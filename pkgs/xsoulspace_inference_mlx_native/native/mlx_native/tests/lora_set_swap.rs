//! Line K gates for the swappable adapter set (`mtp-gates` K-G1 … K-G4).
//!
//! These tests are SYNTHETIC on purpose: no checkpoint, no snapshot, no
//! network — small tensors built in memory, so the properties under test
//! (exact reversal, key separation, hard errors) are proven independently of
//! any model's behaviour. A capability claim (K-G3) is a different thing
//! entirely and is NOT made here: proving that an adapter moves a measured
//! task metric needs a real base that can do the task.
//!
//! The assertions are exact: weights and outputs are compared BIT-FOR-BIT
//! (f32 bit patterns, not tolerances), because the law is "adapter-off ==
//! base byte-for-byte" and a tolerance would hide a broken restore.

use std::collections::HashMap;

use mlx_native::lora::{LoraAdapter, LoraPair};
use mlx_native::lora_set::{AdapterSet, CacheKey};
use mlx_native::mlx::{self, Array, Stream};

const Q_PROJ: &str = "model.layers.0.self_attn.q_proj.weight";
const UP_PROJ: &str = "model.layers.0.mlp.experts.0.up_proj.weight";

/// A live Metal stream. The crate's parity suite already requires one (see
/// `nursery_model_parity`), so this test fails loudly rather than skipping
/// when the machine has no GPU: a silently-skipped gate is not a gate.
fn stream() -> Stream {
    // Test binaries don't sit beside the metallib; pin the cmake-built one
    // (the l0/gpu_tests pattern — without it mlx loads a foreign build's
    // kernels and aborts in stream setup).
    let metallib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        mlx::set_metallib_path(&metallib).expect("metallib pin");
    }
    mlx::gpu().expect("gpu stream")
}

/// f32 bit patterns — "byte-for-byte" means the bits, not a tolerance.
fn bits(values: &[f32]) -> Vec<u32> {
    values.iter().map(|v| v.to_bits()).collect()
}

fn array(data: &[f32], shape: &[usize]) -> Array {
    Array::from_data_f32(data, shape).expect("synthetic array")
}

/// The synthetic base: two weights in the merge surface's `[out, in]`
/// orientation, with distinct values so a wrong restore is visible.
fn synthetic_base() -> HashMap<String, Array> {
    let mut store = HashMap::new();
    store.insert(
        Q_PROJ.to_string(),
        array(
            &[
                1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0,
            ],
            &[3, 4],
        ),
    );
    store.insert(
        UP_PROJ.to_string(),
        array(&[100.0, 101.0, 102.0, 103.0, 104.0, 105.0], &[2, 3]),
    );
    store
}

/// Adapter A: touches q_proj only.
fn adapter_a() -> LoraAdapter {
    LoraAdapter {
        pairs: vec![LoraPair {
            target: Q_PROJ.to_string(),
            // a: [r, in] = [2, 4]
            a: array(&[1.0, 0.0, 0.0, 1.0, 0.5, 0.5, 0.5, 0.5], &[2, 4]),
            // b: [out, r] = [3, 2]
            b: array(&[1.0, 0.0, 2.0, 0.0, 0.0, 1.0], &[3, 2]),
            scale: 1.0,
        }],
        digest: mlx_native::nursery::sha256_hex(b"synthetic-adapter-A"),
    }
}

/// Adapter B: touches q_proj AND up_proj — so a swap has to restore the
/// weights the previous adapter touched but this one does not.
fn adapter_b() -> LoraAdapter {
    LoraAdapter {
        pairs: vec![
            LoraPair {
                target: Q_PROJ.to_string(),
                a: array(&[0.0, 1.0, 1.0, 0.0, 1.0, 0.0, 0.0, 1.0], &[2, 4]),
                b: array(&[0.0, 1.0, 1.0, 1.0, 0.0, 2.0], &[3, 2]),
                scale: 0.5,
            },
            LoraPair {
                target: UP_PROJ.to_string(),
                a: array(&[1.0, 1.0, 0.0, 0.0, 1.0, 1.0], &[2, 3]),
                b: array(&[1.0, 1.0, 2.0, 0.0], &[2, 2]),
                scale: 1.0,
            },
        ],
        digest: mlx_native::nursery::sha256_hex(b"synthetic-adapter-B"),
    }
}

/// An adapter whose target the base does not have.
fn adapter_missing_target() -> LoraAdapter {
    LoraAdapter {
        pairs: vec![LoraPair {
            target: "model.layers.9.self_attn.q_proj.weight".to_string(),
            a: array(&[1.0, 0.0, 0.0, 1.0], &[2, 2]),
            b: array(&[1.0, 0.0, 0.0, 1.0], &[2, 2]),
            scale: 1.0,
        }],
        digest: mlx_native::nursery::sha256_hex(b"synthetic-adapter-missing"),
    }
}

/// One forward step of the synthetic model: `x @ W^T` over one weight.
///
/// The store keeps `[out, in]` (the merge surface's orientation), so the
/// probe transposes the weight to feed it as `[in, out]`.
fn forward(store: &HashMap<String, Array>, name: &str, x: &[f32], s: Stream) -> Vec<f32> {
    let w = store.get(name).expect("weight present in the store");
    let wt = w.transpose_axes(&[1, 0], s).expect("transpose");
    let probe = array(x, &[1, x.len()]);
    let y = probe.matmul(&wt, s).expect("matmul");
    y.eval().expect("eval");
    y.to_f32_vec(s).expect("read back")
}

fn weight_bits(store: &HashMap<String, Array>, name: &str, s: Stream) -> Vec<u32> {
    let w = store.get(name).expect("weight present in the store");
    bits(&w.to_f32_vec(s).expect("read back"))
}

#[test]
fn k_g1_swap_is_real_and_reversible() {
    let s = stream();
    let mut store = synthetic_base();
    let base_q = weight_bits(&store, Q_PROJ, s);
    let base_up = weight_bits(&store, UP_PROJ, s);
    let base_out = forward(&store, Q_PROJ, &[0.5, -1.0, 2.0, 0.25], s);

    let mut set = AdapterSet::new("synthetic-base");
    set.add("a", adapter_a()).expect("adapter a registers");
    set.add("b", adapter_b()).expect("adapter b registers");
    set.bind(&store).expect("set binds to the base");

    // --- adapter A on ---
    let rec_a = set.swap(Some("a"), &mut store, s).expect("swap to a");
    assert_eq!(rec_a.active.as_deref(), Some("a"), "A is active");
    assert_eq!(rec_a.previous, None, "nothing was active before");
    assert_eq!(rec_a.epoch, 1, "the first swap is epoch 1");
    assert_eq!(rec_a.applied, 1, "A touches one weight");
    let out_a = forward(&store, Q_PROJ, &[0.5, -1.0, 2.0, 0.25], s);
    assert_ne!(
        bits(&out_a),
        bits(&base_out),
        "adapter-on must change the output (K-G1)"
    );
    assert_ne!(
        weight_bits(&store, Q_PROJ, s),
        base_q,
        "adapter-on must change the merged weight"
    );
    assert_eq!(
        weight_bits(&store, UP_PROJ, s),
        base_up,
        "a weight the adapter does not touch stays the base weight"
    );

    // --- adapter B on ---
    let rec_b = set.swap(Some("b"), &mut store, s).expect("swap to b");
    assert_eq!(rec_b.active.as_deref(), Some("b"), "B is active");
    assert_eq!(
        rec_b.previous.as_deref(),
        Some("a"),
        "the swap records the previous adapter"
    );
    assert_eq!(rec_b.epoch, 2, "the epoch increments on every swap");
    assert_eq!(rec_b.applied, 2, "B touches two weights");
    let out_b = forward(&store, Q_PROJ, &[0.5, -1.0, 2.0, 0.25], s);
    assert_ne!(
        bits(&out_b),
        bits(&out_a),
        "swapping to B changes the output again"
    );
    assert_ne!(bits(&out_b), bits(&base_out), "B is not the base");
    assert_ne!(
        weight_bits(&store, UP_PROJ, s),
        base_up,
        "B merges a weight A did not touch"
    );

    // --- adapter off: the base, byte for byte ---
    let rec_off = set.swap_to_base(&mut store, s).expect("swap to base");
    assert_eq!(rec_off.active, None, "no adapter is active");
    assert_eq!(
        rec_off.previous.as_deref(),
        Some("b"),
        "the swap records the previous adapter"
    );
    assert_eq!(
        rec_off.epoch, 3,
        "a swap back to the base increments the epoch too"
    );
    assert_eq!(rec_off.applied, 0, "adapter off merges nothing");
    assert_eq!(
        bits(&forward(&store, Q_PROJ, &[0.5, -1.0, 2.0, 0.25], s)),
        bits(&base_out),
        "adapter-off must be byte-for-byte the base output (K-G1)"
    );
    assert_eq!(
        weight_bits(&store, Q_PROJ, s),
        base_q,
        "adapter-off must restore the base weight bytes exactly"
    );
    assert_eq!(
        weight_bits(&store, UP_PROJ, s),
        base_up,
        "adapter-off must restore every weight the set touched"
    );
}

#[test]
fn swaps_do_not_compound_merges() {
    // A merge must be computed from the PRISTINE base, never from the live
    // store: otherwise A → B → A leaves A's delta applied twice and the
    // "reversible" claim is a claim about a different model.
    let s = stream();
    let mut store = synthetic_base();
    let base_up = weight_bits(&store, UP_PROJ, s);
    let mut set = AdapterSet::new("synthetic-base");
    set.add("a", adapter_a()).expect("adapter a registers");
    set.add("b", adapter_b()).expect("adapter b registers");
    set.bind(&store).expect("set binds to the base");

    set.swap(Some("a"), &mut store, s).expect("swap to a");
    let first_a = weight_bits(&store, Q_PROJ, s);
    set.swap(Some("b"), &mut store, s).expect("swap to b");
    assert_ne!(
        weight_bits(&store, UP_PROJ, s),
        base_up,
        "B merges the weight A left alone"
    );
    set.swap(Some("a"), &mut store, s).expect("swap back to a");
    assert_eq!(
        weight_bits(&store, Q_PROJ, s),
        first_a,
        "re-selecting A must land on the same weights A produced the first time"
    );
    assert_eq!(
        weight_bits(&store, UP_PROJ, s),
        base_up,
        "a weight the re-selected adapter does not touch is restored, not left merged"
    );
}

#[test]
fn the_in_out_orientation_merges_and_restores_exactly() {
    // The nursery runtime keeps its weights `[in, out]`; the merge surface
    // writes `[out, in]`. A store in the other orientation must swap and
    // restore just as exactly — otherwise a mis-declared orientation would
    // silently produce a transposed model.
    let s = stream();
    let mut store = HashMap::new();
    store.insert(
        Q_PROJ.to_string(),
        array(
            &[
                1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0,
            ],
            &[4, 3],
        ),
    );
    let base_bits = weight_bits(&store, Q_PROJ, s);

    let mut set = AdapterSet::new("synthetic-base");
    set.set_orientation(mlx_native::lora_set::Orientation::InOut);
    set.add("a", adapter_a()).expect("adapter a registers");
    set.bind(&store).expect("set binds to the base");

    set.swap(Some("a"), &mut store, s).expect("swap to a");
    assert_ne!(
        weight_bits(&store, Q_PROJ, s),
        base_bits,
        "the merged weight differs from the base"
    );
    set.swap_to_base(&mut store, s).expect("swap to base");
    assert_eq!(
        weight_bits(&store, Q_PROJ, s),
        base_bits,
        "adapter-off restores the base bytes in this orientation too"
    );
}

#[test]
fn k_g2_cache_key_carries_the_adapter_digest() {
    let s = stream();
    let mut store = synthetic_base();
    let mut set = AdapterSet::new("synthetic-base");
    set.add("a", adapter_a()).expect("adapter a registers");
    set.add("b", adapter_b()).expect("adapter b registers");
    set.bind(&store).expect("set binds to the base");

    let key_a = set.key_for("a").expect("A has a key");
    let key_b = set.key_for("b").expect("B has a key");
    let key_base = set.base_key();

    assert_ne!(key_a, key_b, "two adapters are two different models");
    assert_eq!(
        key_a,
        set.key_for("a").expect("A has a key"),
        "the key is stable for the same adapter"
    );
    assert_ne!(key_base, key_a, "the base is not adapter A");
    assert_ne!(key_base, key_b, "the base is not adapter B");
    assert!(key_base.is_base(), "the base key says so");
    assert!(!key_a.is_base(), "an adapter key is not the base key");
    assert_eq!(
        key_a.adapter_digest(),
        set.digest_of("a"),
        "the key carries the adapter's own digest"
    );
    assert_ne!(
        key_a.epoch_token(),
        key_b.epoch_token(),
        "a host cache scope token differs per adapter"
    );
    assert_eq!(
        key_a.epoch_token(),
        set.key_for("a").expect("A has a key").epoch_token(),
        "the token is stable for the same adapter"
    );
    assert_ne!(
        key_base.epoch_token(),
        key_a.epoch_token(),
        "the base has its own token"
    );

    // The active key follows the active adapter.
    set.swap(Some("a"), &mut store, s).expect("swap to a");
    assert_eq!(set.cache_key(), key_a, "the active key is A's key");
    set.swap(Some("b"), &mut store, s).expect("swap to b");
    assert_eq!(set.cache_key(), key_b, "the active key is B's key");
    set.swap_to_base(&mut store, s).expect("swap to base");
    assert_eq!(set.cache_key(), key_base, "the active key is the base key");
}

#[test]
fn k_g2_a_cache_built_under_one_adapter_cannot_be_read_under_another() {
    // The prefix cache is modelled here as a map keyed by the set's key: the
    // live prefix pool in `qwen_prefix` is a private module that still keys
    // on its own scope, so this test proves the KEYING, not that the live
    // pool consumes it yet.
    let s = stream();
    let mut store = synthetic_base();
    let mut set = AdapterSet::new("synthetic-base");
    set.add("a", adapter_a()).expect("adapter a registers");
    set.add("b", adapter_b()).expect("adapter b registers");
    set.bind(&store).expect("set binds to the base");

    let mut prefix_cache: HashMap<CacheKey, u32> = HashMap::new();

    set.swap(Some("a"), &mut store, s).expect("swap to a");
    let epoch_a = set.epoch();
    prefix_cache.insert(set.cache_key(), 42);
    assert_eq!(
        prefix_cache.get(&set.cache_key()),
        Some(&42),
        "A's prefix caches"
    );

    // Swap to B: the cache MUST miss.
    set.swap(Some("b"), &mut store, s).expect("swap to b");
    assert!(
        !prefix_cache.contains_key(&set.cache_key()),
        "a prefix computed under A must not be read under B (K-G2)"
    );
    assert!(
        prefix_cache.contains_key(&set.key_for("a").expect("A has a key")),
        "A's own entry is still there under A's key"
    );
    assert_ne!(set.epoch(), epoch_a, "the swap bumped the cache epoch");

    // Swapping back to A: the CONTENT key is the same and the weights are
    // the same bytes, so the entry is sound to reuse — and the test proves
    // the premise (identical weights) instead of assuming it.
    set.swap(Some("a"), &mut store, s).expect("swap back to a");
    assert_eq!(
        prefix_cache.get(&set.cache_key()),
        Some(&42),
        "A's prefix is reusable when A is active again"
    );
    assert!(
        set.epoch() > epoch_a,
        "the epoch keeps counting swaps, so a host can invalidate conservatively"
    );
}

#[test]
fn hard_error_law_a_missing_target_is_an_error_never_a_skip() {
    let store = synthetic_base();
    let mut set = AdapterSet::new("synthetic-base");
    set.add("missing", adapter_missing_target())
        .expect("registers");
    let err = set
        .bind(&store)
        .expect_err("a target the base does not have must be an error");
    assert!(
        err.contains("does not have"),
        "unexpected error text: {err}"
    );

    // And an unknown adapter name is refused, not ignored.
    let mut store = synthetic_base();
    let mut set = AdapterSet::new("synthetic-base");
    set.add("a", adapter_a()).expect("registers");
    set.bind(&store).expect("binds");
    let err = set
        .swap(Some("nope"), &mut store, stream())
        .expect_err("an unknown adapter name must be an error");
    assert!(
        err.contains("no adapter named"),
        "unexpected error text: {err}"
    );

    // An unbound set refuses to swap: without the pristine snapshot it could
    // not restore the base, and a swap that cannot be undone is not a swap.
    let mut store = synthetic_base();
    let mut set = AdapterSet::new("synthetic-base");
    set.add("a", adapter_a()).expect("registers");
    let err = set
        .swap(Some("a"), &mut store, stream())
        .expect_err("an unbound set must refuse to swap");
    assert!(err.contains("not bound"), "unexpected error text: {err}");
}

#[test]
fn k_g4_a_quantized_base_is_refused_not_approximated() {
    // The product checkpoints are 4-bit. A merge into a packed weight needs
    // dequantize -> merge -> requantize — a different path, with its own
    // quantization error. The set refuses it at bind time.
    let mut store = synthetic_base();
    store.insert(
        Q_PROJ.to_string(),
        Array::from_data_u32(&[0, 1, 2, 3, 4, 5], &[3, 4]).expect("packed weight"),
    );
    let mut set = AdapterSet::new("synthetic-base");
    set.add("a", adapter_a()).expect("registers");
    let err = set
        .bind(&store)
        .expect_err("a quantized base must be refused");
    assert!(
        err.contains("dequantize") && err.contains("refused"),
        "unexpected error text: {err}"
    );
    assert!(
        !set.is_bound(),
        "a refused bind leaves the set unbound — no half-bound state"
    );
}

#[test]
fn the_set_is_a_registry_before_it_is_a_swap() {
    // Pure bookkeeping, no GPU: a duplicate name is an error (an ambiguous
    // active adapter is worse than a refused one), and the registry reports
    // what it holds.
    let mut set = AdapterSet::new("synthetic-base");
    set.add("a", adapter_a()).expect("adapter a registers");
    let err = set
        .add("a", adapter_b())
        .expect_err("a duplicate adapter name must be an error");
    assert!(err.contains("already has"), "unexpected error text: {err}");
    assert_eq!(
        set.names(),
        vec!["a".to_string()],
        "the registry lists its adapters"
    );
    assert!(set.get("a").is_some(), "the adapter is reachable by name");
    assert!(set.get("b").is_none(), "an unregistered name is absent");
    assert_eq!(
        set.digest_of("a"),
        Some(mlx_native::nursery::sha256_hex(b"synthetic-adapter-A").as_str()),
        "the digest is the adapter's own"
    );
    assert_eq!(
        set.digest_of("b"),
        None,
        "an unregistered name has no digest"
    );
    assert_eq!(set.epoch(), 0, "a set that never swapped is at epoch 0");
    assert_eq!(
        set.active(),
        None,
        "nothing is active before the first swap"
    );
}
