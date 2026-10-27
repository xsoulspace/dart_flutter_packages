//! C-10, item 3: the artifact THIS lane just trained loads and merges on the
//! native surface.
//!
//! The C-10 claim was: "the measured capability is on the python mlx-lm
//! runtime-adapter path; the Rust surface cannot load that artifact at all".
//! The bridge (`LoraAdapter::load_auto`) and the call site
//! (`NurseryModel::load_with_adapter`) close that. This file is the GATE for
//! the remaining half: does the REAL artifact — the one the 2026-10-21 run
//! trained — actually load, and does merging it produce the delta the format
//! says it should?
//!
//! Two gates live here:
//!   * `the_trained_artifact_loads_and_merges_on_the_native_surface` — the
//!     REAL artifact, which lives under `bench/` (gitignored), so it SKIPS
//!     on a clone that has never run the trainer. Point `MLX_LM_ARTIFACT`
//!     at any mlx-lm adapter to run it elsewhere. A gate that skips loudly
//!     is still a gate; a gate that silently passes is not.
//!   * `the_artifact_format_gate_runs_anywhere_on_a_tracked_synthetic_adapter`
//!     — the FORMAT law (EXPERIMENT-PLAN §5.3), built entirely in-test from
//!     a synthetic mlx-lm safetensors with KNOWN values, so it runs on every
//!     clone with a Metal device: orientation, pair shape, the exact merge
//!     delta, full `apply_to`, the missing-target refusal, and the
//!     unmatched-pair refusal. The trained-artifact gate above remains the
//!     only place that proves the trainer's bytes load; this one proves the
//!     READER obeys the format.
//!
//! What is checked:
//!   1. the artifact loads through the format-detecting loader;
//!   2. every pair is a well-formed 2-D (A, B) pair with a consistent rank;
//!   3. the merge delta equals `scale * (B @ A)` computed on the CPU, for the
//!      SMALLEST pairs — a transposed orientation would show up here as a
//!      wrong delta, which is the failure mode the bridge exists to prevent;
//!   4. `apply_to` merges every pair into a base that has every target, and
//!      REFUSES a base that is missing one (the hard-error law).

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use mlx_native::lora::{merge, LoraAdapter};
use mlx_native::mlx::{self, Array, Stream};

/// A live Metal stream. Test binaries do not sit beside the metallib, so the
/// cmake-built one is pinned first (the same pattern as `lora_set_swap`).
fn stream() -> Stream {
    let metallib =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        mlx::set_metallib_path(&metallib).expect("metallib pin");
    }
    mlx::gpu().expect("gpu stream")
}

/// The trained artifact. `MLX_LM_ARTIFACT` wins; otherwise the durable copy
/// the 2026-10-21 K' run produced.
fn artifact_path() -> PathBuf {
    if let Ok(p) = std::env::var("MLX_LM_ARTIFACT") {
        return PathBuf::from(p);
    }
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(
        "../../bench/nursery/experiments/adapter-conditioning-2026-10-21/adapter_cond/adapters.safetensors",
    )
}

#[test]
fn the_trained_artifact_loads_and_merges_on_the_native_surface() {
    let path = artifact_path();
    if !path.is_file() {
        eprintln!(
            "SKIP: no trained artifact at {} — it lives under bench/ (gitignored). \
             Set MLX_LM_ARTIFACT to run this gate.",
            path.display()
        );
        return;
    }
    let s = stream();
    let scale = 20.0f32;

    // (1) the bridge reads the real artifact.
    let adapter = LoraAdapter::load_auto(&path, scale, s)
        .expect("load_auto must read the mlx-lm artifact the trainer produced");
    assert!(
        !adapter.pairs.is_empty(),
        "the trained artifact produced zero LoRA pairs"
    );
    assert_eq!(adapter.digest.len(), 64, "digest is not a sha256 hex");

    // (2) every pair is a well-formed (A, B) pair: a is [r, in], b is [out, r].
    for pair in &adapter.pairs {
        assert!(
            pair.target.ends_with(".weight"),
            "target {} is not a plain weight name",
            pair.target
        );
        assert_eq!(pair.a.ndim(), 2, "a is not 2-D on {}", pair.target);
        assert_eq!(pair.b.ndim(), 2, "b is not 2-D on {}", pair.target);
        let r = pair.a.dim(0);
        assert!(r > 0, "rank 0 on {}", pair.target);
        assert_eq!(pair.b.dim(1), r, "a/b rank disagree on {}", pair.target);
        assert!(pair.a.dim(1) > 0, "in-dim 0 on {}", pair.target);
        assert!(pair.b.dim(0) > 0, "out-dim 0 on {}", pair.target);
    }

    // (3) the merge delta is exactly `scale * (B @ A)`, checked on the
    // SMALLEST pairs: a transposed orientation would produce a different
    // delta, and verifying every pair would allocate hundreds of MB of
    // synthetic base for no extra signal.
    let mut order: Vec<usize> = (0..adapter.pairs.len()).collect();
    order.sort_by_key(|&i| adapter.pairs[i].b.dim(0) * adapter.pairs[i].a.dim(1));
    let check_n = order.len().min(3);
    for &i in &order[..check_n] {
        let pair = &adapter.pairs[i];
        let r = pair.a.dim(0);
        let in_dim = pair.a.dim(1);
        let out_dim = pair.b.dim(0);
        let base_vals = vec![1.0f32; out_dim * in_dim];
        let base = Array::from_data_f32(&base_vals, &[out_dim, in_dim]).expect("base");
        let merged = merge(&base, &pair.a, &pair.b, scale, s).expect("merge");
        merged.eval().expect("eval merged");
        let got = merged.to_f32_vec(s).expect("merged values");
        let a = pair.a.to_f32_vec(s).expect("a values");
        let b = pair.b.to_f32_vec(s).expect("b values");
        let mut worst = 0.0f32;
        for o in 0..out_dim {
            for i in 0..in_dim {
                let mut delta = 0.0f32;
                for rr in 0..r {
                    delta += b[o * r + rr] * a[rr * in_dim + i];
                }
                let expect = 1.0 + scale * delta;
                worst = worst.max((got[o * in_dim + i] - expect).abs());
            }
        }
        assert!(
            worst < 1e-3,
            "merge delta is wrong on {}: max|diff| = {worst} (an orientation error?)",
            pair.target
        );
    }

    // (4a) `apply_to` merges EVERY pair into a base that has every target.
    let footprint: usize = adapter
        .pairs
        .iter()
        .map(|p| p.b.dim(0) * p.a.dim(1) * 4)
        .sum();
    const BUDGET: usize = 512 * 1024 * 1024;
    if footprint <= BUDGET {
        let mut params: HashMap<String, Array> = HashMap::new();
        for pair in &adapter.pairs {
            let out_dim = pair.b.dim(0);
            let in_dim = pair.a.dim(1);
            let vals = vec![1.0f32; out_dim * in_dim];
            params.insert(
                pair.target.clone(),
                Array::from_data_f32(&vals, &[out_dim, in_dim]).expect("base"),
            );
        }
        let applied = adapter.apply_to(&mut params, s).expect("apply_to");
        assert_eq!(
            applied,
            adapter.pairs.len(),
            "not every pair applied — a silently-unapplied adapter is the failure \
             mode this surface exists to prevent"
        );
    } else {
        eprintln!(
            "note: the synthetic base would be {} MB, over the {} MB budget — the \
             per-pair delta check above still ran on the smallest pairs",
            footprint / (1024 * 1024),
            BUDGET / (1024 * 1024)
        );
    }

    // (4b) a base MISSING a target is a hard error, never a skip.
    let mut missing: HashMap<String, Array> = HashMap::new();
    let err = adapter.apply_to(&mut missing, s);
    assert!(
        err.is_err(),
        "apply_to accepted a base with no targets — a missing target must be an error"
    );
}

// ---- the tracked format fixture: the same law, runnable on every clone ----

/// One synthetic adapter module: `lora_a` is [in, r] and `lora_b` is [r, out]
/// on disk — the TRUE mlx-lm orientation, so the loader's transpose is what
/// the test exercises. Values are small dyadic rationals (quarters/halves),
/// so every product and two-term sum is EXACT in f32 and the CPU expectation
/// matches the merge to the bit.
struct FixtureModule {
    module: &'static str,
    in_dim: usize,
    out_dim: usize,
    rank: usize,
}

fn fixture_a_val(i: usize, r: usize) -> f32 {
    (((i * 7 + r * 13) % 11) as f32) * 0.25 - 1.0
}

fn fixture_b_val(r: usize, o: usize) -> f32 {
    (((r * 5 + o * 3) % 7) as f32) * 0.5 - 1.5
}

/// Write an mlx-lm-format adapter safetensors: 8-byte LE header length, a
/// JSON header, then raw F32 data — the same container the python tuner
/// produces.
fn write_mlx_lm_adapter_fixture(path: &Path, modules: &[FixtureModule]) {
    let mut header = serde_json::Map::new();
    let mut data = Vec::new();
    for m in modules {
        let (in_dim, out_dim, r) = (m.in_dim, m.out_dim, m.rank);
        let a_start = data.len();
        for i in 0..in_dim {
            for rr in 0..r {
                data.extend_from_slice(&fixture_a_val(i, rr).to_le_bytes());
            }
        }
        let b_start = data.len();
        for rr in 0..r {
            for o in 0..out_dim {
                data.extend_from_slice(&fixture_b_val(rr, o).to_le_bytes());
            }
        }
        for (name, shape, start, end) in [
            (
                format!("{}.lora_a", m.module),
                vec![in_dim, r],
                a_start,
                b_start,
            ),
            (
                format!("{}.lora_b", m.module),
                vec![r, out_dim],
                b_start,
                data.len(),
            ),
        ] {
            let mut e = serde_json::Map::new();
            e.insert("dtype".into(), "F32".into());
            e.insert("shape".into(), serde_json::json!(shape));
            e.insert("data_offsets".into(), serde_json::json!([start, end]));
            header.insert(name, serde_json::Value::Object(e));
        }
    }
    let header_json = serde_json::to_string(&header).expect("header json");
    let mut bytes = Vec::new();
    bytes.extend_from_slice(&(header_json.len() as u64).to_le_bytes());
    bytes.extend_from_slice(header_json.as_bytes());
    bytes.extend_from_slice(&data);
    std::fs::write(path, bytes).expect("write adapter fixture");
}

const FIXTURE_SCALE: f32 = 20.0;
const FIXTURE_MODULES: [FixtureModule; 2] = [
    FixtureModule {
        module: "model.layers.0.self_attn.q_proj",
        in_dim: 6,
        out_dim: 4,
        rank: 2,
    },
    FixtureModule {
        module: "model.layers.1.mlp.down_proj",
        in_dim: 3,
        out_dim: 5,
        rank: 2,
    },
];

/// The FORMAT gate, runnable on every clone with a Metal device: a synthetic
/// mlx-lm adapter with known values must load, transpose, merge, apply, and
/// refuse exactly as the format says. This is the tracked fixture
/// (EXPERIMENT-PLAN §5.3): the trained-artifact gate above proves the
/// trainer's bytes; this one proves the READER.
#[test]
fn the_artifact_format_gate_runs_anywhere_on_a_tracked_synthetic_adapter() {
    let s = stream();
    let dir = std::env::temp_dir().join(format!(
        "mlx_lm_artifact_format_gate_{}_{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("clock")
            .as_nanos()
    ));
    std::fs::create_dir_all(&dir).expect("temp dir");

    // (1) the format-detecting loader reads the synthetic mlx-lm file.
    let good = dir.join("fixture_adapter.safetensors");
    write_mlx_lm_adapter_fixture(&good, &FIXTURE_MODULES);
    let adapter = LoraAdapter::load_auto(&good, FIXTURE_SCALE, s)
        .expect("load_auto must read the mlx-lm fixture");
    assert_eq!(adapter.pairs.len(), FIXTURE_MODULES.len());
    assert_eq!(adapter.digest.len(), 64, "digest is not a sha256 hex");

    // (2) shape + VALUE law: the loader's transpose is exact — the loaded
    // pair must hold the written values in transposed orientation, and the
    // merge delta must equal scale * (B @ A) on the CPU values. An
    // orientation error anywhere in the bridge flips these.
    for m in &FIXTURE_MODULES {
        let target = format!("{}.weight", m.module);
        let pair = adapter
            .pairs
            .iter()
            .find(|p| p.target == target)
            .unwrap_or_else(|| panic!("no pair for {target}"));
        let (r, in_dim, out_dim) = (m.rank, m.in_dim, m.out_dim);
        assert_eq!(pair.a.dim(0), r, "a_t rank on {target}");
        assert_eq!(pair.a.dim(1), in_dim, "a_t in-dim on {target}");
        assert_eq!(pair.b.dim(0), out_dim, "b_t out-dim on {target}");
        assert_eq!(pair.b.dim(1), r, "b_t rank on {target}");
        let a_t = pair.a.to_f32_vec(s).expect("a values");
        let b_t = pair.b.to_f32_vec(s).expect("b values");
        for rr in 0..r {
            for i in 0..in_dim {
                let got = a_t[rr * in_dim + i];
                let want = fixture_a_val(i, rr);
                assert!(
                    (got - want).abs() < 1e-6,
                    "a_t[{rr}][{i}] = {got}, want {want} (transpose missed) on {target}"
                );
            }
        }
        for o in 0..out_dim {
            for rr in 0..r {
                let got = b_t[o * r + rr];
                let want = fixture_b_val(rr, o);
                assert!(
                    (got - want).abs() < 1e-6,
                    "b_t[{o}][{rr}] = {got}, want {want} (transpose missed) on {target}"
                );
            }
        }
        // (3) the merge delta on a ones-base is exactly 1 + scale * B@A.
        let base_vals = vec![1.0f32; out_dim * in_dim];
        let base = Array::from_data_f32(&base_vals, &[out_dim, in_dim]).expect("base");
        let merged = merge(&base, &pair.a, &pair.b, FIXTURE_SCALE, s).expect("merge");
        merged.eval().expect("eval merged");
        let got = merged.to_f32_vec(s).expect("merged values");
        let mut worst = 0.0f32;
        for o in 0..out_dim {
            for i in 0..in_dim {
                let mut delta = 0.0f32;
                for rr in 0..r {
                    delta += fixture_b_val(rr, o) * fixture_a_val(i, rr);
                }
                worst = worst.max((got[o * in_dim + i] - (1.0 + FIXTURE_SCALE * delta)).abs());
            }
        }
        assert!(
            worst < 1e-4,
            "merge delta is wrong on {target}: max|diff| = {worst} (an orientation error?)"
        );
    }

    // (4a) `apply_to` merges EVERY pair into a base that has every target.
    let mut params: HashMap<String, Array> = HashMap::new();
    for m in &FIXTURE_MODULES {
        let vals = vec![1.0f32; m.out_dim * m.in_dim];
        params.insert(
            format!("{}.weight", m.module),
            Array::from_data_f32(&vals, &[m.out_dim, m.in_dim]).expect("base"),
        );
    }
    let applied = adapter.apply_to(&mut params, s).expect("apply_to");
    assert_eq!(applied, FIXTURE_MODULES.len());

    // (4b) a base MISSING a target is a hard error, never a skip.
    let mut missing: HashMap<String, Array> = HashMap::new();
    assert!(
        adapter.apply_to(&mut missing, s).is_err(),
        "apply_to accepted a base with no targets"
    );

    // (5) a module with lora_a but no lora_b is a REFUSAL, not a partial load.
    let unmatched = dir.join("unmatched_adapter.safetensors");
    write_mlx_lm_adapter_fixture(
        &unmatched,
        &[FixtureModule {
            module: "model.layers.0.self_attn.q_proj",
            in_dim: 6,
            out_dim: 4,
            rank: 2,
        }],
    );
    // rewrite the header without the lora_b tensor: build a file with ONLY a
    // lora_a by writing a one-module fixture whose b tensor is renamed away.
    let bytes = std::fs::read(&unmatched).expect("read fixture");
    let header_len = u64::from_le_bytes(bytes[..8].try_into().expect("header len")) as usize;
    let mut header: serde_json::Map<String, serde_json::Value> =
        serde_json::from_slice(&bytes[8..8 + header_len]).expect("header json");
    let b_name = "model.layers.0.self_attn.q_proj.lora_b";
    header.remove(b_name);
    let header_json = serde_json::to_string(&header).expect("header json");
    let mut out = Vec::new();
    out.extend_from_slice(&(header_json.len() as u64).to_le_bytes());
    out.extend_from_slice(header_json.as_bytes());
    out.extend_from_slice(&bytes[8 + header_len..]);
    std::fs::write(&unmatched, &out).expect("rewrite unmatched fixture");
    let err = match LoraAdapter::load_auto(&unmatched, FIXTURE_SCALE, s) {
        Err(e) => e,
        Ok(_) => panic!("an unmatched lora_a must refuse, never partially load"),
    };
    assert!(
        err.contains("no lora_b"),
        "refusal should name the missing lora_b, got: {err}"
    );

    // (6) a file with NO lora tensors at all is refused, not read as zero pairs.
    let empty = dir.join("no_lora_adapter.safetensors");
    write_mlx_lm_adapter_fixture(&empty, &[]);
    let err = match LoraAdapter::load_auto(&empty, FIXTURE_SCALE, s) {
        Err(e) => e,
        Ok(_) => panic!("an adapter with no pairs must refuse"),
    };
    assert!(
        err.contains("no LoRA tensors"),
        "refusal should name the empty tensor set, got: {err}"
    );

    std::fs::remove_dir_all(&dir).ok();
}
