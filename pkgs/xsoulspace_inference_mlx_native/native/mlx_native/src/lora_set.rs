//! Swappable adapter set (Line K) — runtime selection over the single-adapter
//! merge in [`crate::lora`].
//!
//! WHY this surface exists: `lora.rs` merges ONE adapter into a base and the
//! merge MUTATES the base weights in place. The product needs several adapters
//! for ONE base (a format adapter, a domain adapter, a repair adapter) that
//! can be selected at runtime and — just as importantly — taken OFF again.
//! In-place merge is exactly what makes that hard: once merged, the base is
//! gone, and "undo" has to be invented.
//!
//! The law this module is built around (MTP-GATES K-G1): **adapter-off == base
//! BYTE-FOR-BYTE**. A cache, a prefix pool, or a host that compares model
//! outputs cannot be built on "close enough", so this module never undoes a
//! merge by subtracting a delta (float subtraction is not the identity) and
//! never re-derives the base by re-reading a checkpoint (the set does not own
//! the store's provenance).
//!
//! ## The swap mechanism, and what it costs
//!
//! `mlx::Array` owns a refcounted handle and frees it on drop — it is NOT
//! `Clone`. So a "pristine copy" of a weight cannot be made by copying the
//! handle, and copying the bytes would add a full extra copy of the touched
//! weights plus a device upload on every restore.
//!
//! Instead the set RETAINS the ORIGINAL base arrays of the weights it
//! touches. A swap is two phases:
//!
//! 1. **compute** — for every pair of the incoming adapter, build the merged
//!    array FROM THE BASE array (wherever the base currently lives: retained
//!    by the set, or still in the store). Nothing is mutated, so a swap that
//!    fails leaves the store exactly as it was.
//! 2. **commit** — move each touched weight's base array to its new home: into
//!    the set when the incoming adapter merges it (the store gets the merged
//!    array), back into the store when it does not (the store gets the
//!    pristine base array).
//!
//! Consequences:
//!
//! * *Exactness is structural, not lucky.* Adapter-off puts the very same
//!   `Array` object back into the store — the one that was there before the
//!   first swap. "Byte-for-byte" is therefore true by construction; there is
//!   no re-materialization to be approximate.
//! * *No compounding.* The merged array is always computed from the base,
//!   never from the live store, so the result depends only on (base, adapter)
//!   and the swap is order-independent.
//! * *Memory*: no copy is made. The price of reversibility is that the base
//!   arrays of the ACTIVE adapter's targets stay resident next to their
//!   merged twins — they would otherwise be freed when the merge replaced
//!   them. That is one extra copy of the active adapter's target weights.
//!   The rejected alternative is keeping only the `B @ A` deltas (nearly
//!   free, but restoring the base by subtraction is inexact and would break
//!   K-G1); a third option — re-reading the base from disk on every swap —
//!   is exact but moves the cost to I/O and needs provenance the set does
//!   not own.
//!
//! ## The base digest gap (known, not hidden)
//!
//! An adapter is trained against ONE base, so the strong form of a cache key
//! is `(base digest, adapter digest)`. [`LoraAdapter`] carries only the
//! ADAPTER digest (of the adapter file bytes); it has no base digest, and
//! adding one would mean changing `lora.rs`, which this line does not do. So
//! the set carries the base binding at the SET level: a caller-supplied
//! `base_id` plus an optional `base_digest` the caller knows (the
//! checkpoint's own digest). The gap that remains: nothing here can PROVE
//! that a given adapter was trained against THIS base — that check is the
//! caller's to make before adding the adapter to a set.
//!
//! ## K-G4 — quantized bases are refused, not approximated
//!
//! A merge into a packed (quantized) weight needs dequantize → merge →
//! requantize, which is a different path with its own quantization error.
//! This module refuses such a base at bind time: every touched base weight
//! must be plain `f32`. The refusal is an error, never a silent skip.
//!
//! ## What this module does NOT claim
//!
//! * **K-G3 (the capability question) is not claimed here.** This surface
//!   proves that an adapter can be selected, swapped and taken off. Whether
//!   an adapter moves a MEASURED TASK METRIC on a base that can do the task
//!   is a different claim, on a real base, with a real task.
//! * **The live prefix cache does not consume [`CacheKey`] yet.** The prefix
//!   pool in `qwen_prefix` is a private module that still keys its entries
//!   on its own `CacheScope { actor, epoch }` string. This module makes the
//!   keying POSSIBLE ([`CacheKey::epoch_token`] is shaped to fill that slot)
//!   — it does not make the live cache invalidate itself. Wiring it is a
//!   change to `qwen_prefix.rs`, which this line does not touch.

use std::collections::HashMap;

use crate::lora::{self, LoraAdapter};
use crate::mlx::{Array, Dtype, Stream};

/// The orientation the host store keeps its weights in.
///
/// The merge arithmetic is orientation-free, but the STORAGE is not: the
/// merge surface writes `[out, in]` weights, while the nursery runtime keeps
/// `[in, out]`. Getting this wrong silently produces a transposed model, so
/// the caller states it once and the set uses it for every merge.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Orientation {
    /// `[out, in]` — the orientation of [`lora::merge`] and of the `params`
    /// map the merge surface writes into.
    OutIn,
    /// `[in, out]` — the orientation the nursery runtime keeps its weights in
    /// (merged with [`lora::merge_transposed`]).
    InOut,
}

/// A content-addressed cache key for the ACTIVE weights of one base.
///
/// Two states of the same base that carry different adapter digests are
/// DIFFERENT models, so a cache entry built under one must never be read
/// under the other. The key therefore carries the adapter digest (and the
/// base binding), and the base state (no adapter) has its own distinct key.
///
/// The key is stable: the same adapter on the same base always yields the
/// same key, so a cache survives a process restart. Invalidation across
/// swaps is handled by the separate, monotonic [`AdapterSet::epoch`].
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct CacheKey {
    base_id: String,
    base_digest: Option<String>,
    /// `None` == the base itself (adapter off).
    adapter_digest: Option<String>,
}

impl CacheKey {
    pub fn base_id(&self) -> &str {
        &self.base_id
    }

    /// The base checkpoint digest, when the caller supplied one.
    pub fn base_digest(&self) -> Option<&str> {
        self.base_digest.as_deref()
    }

    /// The digest of the active adapter; `None` for the base state.
    pub fn adapter_digest(&self) -> Option<&str> {
        self.adapter_digest.as_deref()
    }

    /// True for the "no adapter" state — the base weights themselves.
    pub fn is_base(&self) -> bool {
        self.adapter_digest.is_none()
    }

    /// A stable string a host can drop into its own cache scope.
    ///
    /// It changes when the active adapter changes and does NOT change when
    /// the same adapter is re-selected, so a host that scopes a prefix cache
    /// by this token cannot read a prefix computed under a different adapter.
    ///
    /// The live prefix pool keys its entries on a `CacheScope { actor, epoch }`
    /// string; this token is shaped to fill that slot when the pool is wired
    /// to it (it is not wired yet — see the module docs).
    pub fn epoch_token(&self) -> String {
        match &self.adapter_digest {
            Some(d) => format!("lora:{}:{}", self.base_id, d),
            None => format!("lora:{}:base", self.base_id),
        }
    }
}

/// What a swap changed — the record a caller needs to invalidate caches.
#[derive(Clone, Debug)]
pub struct SwapRecord {
    /// Monotonic generation counter; incremented on EVERY swap, including a
    /// swap back to the base. A cache entry tagged with an older epoch is
    /// stale by construction.
    pub epoch: u64,
    /// The adapter that was active before this swap (`None` == base).
    pub previous: Option<String>,
    /// The adapter active after this swap (`None` == base).
    pub active: Option<String>,
    /// Digest of the active adapter (`None` == base).
    pub digest: Option<String>,
    /// The cache key of the state after this swap.
    pub key: CacheKey,
    /// How many weights were merged (0 for the base state).
    pub applied: usize,
}

/// A registry of named adapters for ONE base, with runtime selection.
///
/// The set owns the SWAP, not the model: the host keeps the weight store and
/// lends it to [`AdapterSet::bind`] and [`AdapterSet::swap`]. Between a bind
/// and the next one, the touched weights of the store belong to the set.
pub struct AdapterSet {
    base_id: String,
    base_digest: Option<String>,
    /// Insertion order, so `names()` is deterministic.
    order: Vec<String>,
    adapters: HashMap<String, LoraAdapter>,
    /// Every weight any adapter touches, in first-seen order.
    touched: Vec<String>,
    /// The base arrays the set RETAINS: those the active adapter merged.
    /// They are the original objects, not copies.
    retained: HashMap<String, Array>,
    active: Option<String>,
    epoch: u64,
    bound: bool,
    orientation: Orientation,
}

impl AdapterSet {
    /// A set bound to one base. `base_id` names the base for cache keys; the
    /// checkpoint digest is optional and can be supplied later with
    /// [`AdapterSet::set_base_digest`].
    pub fn new(base_id: &str) -> Self {
        Self {
            base_id: base_id.to_string(),
            base_digest: None,
            order: Vec::new(),
            adapters: HashMap::new(),
            touched: Vec::new(),
            retained: HashMap::new(),
            active: None,
            epoch: 0,
            bound: false,
            orientation: Orientation::OutIn,
        }
    }

    /// State the base checkpoint digest the caller knows. It enters every
    /// cache key, so a cache built for one base can never be read for another.
    pub fn set_base_digest(&mut self, digest: &str) {
        self.base_digest = Some(digest.to_string());
    }

    /// State the weight orientation of the host store.
    pub fn set_orientation(&mut self, orientation: Orientation) {
        self.orientation = orientation;
    }

    /// Register an adapter under `name`. A duplicate name is an error: two
    /// adapters under one name would make the active adapter ambiguous, and
    /// an ambiguous swap is worse than a refused one.
    ///
    /// Adapters must be added BEFORE [`AdapterSet::bind`]: the set tracks the
    /// union of every adapter's targets, and a target that appears after the
    /// binding cannot be restored exactly.
    pub fn add(&mut self, name: &str, adapter: LoraAdapter) -> Result<(), String> {
        if name.is_empty() {
            return Err("adapter name must not be empty".to_string());
        }
        if self.adapters.contains_key(name) {
            return Err(format!("adapter set already has an adapter named {name}"));
        }
        if self.bound {
            return Err(
                "cannot add an adapter to a bound set: the set tracks the union of \
                 the adapters' targets, and a late target would not be restorable \
                 (build a new set instead)"
                    .to_string(),
            );
        }
        for pair in &adapter.pairs {
            if !self.touched.contains(&pair.target) {
                self.touched.push(pair.target.clone());
            }
        }
        self.order.push(name.to_string());
        self.adapters.insert(name.to_string(), adapter);
        Ok(())
    }

    /// The registered adapter names, in registration order.
    pub fn names(&self) -> Vec<String> {
        self.order.clone()
    }

    /// The adapter registered under `name`.
    pub fn get(&self, name: &str) -> Option<&LoraAdapter> {
        self.adapters.get(name)
    }

    /// The digest of the adapter registered under `name` — the half of the
    /// cache key that changes when the active adapter changes.
    pub fn digest_of(&self, name: &str) -> Option<&str> {
        self.adapters.get(name).map(|a| a.digest.as_str())
    }

    /// The base this set is bound to.
    pub fn base_id(&self) -> &str {
        &self.base_id
    }

    /// The base checkpoint digest, when the caller supplied one.
    pub fn base_digest(&self) -> Option<&str> {
        self.base_digest.as_deref()
    }

    /// The active adapter name (`None` == the base).
    pub fn active(&self) -> Option<&str> {
        self.active.as_deref()
    }

    /// The digest of the active adapter (`None` == the base).
    pub fn active_digest(&self) -> Option<&str> {
        self.active.as_deref().and_then(|n| self.digest_of(n))
    }

    /// The monotonic swap generation. Starts at 0 (never swapped) and is
    /// incremented by EVERY successful swap, including a swap back to the
    /// base. A host that keeps a cache in place across swaps can compare
    /// epochs to know its entries are stale.
    pub fn epoch(&self) -> u64 {
        self.epoch
    }

    /// The cache key of the CURRENT state (the base until something is
    /// swapped on).
    pub fn cache_key(&self) -> CacheKey {
        CacheKey {
            base_id: self.base_id.clone(),
            base_digest: self.base_digest.clone(),
            adapter_digest: self.active_digest().map(str::to_string),
        }
    }

    /// The cache key an adapter WOULD have if it were active. `None` for an
    /// unknown name.
    pub fn key_for(&self, name: &str) -> Option<CacheKey> {
        self.digest_of(name).map(|d| CacheKey {
            base_id: self.base_id.clone(),
            base_digest: self.base_digest.clone(),
            adapter_digest: Some(d.to_string()),
        })
    }

    /// The key of the base state (adapter off).
    pub fn base_key(&self) -> CacheKey {
        CacheKey {
            base_id: self.base_id.clone(),
            base_digest: self.base_digest.clone(),
            adapter_digest: None,
        }
    }

    /// The base array the set retains for `name`, when the active adapter
    /// merged that weight. `None` when the weight is not merged right now
    /// (its base array is in the store).
    pub fn retained_base(&self, name: &str) -> Option<&Array> {
        self.retained.get(name)
    }

    /// Bind the set to a base store.
    ///
    /// The store must hold the BASE weights (no adapter merged yet): those
    /// arrays are what every later merge is computed from and what "adapter
    /// off" restores. Targets absent from the base are a HARD ERROR (the law
    /// the merge surface already enforces), and a target that is not plain
    /// `f32` is REFUSED (K-G4: a merge into a packed weight needs
    /// dequantize → merge → requantize).
    pub fn bind(&mut self, store: &HashMap<String, Array>) -> Result<(), String> {
        if self.bound {
            return Err("adapter set is already bound to a base".to_string());
        }
        // Reused, not reimplemented: a target the base does not have is an
        // error, never a silent skip.
        lora::validate_targets(&self.touched, store)?;
        for target in &self.touched {
            let arr = match store.get(target) {
                Some(a) => a,
                None => return Err(format!("base weight {target} disappeared")),
            };
            if arr.dtype() != Dtype::Float32 {
                return Err(format!(
                    "base weight {target} is {:?} — a merge into a packed weight needs \
                     dequantize -> merge -> requantize, which is a different path; \
                     refused, not approximated",
                    arr.dtype()
                ));
            }
        }
        self.bound = true;
        Ok(())
    }

    /// Whether the set is bound to a base.
    pub fn is_bound(&self) -> bool {
        self.bound
    }

    /// Select an adapter (`None` == adapter off, i.e. the base weights) and
    /// write the result into `store`.
    ///
    /// The merged arrays are computed from the BASE, so the result depends
    /// only on (base, adapter) — never on which adapter was active before.
    /// That is what makes a swap-back land exactly on the base bytes and
    /// what makes the swap order-independent.
    ///
    /// Every touched weight of the store is written on every swap (merged if
    /// the active adapter touches it, pristine if not), so a weight another
    /// adapter had modified is restored rather than left merged.
    pub fn swap(
        &mut self,
        name: Option<&str>,
        store: &mut HashMap<String, Array>,
        s: Stream,
    ) -> Result<SwapRecord, String> {
        if !self.bound {
            return Err(
                "adapter set is not bound to a base: call bind() with the base store \
                 first (an unbound swap could not restore the base)"
                    .to_string(),
            );
        }
        let adapter = match name {
            Some(n) => match self.adapters.get(n) {
                Some(a) => Some((n.to_string(), a)),
                None => return Err(format!("no adapter named {n} in this set")),
            },
            None => None,
        };

        // Every touched weight must be locatable before anything moves.
        for target in &self.touched {
            if !self.retained.contains_key(target) && !store.contains_key(target) {
                return Err(format!("base weight {target} is not in the store"));
            }
        }

        // Compute phase: nothing in the store changes until every merge
        // succeeded, so a failed swap leaves the store as it was.
        let mut merged: HashMap<String, Array> = HashMap::new();
        if let Some((_, a)) = &adapter {
            for pair in &a.pairs {
                let base = match self.retained.get(&pair.target) {
                    Some(b) => b,
                    None => match store.get(&pair.target) {
                        Some(b) => b,
                        None => {
                            return Err(format!(
                                "adapter target {} is not in the base store",
                                pair.target
                            ))
                        }
                    },
                };
                let out = match self.orientation {
                    Orientation::OutIn => lora::merge(base, &pair.a, &pair.b, pair.scale, s),
                    Orientation::InOut => {
                        lora::merge_transposed(base, &pair.a, &pair.b, pair.scale, s)
                    }
                }
                .map_err(|e| format!("merge {}: mlx status {}", pair.target, e.0))?;
                out.eval()
                    .map_err(|e| format!("merge {}: mlx status {}", pair.target, e.0))?;
                merged.insert(pair.target.clone(), out);
            }
        }

        let applied = merged.len();

        // Commit phase: move each touched weight's base array to its new
        // home, and write the merged array where the active adapter applies.
        let touched = self.touched.clone();
        for target in &touched {
            let base = match self.retained.remove(target) {
                Some(b) => b,
                None => match store.remove(target) {
                    Some(b) => b,
                    None => return Err(format!("base weight {target} vanished mid-swap")),
                },
            };
            match merged.remove(target) {
                Some(m) => {
                    store.insert(target.clone(), m);
                    self.retained.insert(target.clone(), base);
                }
                None => {
                    store.insert(target.clone(), base);
                }
            }
        }

        let previous = self.active.clone();
        self.active = adapter.as_ref().map(|(n, _)| n.clone());
        self.epoch += 1;
        Ok(SwapRecord {
            epoch: self.epoch,
            previous,
            active: self.active.clone(),
            digest: self.active_digest().map(str::to_string),
            key: self.cache_key(),
            applied,
        })
    }

    /// Swap the adapter OFF — the base weights, byte-for-byte.
    pub fn swap_to_base(
        &mut self,
        store: &mut HashMap<String, Array>,
        s: Stream,
    ) -> Result<SwapRecord, String> {
        self.swap(None, store, s)
    }
}
