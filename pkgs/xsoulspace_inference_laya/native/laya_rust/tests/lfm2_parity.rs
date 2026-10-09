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
    let Ok(s) = mlx::gpu() else {
        eprintln!("skipping: no Metal device");
        return;
    };
    let metallib = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        laya_native::mlx::set_metallib_path(&metallib);
    }

    std::env::set_var("LFM2_SNAPSHOT", &snap);
    let model = Lfm2::load(&snap).expect("lfm2 loads");
    let t0 = std::time::Instant::now();
    let ids = model
        .generate_greedy(&fx.prompt_ids, fx.greedy_ids.len(), s)
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
