//! Nursery tiny-model runtime (Line I) — the Rust/Metal side of
//! `tool/nursery/model_def.py`'s exact contract.
//!
//! STATUS (2026-10-18): COMPILED and PARITY-TESTED. The cross-language
//! oracle `tests/nursery_model_parity.rs` loads ONLY the packed fixture
//! store (`testdata/nursery_model/`) and reproduces the Python forward's
//! per-position per-layer top-k sets exactly, the greedy bytes and stop
//! reason exactly, and label/lm logits within pinned tolerances. Not yet
//! run on a TRAINED model — the real RUNG-0 checkpoint is still owed
//! (TRAIN-GATES.md launch checklist first). Everything here composes ONLY
//! proven pieces: the digest-verified store reader (`nursery.rs`), the
//! mlx-c binding layer (`mlx.rs`, the same seam qwen/lfm2 run on), and
//! the parity-pinned quantized_matmul path (qwen.rs).
//!
//! The mirrored contract (model_def.py is the ONE definition):
//! - carry-state linear attention, READ-THEN-UPDATE (BOS sees the empty
//!   state): `y_t = q_t · S_{t-1}; S_t = decay ⊙ S_{t-1} + outer(k_t, v_t)`,
//!   decay per channel through sigmoid;
//! - per block: `x += Wo·attn(rms(x))` then `x += MoE(rms(x))`;
//! - router logits fp32 end-to-end (PORTING-MOE.md law — enforced at load:
//!   a store whose router tensor is not float32 is REJECTED);
//! - top-k selection: k largest by value, ties to the LOWER index, returned
//!   ascending (`top_k` below is line-for-line the py rule);
//! - combine weights = softmax over the selected logits; expert =
//!   `down(silu(gate(h)) * up(h))`.
//!
//! Runge-0 scope (deliberate): the whole model is resident after load —
//! the store path still exercises pack-at-birth, full digest verification
//! and addressable point reads, but expert paging/route plans are RUNG-3
//! work. Embed/norm/heads are plain (non-quantized) only; a quantized one
//! is a hard, named error, not a silent path.

use crate::mlx::{self, Array, Dtype, Stream};
use crate::nursery::{Manifest, NurseryStore, Tensor};
use std::path::Path;

pub const BOS: usize = 256;
pub const EOS: usize = 257;

pub struct NurseryModelConfig {
    pub hidden_size: usize,
    pub layers: usize,
    pub experts: usize,
    pub topk: usize,
    pub intermediate: usize,
    pub vocab_size: usize,
    pub rms_norm_eps: f32,
    /// routing-window A/B arm (model_def.py): the expert SET re-decides
    /// every `routing_window` positions; 1 = per-token (default, so older
    /// configs without the key load unchanged).
    pub routing_window: usize,
    pub label_kinds: Vec<String>,
}

impl NurseryModelConfig {
    /// config.json rides inside the store manifest (`source.config`) — the
    /// packed store is the only thing the runtime opens.
    pub fn from_manifest(manifest: &Manifest) -> Result<Self, String> {
        let c = manifest
            .source
            .get("config")
            .ok_or("manifest source.config missing — not a nursery checkpoint store")?;
        let get = |key: &str| -> Result<serde_json::Value, String> {
            c.get(key)
                .cloned()
                .ok_or_else(|| format!("config missing {key}"))
        };
        let usize_of = |key: &str| -> Result<usize, String> {
            get(key)?
                .as_u64()
                .map(|v| v as usize)
                .ok_or_else(|| format!("config {key} is not an integer"))
        };
        Ok(Self {
            hidden_size: usize_of("hidden_size")?,
            layers: usize_of("num_hidden_layers")?,
            experts: usize_of("num_experts")?,
            topk: usize_of("num_experts_per_tok")?,
            intermediate: usize_of("moe_intermediate_size")?,
            vocab_size: usize_of("vocab_size")?,
            rms_norm_eps: get("rms_norm_eps")?
                .as_f64()
                .ok_or_else(|| "config rms_norm_eps is not a number".to_string())?
                as f32,
            routing_window: get("routing_window")
                .ok()
                .and_then(|v| v.as_u64())
                .map(|v| v as usize)
                .unwrap_or(1)
                .max(1),
            label_kinds: get("label_kinds")?
                .as_array()
                .map(|a| {
                    a.iter()
                        .filter_map(|v| v.as_str().map(str::to_string))
                        .collect()
                })
                .ok_or_else(|| "config label_kinds is not a list".to_string())?,
        })
    }
}

/// One weight in store orientation or pre-transposed for matmul.
enum NWeight {
    /// `[in, out]` — transposed once at load, evaluated once at load so a
    /// broken store fails at load, not mid-generate.
    Plain { wt: Array },
    Quant {
        w: Array,
        scales: Array,
        biases: Array,
    },
}

impl NWeight {
    /// The `[in, out]` array when this weight is plain f32 — the only shape a
    /// LoRA merge can touch. Quantized weights return None: merging into a
    /// packed weight needs dequantize → merge → requantize, which is a
    /// different path and is refused rather than approximated.
    fn plain_mut(&mut self) -> Option<&mut Array> {
        match self {
            NWeight::Plain { wt } => Some(wt),
            NWeight::Quant { .. } => None,
        }
    }
}

struct Expert {
    gate: NWeight,
    up: NWeight,
    down: NWeight,
}

struct NurseryLayer {
    ln1: Array,
    ln2: Array,
    q: Array,
    k: Array,
    v: Array,
    o: Array,
    decay: Array,
    router: Array, // Plain, pre-transposed [H, E]
    experts: Vec<Expert>,
}

pub struct NurseryModel {
    #[allow(dead_code)] // held for the manifest; tensors are resident
    store: NurseryStore,
    cfg: NurseryModelConfig,
    embed: Array,        // [V, H]
    norm: Array,         // [H]
    lm_head: NWeight,    // [V, H] (pre-transposed to [H, V] when plain)
    label_head: NWeight, // [K, H] (pre-transposed to [H, K] when plain)
    layers: Vec<NurseryLayer>,
    group_size: i32,
    bits: i32,
}

/// One (layer, selected experts) decision at one position — the GATE-2 row
/// shape (`{"pos", "layer", "experts"}`), so a runtime trace is analyzable
/// by the frozen gate2 oracle AND bench/stage1_paged_moe/analyze_routes.py.
#[derive(serde::Serialize, Clone)]
pub struct RouteRow {
    pub pos: usize,
    pub layer: usize,
    pub experts: Vec<usize>,
}

pub struct StepOut {
    /// Final-head logits over the whole vocab (f32 host copy).
    pub logits: Vec<f32>,
    /// Label-head logits, config label_kinds order (GATE-3 behavior).
    pub label_logits: Vec<f32>,
    /// This step's routing decisions, one row per layer.
    pub routes: Vec<RouteRow>,
}

/// Store bytes -> mlx array, exact dtypes only. float16/bfloat16 keep their
/// raw LE bytes (mlx native dtypes); uint32 is the packed-quant path.
fn make_array(t: &Tensor) -> Result<Array, String> {
    let expect = t.elements();
    match t.dtype.as_str() {
        "float32" => {
            if t.data.len() != expect * 4 {
                return Err(format!("float32 byte count mismatch for shape {:?}", t.shape));
            }
            let v: Vec<f32> = t
                .data
                .chunks_exact(4)
                .map(|c| f32::from_le_bytes([c[0], c[1], c[2], c[3]]))
                .collect();
            Array::from_data_f32(&v, &t.shape).map_err(|e| format!("mlx status {}", e.0))
        }
        "float16" => {
            if t.data.len() != expect * 2 {
                return Err(format!("float16 byte count mismatch for shape {:?}", t.shape));
            }
            Array::from_data_f16(&t.data, &t.shape).map_err(|e| format!("mlx status {}", e.0))
        }
        "bfloat16" => {
            if t.data.len() != expect * 2 {
                return Err(format!("bfloat16 byte count mismatch for shape {:?}", t.shape));
            }
            Array::from_data_bf16(&t.data, &t.shape).map_err(|e| format!("mlx status {}", e.0))
        }
        "uint32" => {
            if t.data.len() != expect * 4 {
                return Err(format!("uint32 byte count mismatch for shape {:?}", t.shape));
            }
            let v: Vec<u32> = t
                .data
                .chunks_exact(4)
                .map(|c| u32::from_le_bytes([c[0], c[1], c[2], c[3]]))
                .collect();
            Array::from_data_u32(&v, &t.shape).map_err(|e| format!("mlx status {}", e.0))
        }
        other => Err(format!(
            "dtype {other} has no nursery runtime array path (expected float32/float16/bfloat16/uint32)"
        )),
    }
}

impl NurseryModel {
    /// Opens the store, digest-verifies EVERY segment (hard error on any
    /// mismatch — the trust model of everything below), then reads every
    /// tensor by canonical name. A store that does not match model_def.py's
    /// naming fails here with the missing name, never silently.
    pub fn load(model_dir: &Path) -> Result<Self, String> {
        let mut store = NurseryStore::open(model_dir)?;
        store.verify_all()?;
        let cfg = NurseryModelConfig::from_manifest(&store.manifest)?;
        let s = mlx::gpu().map_err(|e| format!("gpu init failed: mlx status {}", e.0))?;

        let (group_size, bits) = match &store.manifest.quantization {
            Some(q) => (q.group_size as i32, q.bits as i32),
            None => (0, 0),
        };

        fn plain_tensor(store: &mut NurseryStore, name: &str, s: Stream) -> Result<Array, String> {
            if store.tensor_meta(&format!("{name}.scales")).is_some() {
                return Err(format!(
                    "quantized {name} not supported by the nursery runtime yet \
                     (rung-0 saves f32); extend NWeight when a packed rung ships"
                ));
            }
            let t = store.read_tensor(&format!("{name}.weight"))?;
            let arr = make_array(&t)?;
            if t.dtype != "float32" {
                // Small tensors saved narrower than f32 (f16 norms/decay are
                // the fixture's own paths) widen once at load so every
                // downstream op sees one dtype.
                let wide = arr
                    .astype(Dtype::Float32, s)
                    .map_err(|e| format!("{name}: widen failed: mlx status {}", e.0))?;
                wide.eval()
                    .map_err(|e| format!("{name}: eval failed: mlx status {}", e.0))?;
                return Ok(wide);
            }
            Ok(arr)
        }

        fn load_weight(
            store: &mut NurseryStore,
            name: &str,
            group_size: i32,
            _bits: i32,
            s: Stream,
        ) -> Result<NWeight, String> {
            if store.tensor_meta(&format!("{name}.scales")).is_some() {
                if group_size == 0 {
                    return Err(format!(
                        "quantized {name} but manifest carries no quantization block"
                    ));
                }
                let w = make_array(&store.read_tensor(name)?)?;
                let scales = make_array(&store.read_tensor(&format!("{name}.scales"))?)?;
                let biases = make_array(&store.read_tensor(&format!("{name}.biases"))?)?;
                return Ok(NWeight::Quant { w, scales, biases });
            }
            let arr = make_array(&store.read_tensor(&format!("{name}.weight"))?)?;
            let wt = arr
                .transpose_axes(&[1, 0], s)
                .map_err(|e| format!("{name}: transpose failed: mlx status {}", e.0))?;
            wt.eval()
                .map_err(|e| format!("{name}: eval failed: mlx status {}", e.0))?;
            Ok(NWeight::Plain { wt })
        }

        // The router law, enforced where it binds: fp32 or the store is
        // refused (PORTING-MOE.md — routes flip at fp16 quantization noise).
        for l in 0..cfg.layers {
            let name = format!("model.layers.{l}.mlp.gate.weight");
            let meta = store
                .tensor_meta(&name)
                .ok_or_else(|| format!("store has no router tensor {name}"))?;
            if meta.dtype != "float32" {
                return Err(format!(
                    "router {name} is dtype {}, law requires float32 (PORTING-MOE.md)",
                    meta.dtype
                ));
            }
        }

        let embed = plain_tensor(&mut store, "model.embed_tokens", s)?;
        let norm = plain_tensor(&mut store, "model.norm", s)?;
        let lm_head = load_weight(&mut store, "model.lm_head", group_size, bits, s)?;
        let label_head = load_weight(&mut store, "model.label_head", group_size, bits, s)?;

        let mut layers = Vec::with_capacity(cfg.layers);
        for l in 0..cfg.layers {
            let p = format!("model.layers.{l}");
            let ln1 = plain_tensor(&mut store, &format!("{p}.input_layernorm"), s)?;
            let ln2 = plain_tensor(&mut store, &format!("{p}.post_attention_layernorm"), s)?;
            let q = plain_tensor(&mut store, &format!("{p}.self_attn.q_proj"), s)?;
            let k = plain_tensor(&mut store, &format!("{p}.self_attn.k_proj"), s)?;
            let v = plain_tensor(&mut store, &format!("{p}.self_attn.v_proj"), s)?;
            let o = plain_tensor(&mut store, &format!("{p}.self_attn.o_proj"), s)?;
            let decay = plain_tensor(&mut store, &format!("{p}.self_attn.decay"), s)?;
            let router = plain_tensor(&mut store, &format!("{p}.mlp.gate"), s)?;
            // attn projections are used as [in,out] after one transpose
            // (store orientation is [out,in]); heads keep NWeight.
            let tr = |a: Array| -> Result<Array, String> {
                let wt = a
                    .transpose_axes(&[1, 0], s)
                    .map_err(|e| format!("transpose failed: mlx status {}", e.0))?;
                wt.eval()
                    .map_err(|e| format!("eval failed: mlx status {}", e.0))?;
                Ok(wt)
            };
            let (q, k, v, o) = (tr(q)?, tr(k)?, tr(v)?, tr(o)?);
            let router = tr(router)?;
            let mut experts = Vec::with_capacity(cfg.experts);
            for e in 0..cfg.experts {
                let b = format!("{p}.mlp.experts.{e}");
                experts.push(Expert {
                    gate: load_weight(&mut store, &format!("{b}.gate_proj"), group_size, bits, s)?,
                    up: load_weight(&mut store, &format!("{b}.up_proj"), group_size, bits, s)?,
                    down: load_weight(&mut store, &format!("{b}.down_proj"), group_size, bits, s)?,
                });
            }
            layers.push(NurseryLayer {
                ln1,
                ln2,
                q,
                k,
                v,
                o,
                decay,
                router,
                experts,
            });
        }

        Ok(Self {
            store,
            cfg,
            embed,
            norm,
            lm_head,
            label_head,
            layers,
            group_size,
            bits,
        })
    }

    /// Load the store, then merge a LoRA adapter into it.
    ///
    /// The adapter is applied ONCE at load, not per token: on this device
    /// decode is memory-bound, so a merged weight costs nothing extra while a
    /// per-token `W + BA` would re-read A and B on every forward.
    ///
    /// A merged weight set is a DIFFERENT model — every cached prefix
    /// computed under the base is stale. Callers that cache must key on the
    /// adapter digest (`LoraAdapter::digest`).
    ///
    /// The adapter's on-disk format is DETECTED (`LoraAdapter::load_auto`):
    /// both the PEFT layout and the mlx-lm layout the Python tuner actually
    /// writes are accepted, and a file in neither layout is REFUSED rather
    /// than read as one of them. C-10 was exactly this: the surface could
    /// only read the format the lane did not train.
    pub fn load_with_adapter(
        model_dir: &Path,
        adapter_path: &Path,
        scale: f32,
    ) -> Result<Self, String> {
        let mut model = Self::load(model_dir)?;
        let s = mlx::gpu().map_err(|e| format!("gpu init failed: mlx status {}", e.0))?;
        let adapter = crate::lora::LoraAdapter::load_auto(adapter_path, scale, s)?;
        let applied = model.apply_adapter(&adapter, s)?;
        if applied == 0 {
            return Err("adapter applied to zero weights".to_string());
        }
        Ok(model)
    }

    /// Merge every adapter pair into the resident weights.
    ///
    /// A target the model does not have is a HARD ERROR, never a skip: a
    /// silently-unapplied adapter is the failure mode this surface exists to
    /// prevent. Quantized weights are refused for the same reason (a merge
    /// into a packed weight would need dequantize → merge → requantize).
    pub fn apply_adapter(
        &mut self,
        adapter: &crate::lora::LoraAdapter,
        s: Stream,
    ) -> Result<usize, String> {
        let mut applied = 0;
        for pair in &adapter.pairs {
            let name = pair
                .target
                .strip_suffix(".weight")
                .unwrap_or(&pair.target)
                .to_string();
            let Some(arr) = self.weight_mut(&name) else {
                return Err(format!(
                    "adapter targets {name}: not present as a plain f32 weight \
                     (missing, or quantized — a merge requires f32)"
                ));
            };
            let merged = crate::lora::merge_transposed(arr, &pair.a, &pair.b, pair.scale, s)
                .map_err(|e| format!("merge {name}: mlx status {}", e.0))?;
            merged
                .eval()
                .map_err(|e| format!("merge {name}: mlx status {}", e.0))?;
            *arr = merged;
            applied += 1;
        }
        Ok(applied)
    }

    /// Resolve a canonical weight name to its `[in, out]` array.
    ///
    /// Only the weights a LoRA realistically targets are addressable: the
    /// attention projections, the expert MLPs, and the two heads. Everything
    /// else (norms, decay, router) is deliberately not — adapting a router
    /// would break the fp32 router law, and adapting a norm is not a LoRA.
    fn weight_mut(&mut self, name: &str) -> Option<&mut Array> {
        if name == "model.lm_head" {
            return self.lm_head.plain_mut();
        }
        if name == "model.label_head" {
            return self.label_head.plain_mut();
        }
        let rest = name.strip_prefix("model.layers.")?;
        let (l, tail) = rest.split_once('.')?;
        let l: usize = l.parse().ok()?;
        let layer = self.layers.get_mut(l)?;
        if let Some(proj) = tail.strip_prefix("self_attn.") {
            let proj = proj.strip_suffix("_proj")?;
            return match proj {
                "q" => Some(&mut layer.q),
                "k" => Some(&mut layer.k),
                "v" => Some(&mut layer.v),
                "o" => Some(&mut layer.o),
                _ => None,
            };
        }
        if let Some(rest) = tail.strip_prefix("mlp.experts.") {
            let (e, proj) = rest.split_once('.')?;
            let e: usize = e.parse().ok()?;
            let proj = proj.strip_suffix("_proj")?;
            let expert = layer.experts.get_mut(e)?;
            return match proj {
                "gate" => expert.gate.plain_mut(),
                "up" => expert.up.plain_mut(),
                "down" => expert.down.plain_mut(),
                _ => None,
            };
        }
        None
    }

    pub fn config(&self) -> &NurseryModelConfig {
        &self.cfg
    }

    fn linear(&self, w: &NWeight, x: &Array, s: Stream) -> Result<Array, String> {
        match w {
            NWeight::Plain { wt } => x
                .matmul(wt, s)
                .map_err(|e| format!("matmul: mlx status {}", e.0)),
            NWeight::Quant { w, scales, biases } => {
                Array::quantized_matmul(x, w, scales, biases, true, self.group_size, self.bits, s)
                    .map_err(|e| format!("quantized_matmul: mlx status {}", e.0))
            }
        }
    }

    fn expert_mlp(&self, e: &Expert, h2: &Array, s: Stream) -> Result<Array, String> {
        let g = self.linear(&e.gate, h2, s)?; // [1, F]
        let g = g
            .sigmoid(s)
            .and_then(|sig| g.mul(&sig, s))
            .map_err(|e| format!("silu: mlx status {}", e.0))?;
        let u = self.linear(&e.up, h2, s)?; // [1, F]
        let h = g
            .mul(&u, s)
            .map_err(|e| format!("gated mul: mlx status {}", e.0))?;
        self.linear(&e.down, &h, s) // [1, H]
    }

    /// One decode step for `token` (a byte 0..256, or BOS/EOS). `states`
    /// carries one [H, H] attention state per layer; `routing` carries one
    /// optional cached expert set per layer (the routing-window A/B arm,
    /// model_def `routing_window`: the set re-decides when
    /// `pos % window == 0` or the cache is cold). Pass fresh vectors from
    /// `fresh_states`/`fresh_routing` to start a sequence. The recurrence
    /// is read-then-update — identical order to model_def.forward_sequence.
    pub fn forward_step(
        &self,
        token: usize,
        states: &mut [Array],
        routing: &mut [Option<Vec<usize>>],
        pos: usize,
        s: Stream,
    ) -> Result<StepOut, String> {
        let h = self.cfg.hidden_size;
        let mut x = gather_row(&self.embed, self.cfg.vocab_size, token, h, s)?; // [1, H]

        let mut routes = Vec::with_capacity(self.cfg.layers);
        for (l, lay) in self.layers.iter().enumerate() {
            // ---- carry-state linear attention (read-then-update) ----
            let h1 = Array::rms_norm(&x, &lay.ln1, self.cfg.rms_norm_eps, s)
                .map_err(|e| format!("rms: mlx status {}", e.0))?;
            let q = h1.matmul(&lay.q, s).map_err(mperf("q"))?; // [1, H]
            let k = h1.matmul(&lay.k, s).map_err(mperf("k"))?;
            let v = h1.matmul(&lay.v, s).map_err(mperf("v"))?;
            let decay = lay
                .decay
                .sigmoid(s)
                .map_err(|e| format!("decay sigmoid: mlx status {}", e.0))?;
            let y = q.matmul(&states[l], s).map_err(mperf("state read"))?; // [1, H]
            let k_col = k.reshape(&[h, 1], s).map_err(mperf("k reshape"))?;
            let v_row = v.reshape(&[1, h], s).map_err(mperf("v reshape"))?;
            let outer = k_col.mul(&v_row, s).map_err(mperf("outer"))?; // [H, H]
            let decay_row = decay.reshape(&[1, h], s).map_err(mperf("decay reshape"))?;
            let decayed = states[l].mul(&decay_row, s).map_err(mperf("decay mul"))?;
            states[l] = decayed.add(&outer, s).map_err(mperf("state update"))?;
            let attn = y.matmul(&lay.o, s).map_err(mperf("o"))?;
            x = x.add(&attn, s).map_err(mperf("attn residual"))?;

            // ---- MoE ----
            let h2 = Array::rms_norm(&x, &lay.ln2, self.cfg.rms_norm_eps, s)
                .map_err(|e| format!("rms2: mlx status {}", e.0))?;
            let rlogits = h2
                .matmul(&lay.router, s)
                .and_then(|r| r.astype(Dtype::Float32, s))
                .map_err(|e| format!("router: mlx status {}", e.0))?; // [1, E]
            let rv = rlogits
                .to_f32_vec(s)
                .map_err(|e| format!("router readback: mlx status {}", e.0))?;
            if rv.iter().any(|v| !v.is_finite()) {
                return Err(format!(
                    "layer {l} router logits not finite at pos {pos} — refusing to route"
                ));
            }
            let window = self.cfg.routing_window;
            if routing[l].is_none() || pos % window == 0 {
                routing[l] = Some(top_k(&rv, self.cfg.topk));
            }
            let sel = routing[l]
                .clone()
                .expect("routing cache just written above");
            let sel_vals: Vec<f32> = sel.iter().map(|&e| rv[e]).collect();
            let sel_arr = Array::from_data_f32(&sel_vals, &[sel.len()])
                .map_err(|e| format!("sel arr: mlx status {}", e.0))?;
            let w = sel_arr
                .softmax(s)
                .map_err(|e| format!("gate softmax: mlx status {}", e.0))?;
            let wv = w
                .to_f32_vec(s)
                .map_err(|e| format!("gate readback: mlx status {}", e.0))?;
            let mut acc =
                Array::full_f32(0.0, &[1, h], s).map_err(|e| format!("acc: mlx status {}", e.0))?;
            for (j, &e) in sel.iter().enumerate() {
                let d = self.expert_mlp(&lay.experts[e], &h2, s)?; // [1, H]
                let scaled = d
                    .mul(&Array::scalar_f32(wv[j]), s)
                    .map_err(mperf("combine"))?;
                acc = acc.add(&scaled, s).map_err(mperf("combine add"))?;
            }
            x = x.add(&acc, s).map_err(mperf("moe residual"))?;
            routes.push(RouteRow {
                pos,
                layer: l,
                experts: sel,
            });
        }

        let t = Array::rms_norm(&x, &self.norm, self.cfg.rms_norm_eps, s)
            .map_err(|e| format!("final rms: mlx status {}", e.0))?;
        let logits = self.linear(&self.lm_head, &t, s)?; // [1, V]
        let label = self.linear(&self.label_head, &t, s)?; // [1, K]
        Ok(StepOut {
            logits: logits
                .to_f32_vec(s)
                .map_err(|e| format!("logits readback: mlx status {}", e.0))?,
            label_logits: label
                .to_f32_vec(s)
                .map_err(|e| format!("label readback: mlx status {}", e.0))?,
            routes,
        })
    }

    /// Zero states for a fresh sequence ([H, H] per layer).
    pub fn fresh_states(&self, s: Stream) -> Result<Vec<Array>, String> {
        (0..self.cfg.layers)
            .map(|_| {
                Array::full_f32(0.0, &[self.cfg.hidden_size, self.cfg.hidden_size], s)
                    .map_err(|e| format!("zero state: mlx status {}", e.0))
            })
            .collect()
    }

    /// Cold routing-window caches (one slot per layer).
    pub fn fresh_routing(&self) -> Vec<Option<Vec<usize>>> {
        vec![None; self.cfg.layers]
    }

    /// Greedy byte generation: BOS, then the prompt bytes, then up to
    /// `max_new` argmax bytes (tie -> lower id, the py rule), stopping at
    /// EOS. Routes are captured for EVERY step (prefill included) so a
    /// runtime trace is a complete GATE-2 input.
    pub fn generate(
        &self,
        prompt_bytes: &[u8],
        max_new: usize,
        s: Stream,
    ) -> Result<GenerateOutcome, String> {
        let mut states = self.fresh_states(s)?;
        let mut routing = self.fresh_routing();
        let mut routes = Vec::new();
        let mut label_logits = Vec::new();
        let mut last_logits = Vec::new();

        let step_once = |token: usize,
                         states: &mut Vec<Array>,
                         routing: &mut Vec<Option<Vec<usize>>>,
                         pos: usize,
                         routes: &mut Vec<RouteRow>,
                         label_logits: &mut Vec<f32>,
                         last_logits: &mut Vec<f32>|
         -> Result<usize, String> {
            let out = self.forward_step(token, states, routing, pos, s)?;
            let next = argmax(&out.logits)?;
            routes.extend(out.routes);
            *label_logits = out.label_logits;
            *last_logits = out.logits;
            Ok(next)
        };

        let mut next = step_once(
            BOS,
            &mut states,
            &mut routing,
            0,
            &mut routes,
            &mut label_logits,
            &mut last_logits,
        )?;
        for (i, &b) in prompt_bytes.iter().enumerate() {
            next = step_once(
                b as usize,
                &mut states,
                &mut routing,
                i + 1,
                &mut routes,
                &mut label_logits,
                &mut last_logits,
            )?;
        }
        let mut emitted = Vec::with_capacity(max_new);
        let mut stop_reason = "max_new";
        for n in 0..max_new {
            if next == EOS {
                stop_reason = "eos";
                break;
            }
            emitted.push(next as u8);
            next = step_once(
                next,
                &mut states,
                &mut routing,
                prompt_bytes.len() + 1 + n,
                &mut routes,
                &mut label_logits,
                &mut last_logits,
            )?;
        }
        Ok(GenerateOutcome {
            emitted,
            routes,
            label_logits,
            last_logits,
            stop_reason,
        })
    }
}

pub struct GenerateOutcome {
    pub emitted: Vec<u8>,
    pub routes: Vec<RouteRow>,
    pub label_logits: Vec<f32>,
    /// The final step's whole-vocab logits (the step that fed the last
    /// non-EOS token) — the cross-language parity anchor.
    pub last_logits: Vec<f32>,
    pub stop_reason: &'static str,
}

fn mperf(name: &'static str) -> impl Fn(mlx::MlxError) -> String {
    move |e| format!("{name}: mlx status {}", e.0)
}

/// One embedding row gather: [rows, cols] table, row index -> [1, cols].
/// Plain `take` with no axis FLATTENS the source (mlx semantics — the
/// qwen.rs gather_rows comment paid for this), so the row index is turned
/// into explicit flat column indices and the output shape comes from the
/// indices' shape.
fn gather_row(
    table: &Array,
    rows: usize,
    row: usize,
    cols: usize,
    s: Stream,
) -> Result<Array, String> {
    let flat = table
        .reshape(&[rows * cols], s)
        .map_err(mperf("gather reshape"))?;
    let base =
        Array::from_data_i32(&[(row * cols) as i32], &[1, 1]).map_err(mperf("gather base"))?;
    let col_idx = Array::arange_i32(0, cols as i32, s).map_err(mperf("gather cols"))?;
    let idx = base.add(&col_idx, s).map_err(mperf("gather idx"))?; // [1, cols]
    flat.take(&idx, s).map_err(mperf("gather take"))
}

/// THE shared selection rule (model_def.top_k_experts): k largest by value,
/// ties to the LOWER index, returned ascending. Router logits are checked
/// finite before this runs.
fn top_k(vals: &[f32], k: usize) -> Vec<usize> {
    let mut order: Vec<usize> = (0..vals.len()).collect();
    order.sort_by(|&a, &b| {
        vals[b]
            .partial_cmp(&vals[a])
            .unwrap_or(std::cmp::Ordering::Equal)
            .then(a.cmp(&b))
    });
    let mut sel = order.into_iter().take(k).collect::<Vec<usize>>();
    sel.sort_unstable();
    sel
}

/// Deterministic argmax: highest value, ties to the lower index.
fn argmax(vals: &[f32]) -> Result<usize, String> {
    if vals.is_empty() {
        return Err("argmax over empty logits".to_string());
    }
    let mut best = 0usize;
    for i in 1..vals.len() {
        if vals[i] > vals[best] {
            best = i;
        }
    }
    Ok(best)
}
