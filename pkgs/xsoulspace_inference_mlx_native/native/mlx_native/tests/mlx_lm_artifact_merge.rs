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
//! The artifact lives under `bench/`, which is gitignored, so this gate SKIPS
//! on a clone that has never run the trainer. Point `MLX_LM_ARTIFACT` at any
//! mlx-lm adapter to run it elsewhere. A gate that skips loudly is still a
//! gate; a gate that silently passes is not.
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
use std::path::PathBuf;

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
