//! ADR 0054 R2 gate: greedy token-for-token parity against the mlx-lm
//! reference (fixture regenerated from the cached Qwen3-0.6B-4bit snapshot
//! via tool/gen_qwen3_parity_fixture.py) plus byte-level-BPE parity probes.
//!
//! Skips (with a note) when the snapshot or fixture is absent — the model is
//! not committed. RUNG LAW: a parity failure is a gate failure; record it in
//! the ADR, never weaken the fixture.

use laya_native::bpe::ByteLevelBpe;
use laya_native::mlx;
use laya_native::mlx::{Array, Dtype};
use laya_native::qwen::{KvCache, Qwen3};
use serde::Deserialize;

#[derive(Deserialize)]
struct ParityFixture {
    snapshot: String,
    #[allow(dead_code)]
    prompt: String,
    prompt_ids: Vec<i32>,
    greedy_ids: Vec<i32>,
    tokenizer_probes: std::collections::HashMap<String, Vec<u32>>,
    /// Per-step reference top-2 (id + logits) — present in fixtures
    /// recorded for a model whose greedy stream contains HARD ties
    /// (top-2 gap at print precision; python flips them between its own
    /// runs). When present, the gate is teacher-forced: each step
    /// conditions on the REFERENCE prefix, and a mismatch passes only if
    /// it is a recorded tie and the engine's token is the reference's
    /// other top-2 member.
    steps: Option<Vec<RefStep>>,
}

#[derive(serde::Deserialize)]
struct RefStep {
    r#ref: i32,
    top2: [i32; 2],
    logits: [f32; 2],
}

fn fixture() -> Option<ParityFixture> {
    let path = std::env::var_os("QWEN3_FIXTURE")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| {
            std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("testdata/qwen3_06b_parity.json")
        });
    let raw = std::fs::read_to_string(path).ok()?;
    Some(serde_json::from_str(&raw).expect("parity fixture parses"))
}

/// The cached snapshot dir (or $QWEN3_SNAPSHOT override), if present.
fn snapshot_dir(_fixture: &ParityFixture) -> Option<std::path::PathBuf> {
    if let Some(over) = std::env::var_os("QWEN3_SNAPSHOT") {
        let p = std::path::PathBuf::from(over);
        if p.is_dir() {
            return Some(p);
        }
        return None;
    }
    let home = std::env::var_os("HOME")?;
    let mut pat = std::path::PathBuf::from(home);
    pat.push(".cache/huggingface/hub");
    let hub = std::fs::read_dir(&pat).ok()?;
    for entry in hub.flatten() {
        let name = entry.file_name();
        if name.to_string_lossy().contains("Qwen3-0.6B-4bit") {
            let snaps = entry.path().join("snapshots");
            if let Ok(list) = std::fs::read_dir(&snaps) {
                for s in list.flatten() {
                    if s.path().is_dir() && s.path().join("config.json").is_file() {
                        return Some(s.path());
                    }
                }
            }
        }
    }
    None
}

fn gpu() -> Option<mlx::Stream> {
    if let Ok(s) = mlx::gpu() {
        return Some(s);
    }
    eprintln!("skipping: no Metal device");
    None
}

/// Tokenizer probes: Rust BPE must produce the reference ids exactly.
#[test]
fn bpe_matches_reference_probes() {
    let Some(fx) = fixture() else {
        eprintln!("skipping: parity fixture absent");
        return;
    };
    let Some(snap) = snapshot_dir(&fx) else {
        eprintln!("skipping: Qwen3-0.6B-4bit snapshot absent");
        return;
    };
    let tok = ByteLevelBpe::load(&snap).expect("tokenizer loads");
    for (text, want) in &fx.tokenizer_probes {
        let got = tok.encode(text).unwrap_or_else(|e| panic!("encode {text:?}: {e}"));
        assert_eq!(
            &got, want,
            "tokenizer probe diverged for {text:?}\n got  {got:?}\n want {want:?}"
        );
    }
    // Round-trip: decode(encode(probe)) returns the NFC-normalized text.
    for text in fx.tokenizer_probes.keys() {
        let ids = tok.encode(text).unwrap();
        let back = tok.decode(&ids).unwrap();
        assert_eq!(&back, text);
    }
}

/// The R2 gate: greedy decode reproduces the reference token sequence.
#[test]
fn greedy_decode_matches_reference() {
    let Some(fx) = fixture() else {
        eprintln!("skipping: parity fixture absent");
        return;
    };
    let Some(snap) = snapshot_dir(&fx) else {
        eprintln!("skipping: Qwen3-0.6B-4bit snapshot absent");
        return;
    };
    // Golden-laya convention: the metallib sits in the crate's build dir.
    // Test binaries don't sit beside a metallib; pin it BEFORE the first
    // gpu() call (see lib.rs l0_ops) so the test is deterministic in a
    // single-process run, not just when a sibling test pinned it first.
    let metallib = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        laya_native::mlx::set_metallib_path(&metallib);
    }
    let Some(s) = gpu() else { return };

    let tok = ByteLevelBpe::load(&snap).expect("tokenizer loads");
    let prompt_ids = tok
        .encode(&fx.prompt)
        .expect("prompt encodes")
        .into_iter()
        .map(|i| i as i32)
        .collect::<Vec<_>>();
    assert_eq!(
        prompt_ids, fx.prompt_ids,
        "prompt tokenization diverged from the reference"
    );

    let t0 = std::time::Instant::now();
    let model = Qwen3::load(&snap).expect("model loads");
    println!("model load: {:?}", t0.elapsed());

    // Tie-aware fixtures (models with hard greedy ties — Qwen3-1.7B):
    // teacher-forced per-step parity. The engine conditions on the
    // REFERENCE prefix each step (prefill once, then step the reference
    // tokens through the cache), so a fork at one tie cannot cascade.
    if let Some(steps) = &fx.steps {
        let mut cache = KvCache::new(model.cfg.layers);
        cache
            .reserve(
                model.table(),
                model.cfg.kv_heads,
                model.cfg.head_dim,
                fx.prompt_ids.len() + steps.len(),
                s,
            )
            .expect("reserve");
        // The prefill pass predicts step 0 (its lm_head tail is the
        // whole-prefix head — forward_step handles l > 1); each later
        // step consumes the PREVIOUS reference token.
        let pre = Array::from_data_i32(&fx.prompt_ids, &[1, fx.prompt_ids.len()])
            .expect("prefill tokens");
        let mut logits = model.forward_step(&pre, &mut cache, s).expect("prefill");
        let mut mismatches = Vec::new();
        for (k, step) in steps.iter().enumerate() {
            if k > 0 {
                let prev: Vec<i32> = vec![steps[k - 1].r#ref];
                let tokens = Array::from_data_i32(&prev, &[1, 1]).expect("step tokens");
                logits = model.forward_step(&tokens, &mut cache, s).expect("step");
            }
            let l_len = logits.dim(1);
            let last_pos = logits
                .slice(&[0, (l_len - 1) as i32, 0], &[1, l_len as i32, logits.dim(2) as i32], &[1, 1, 1], s)
                .expect("last position");
            let am = last_pos.argmax_axis(-1, false, s).expect("argmax");
            let f = am.astype(Dtype::Float32, s).expect("cast");
            let v = f.to_f32_vec(s).expect("readback");
            let got = v.first().copied().unwrap_or(f32::NAN) as i32;
            let tie = (step.logits[0] - step.logits[1]).abs() <= 0.05;
            let ok = got == step.r#ref
                || (tie && (got == step.top2[0] || got == step.top2[1]));
            if !ok {
                mismatches.push((k, got, step.r#ref, tie));
            }
        }
        assert!(
            mismatches.is_empty(),
            "teacher-forced parity FAILED: {mismatches:?} (of {} steps; ties pass only within the recorded top-2)",
            steps.len()
        );
        println!(
            "PARITY: {}/{} teacher-forced steps match (tie-aware: {} recorded top-2 ties accepted)",
            steps.len(),
            steps.len(),
            steps.iter().filter(|st| (st.logits[0] - st.logits[1]).abs() <= 0.05).count()
        );
        return;
    }

    let t0 = std::time::Instant::now();
    let ids = model
        .generate_greedy(&fx.prompt_ids, fx.greedy_ids.len(), None, s)
        .expect("greedy decode runs");
    println!("greedy {} tokens: {:?}", fx.greedy_ids.len(), t0.elapsed());

    let generated = &ids[fx.prompt_ids.len()..];
    let mut first_diff = None;
    for (i, (g, w)) in generated.iter().zip(fx.greedy_ids.iter()).enumerate() {
        if g != w {
            first_diff = Some((i, *g, *w));
            break;
        }
    }
    match first_diff {
        None => {
            println!(
                "PARITY: {}/{} greedy tokens match the mlx-lm reference",
                fx.greedy_ids.len(),
                fx.greedy_ids.len()
            );
        }
        Some((i, g, w)) => panic!(
            "greedy parity FAILED at generated token {i}: got {g}, want {w} (of {} tokens)",
            fx.greedy_ids.len()
        ),
    }
    assert_eq!(generated, &fx.greedy_ids[..]);
}

/// FFI smoke: the C ABI surface (load → generate JSON → unload) end-to-end
/// with the fixture prompt.
#[test]
fn qwen_ffi_generate_smoke() {
    let Some(fx) = fixture() else {
        eprintln!("skipping: parity fixture absent");
        return;
    };
    let Some(snap) = snapshot_dir(&fx) else {
        eprintln!("skipping: Qwen3-0.6B-4bit snapshot absent");
        return;
    };
    let metallib = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        laya_native::mlx::set_metallib_path(&metallib);
    }

    extern "C" {
        fn laya_native_qwen_load(model_dir: *const std::ffi::c_char) -> i64;
        fn laya_native_qwen_generate(
            handle: i64,
            request_json: *const std::ffi::c_char,
        ) -> *mut std::ffi::c_char;
        fn laya_native_qwen_unload(handle: i64);
        fn laya_native_free(pointer: *mut std::ffi::c_char);
    }

    let dir = std::ffi::CString::new(snap.to_str().unwrap()).unwrap();
    let handle = unsafe { laya_native_qwen_load(dir.as_ptr()) };
    assert!(handle > 0, "qwen load failed: {handle}");
    let request = std::ffi::CString::new(
        serde_json::json!({ "prompt": fx.prompt, "max_tokens": 8 }).to_string(),
    )
    .unwrap();
    let out = unsafe { laya_native_qwen_generate(handle, request.as_ptr()) };
    assert!(!out.is_null(), "generate returned null");
    let payload = unsafe { std::ffi::CStr::from_ptr(out) }.to_string_lossy().to_string();
    unsafe { laya_native_free(out) };
    unsafe { laya_native_qwen_unload(handle) };

    let parsed: serde_json::Value = serde_json::from_str(&payload).expect("response JSON");
    assert!(
        parsed.get("error").is_none(),
        "generate errored: {parsed}"
    );
    let ids: Vec<i32> = parsed["ids"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.as_i64().unwrap() as i32)
        .collect();
    assert_eq!(ids.len(), fx.prompt_ids.len() + 8);
    assert_eq!(
        &ids[..fx.prompt_ids.len()],
        &fx.prompt_ids[..],
        "FFI prompt ids diverge from the tokenizer fixture"
    );
    if fx.steps.is_some() {
        // Tie-aware fixture (hard greedy ties): the FFI smoke's job is the
        // ABI surface, not the stream — assert only the first token (the
        // stream gate owns parity, teacher-forced above).
        assert_eq!(
            ids[fx.prompt_ids.len()],
            fx.steps.as_ref().unwrap()[0].r#ref,
            "FFI first greedy token diverges from the reference"
        );
    } else {
        assert_eq!(
            &ids[fx.prompt_ids.len()..],
            &fx.greedy_ids[..8],
            "FFI greedy ids diverge from the reference"
        );
    }
}
