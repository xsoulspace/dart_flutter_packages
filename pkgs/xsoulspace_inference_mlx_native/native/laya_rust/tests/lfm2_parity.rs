//! ADR 0055 LFM2 rung gate: the Rust hybrid short-conv/GQA decoder must
//! reproduce the pinned venv reference (mlx_lm lfm2) token-for-token, then
//! measure decode throughput against ADR 0051's "≥45 tok/s 1.2B q4 class"
//! row (AC power — the ADR 0051 law: record the power state).
//!
//! Skips (with a note) when the snapshot or fixture is absent. The fixture
//! carries prompt_ids from the reference tokenizer — bpe.rs is
//! Qwen-specific and deliberately NOT used here (empty tokenizer_probes).

use laya_native::lfm2::Lfm2;
use laya_native::mlx::{self, Dtype};
use serde::Deserialize;

#[derive(Deserialize)]
struct ParityFixture {
    snapshot: String,
    #[allow(dead_code)]
    prompt: String,
    prompt_ids: Vec<i32>,
    greedy_ids: Vec<i32>,
}

fn fixture() -> Option<ParityFixture> {
    let path = std::env::var_os("LFM2_FIXTURE")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| {
            std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("testdata/lfm25_12b_parity.json")
        });
    let raw = std::fs::read_to_string(path).ok()?;
    Some(serde_json::from_str(&raw).expect("lfm2 fixture parses"))
}

fn snapshot_dir(fx: &ParityFixture) -> Option<std::path::PathBuf> {
    if let Some(over) = std::env::var_os("LFM2_SNAPSHOT") {
        let p = std::path::PathBuf::from(over);
        return if p.is_dir() { Some(p) } else { None };
    }
    let p = std::path::PathBuf::from(&fx.snapshot);
    if p.is_dir() {
        return Some(p);
    }
    None
}

#[test]
fn lfm2_greedy_matches_reference_and_gate() {
    let Some(fx) = fixture() else {
        eprintln!("skipping: lfm2 parity fixture absent");
        return;
    };
    let Some(snap) = snapshot_dir(&fx) else {
        eprintln!("skipping: LFM2 snapshot absent");
        return;
    };
    // Test binaries don't sit beside a metallib; pin the cmake-built one
    // BEFORE the first gpu() call — the pinning is process-global, but the
    // device/stream init is lazy, so a gpu() call first would initialize it
    // without kernels and fail (see lib.rs l0_ops).
    let metallib = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        laya_native::mlx::set_metallib_path(&metallib);
    }
    let Ok(s) = mlx::gpu() else {
        eprintln!("skipping: no Metal device");
        return;
    };

    std::env::set_var("LFM2_SNAPSHOT", &snap);
    let model = Lfm2::load(&snap).expect("lfm2 loads");
    let t0 = std::time::Instant::now();
    let ids = model
        .generate_greedy(&fx.prompt_ids, fx.greedy_ids.len(), None, s)
        .expect("greedy decode runs");
    let dt = t0.elapsed();
    let generated = &ids[fx.prompt_ids.len()..];

    assert_eq!(
        generated,
        fx.greedy_ids.as_slice(),
        "greedy tokens diverge from the mlx_lm reference\n got  {generated:?}\n want {:?}",
        fx.greedy_ids
    );

    let tok_s = generated.len() as f64 / dt.as_secs_f64();
    println!(
        "lfm2 greedy: {}/{} tokens match; decode {:.1} tok/s ({:?} for {}) on AC",
        generated.len(),
        fx.greedy_ids.len(),
        tok_s,
        dt,
        generated.len()
    );
    // ADR 0051's "LFM decode ≥45 tok/s" row — first honest measurement on
    // the Rust host. Print-only verdict here (power-state-dependent; the
    // ADR records the number and the state).
    if tok_s < 45.0 {
        eprintln!(
            "NOTE: {tok_s:.1} tok/s < 45 gate — record power state; the \
             gate verdict belongs to the ADR, not a hard assert"
        );
    }
    let _ = Dtype::Float32;
}

/// Opt-in EOS stop (ADR 0055 gap): with `stop_on_eos` + `eos_ids=[7, 2]`
/// (<|im_end|>, <|endoftext|>) the generate native stops AT the first eos in
/// the pinned greedy stream — it emits that eos token, then breaks (HF
/// convention). The fixture's stream runs THROUGH both eos ids (7 at index
/// 21, 2 at 22) and continues to 64 tokens; the DEFAULT-OFF path is exactly
/// what the fixture gate above pins. Driven through the FFI so the serde
/// request wiring (`stop_on_eos`/`eos_ids`) is covered in the same gate.
#[test]
fn lfm2_generate_stops_at_eos_only_when_opted_in() {
    let Some(fx) = fixture() else {
        eprintln!("skipping: lfm2 parity fixture absent");
        return;
    };
    let Some(snap) = snapshot_dir(&fx) else {
        eprintln!("skipping: LFM2 snapshot absent");
        return;
    };
    // Pin the metallib BEFORE gpu() (see the 12B test above).
    let metallib = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        laya_native::mlx::set_metallib_path(&metallib);
    }
    let Ok(_) = mlx::gpu() else {
        eprintln!("skipping: no Metal device");
        return;
    };

    extern "C" {
        fn laya_native_lfm2_load(model_dir: *const std::ffi::c_char) -> i64;
        fn laya_native_lfm2_generate(
            handle: i64,
            request_json: *const std::ffi::c_char,
        ) -> *mut std::ffi::c_char;
        fn laya_native_lfm2_unload(handle: i64);
        fn laya_native_free(pointer: *mut std::ffi::c_char);
    }

    let dir = std::ffi::CString::new(snap.to_str().unwrap()).unwrap();
    let handle = unsafe { laya_native_lfm2_load(dir.as_ptr()) };
    assert!(handle > 0, "lfm2 load failed: {handle}");

    let eos_pos = fx
        .greedy_ids
        .iter()
        .position(|t| *t == 7 || *t == 2)
        .expect("fixture greedy stream contains <|im_end|> or <|endoftext|>");

    let request = std::ffi::CString::new(
        serde_json::json!({
            "prompt_ids": fx.prompt_ids,
            "max_tokens": fx.greedy_ids.len(),
            "stop_on_eos": true,
            "eos_ids": [7, 2],
        })
        .to_string(),
    )
    .unwrap();
    let out = unsafe { laya_native_lfm2_generate(handle, request.as_ptr()) };
    assert!(!out.is_null(), "generate returned null");
    let payload = unsafe { std::ffi::CStr::from_ptr(out) }
        .to_string_lossy()
        .to_string();
    unsafe { laya_native_free(out) };
    unsafe { laya_native_lfm2_unload(handle) };

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
    let generated = &ids[fx.prompt_ids.len()..];
    assert_eq!(
        generated,
        &fx.greedy_ids[..=eos_pos],
        "stop_on_eos must emit exactly the fixture prefix up to and including the first eos"
    );
    assert_eq!(
        generated.last(),
        Some(&fx.greedy_ids[eos_pos]),
        "the eos token itself must be emitted before stopping"
    );
    assert!(
        generated.len() < fx.greedy_ids.len(),
        "generation must stop before the pinned stream ends (default OFF keeps it whole)"
    );
}

/// The FFI rung's tokenizer gate: the hand-rolled byte-level BPE must
/// reproduce the reference tokenizer ids for the fixture prompt (the
/// fixture itself carries empty tokenizer_probes — this test is the
/// probe). prompt_ids[0] is <|startoftext|> (BOS), added by generate,
/// not by encode.
#[test]
fn lfm2_tokenizer_matches_reference() {
    let Some(fx) = fixture() else {
        eprintln!("skipping: lfm2 parity fixture absent");
        return;
    };
    let Some(snap) = snapshot_dir(&fx) else {
        eprintln!("skipping: LFM2 snapshot absent");
        return;
    };
    let tok = laya_native::bpe::ByteLevelBpe::load_tokenizer_json(&snap)
        .expect("tokenizer.json loads");
    let raw = tok.encode(&fx.prompt).expect("encode");
    let want: Vec<u32> = fx.prompt_ids[1..].iter().map(|&i| i as u32).collect();
    assert_eq!(
        fx.prompt_ids.first(),
        Some(&1),
        "fixture prompt_ids should start with <|startoftext|>"
    );
    assert_eq!(
        raw, want,
        "raw encode diverges from reference ids (BOS excluded)\n got  {raw:?}\n want {:?}",
        &fx.prompt_ids[1..]
    );
    // Decode round trip over the generated suffix.
    let text = tok.decode(&fx.greedy_ids.iter().map(|&i| i as u32).collect::<Vec<_>>())
        .expect("decode");
    assert!(!text.is_empty());
    println!("lfm2 tokenizer parity: {} ids round trip; sample {text:?}", raw.len());
}

/// The v1 config dialect (full_attn_idxs, e.g. LFM2-700M-4bit): the
/// config-derivation gate. Same engine, different config shapes — the
/// fixture pins the reference greedy stream (venv mlx_lm, BOS included in
/// prompt_ids; the Rust text path prepends the same BOS).
#[test]
fn lfm2_700m_greedy_matches_reference() {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("testdata/lfm2_700m_parity.json");
    let Ok(raw) = std::fs::read_to_string(&path) else {
        eprintln!("skipping: 700m parity fixture absent");
        return;
    };
    #[derive(Deserialize)]
    struct Fx700 {
        snapshot: String,
        prompt_ids: Vec<i32>,
        greedy_ids: Vec<i32>,
    }
    let fx: Fx700 = serde_json::from_str(&raw).expect("700m fixture parses");
    let snap = std::env::var_os("LFM2_700M_SNAPSHOT")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| std::path::PathBuf::from(&fx.snapshot));
    if !snap.is_dir() {
        eprintln!("skipping: 700m snapshot absent");
        return;
    }
    // Pin the metallib BEFORE gpu() (see the 12B test above).
    let metallib = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        let _ = laya_native::mlx::set_metallib_path(&metallib);
    }
    let Ok(s) = mlx::gpu() else {
        eprintln!("skipping: no Metal device");
        return;
    };
    let model = match Lfm2::load(&snap) {
        Ok(m) => m,
        Err(e) => panic!("700m load failed (config derivation?): mlx status {}", e.0),
    };
    let ids = model
        .generate_greedy(&fx.prompt_ids, fx.greedy_ids.len(), None, s)
        .expect("700m greedy");
    let got = &ids[fx.prompt_ids.len()..];
    assert_eq!(
        got,
        fx.greedy_ids.as_slice(),
        "700m greedy diverges (v1 config dialect)\n got  {got:?}\n want {:?}",
        fx.greedy_ids
    );
    println!("lfm2 700m: {}/{} tokens match the v1-config reference", got.len(), fx.greedy_ids.len());
}
