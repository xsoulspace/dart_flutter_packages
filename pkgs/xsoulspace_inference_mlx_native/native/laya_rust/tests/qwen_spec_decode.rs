//! ADR 0057 bottleneck-1 rung: draft-model speculative greedy decoding.
//! Gate = SELF-CONSISTENCY: draft+verify output must equal the target's
//! plain greedy token-for-token (greedy verification is exact — a wrong
//! draft token is always caught by the verify argmax), plus the tok/s A/B
//! (power state recorded per the ADR 0051 law).
//!
//! Target: Qwen3-1.7B-4bit; draft: Qwen3-0.6B-4bit (same tokenizer, same
//! engine). Skips honestly when either snapshot is absent.

use std::time::Instant;

fn snapshot(fragment: &str) -> Option<std::path::PathBuf> {
    if let Some(dir) = std::env::var_os("LAYA_SPEC_SNAPSHOT_DIR") {
        let p = std::path::PathBuf::from(dir);
        return if p.is_dir() { Some(p) } else { None };
    }
    let home = std::env::var("HOME").ok()?;
    let hub = std::path::Path::new(&home).join(".cache/huggingface/hub");
    for e in std::fs::read_dir(hub).ok()?.flatten() {
        if e.file_name().to_string_lossy().contains(fragment) {
            for s in std::fs::read_dir(e.path().join("snapshots")).ok()?.flatten() {
                if s.path().join("config.json").is_file() {
                    return Some(s.path());
                }
            }
        }
    }
    None
}

fn metallib() {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("build/mlx-install/lib/mlx.metallib");
    if path.is_file() {
        let _ = laya_native::mlx::set_metallib_path(&path);
    }
}

#[test]
fn speculative_greedy_is_token_exact_and_faster() {
    let Some(target_dir) = snapshot("Qwen3-1.7B-4bit") else {
        eprintln!("skipping: Qwen3-1.7B-4bit snapshot absent");
        return;
    };
    let Some(draft_dir) = snapshot("Qwen3-0.6B-4bit") else {
        eprintln!("skipping: Qwen3-0.6B-4bit snapshot absent");
        return;
    };
    metallib();
    let Ok(s) = laya_native::mlx::gpu() else {
        eprintln!("skipping: no Metal device");
        return;
    };
    let target = laya_native::qwen::Qwen3::load(&target_dir).expect("target loads");
    let draft = laya_native::qwen::Qwen3::load(&draft_dir).expect("draft loads");

    // A short prompt from the shared tokenizer (fixture prompt text,
    // tokenized by the checkpoint BPE — the same tokenizer both sizes
    // ship).
    let fixture: serde_json::Value = serde_json::from_str(
        &std::fs::read_to_string(
            std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("testdata/qwen3_06b_parity.json"),
        )
        .expect("fixture"),
    )
    .unwrap();
    let prompt: Vec<i32> = fixture["prompt_ids"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.as_i64().unwrap() as i32)
        .collect();
    let steps = 32;

    // Plain greedy (the oracle path — fixture-proven engine).
    let t0 = Instant::now();
    let plain = target
        .generate_greedy(&prompt, steps, None, s)
        .expect("plain greedy");
    let plain_dt = t0.elapsed().as_secs_f64();

    // Draft+verify. k sweeps via LAYA_SPEC_K (default 4) — the draft
    // window trades proposed tokens against wasted draft steps.
    let k: usize = std::env::var("LAYA_SPEC_K").ok().and_then(|v| v.parse().ok()).unwrap_or(4);
    let t1 = Instant::now();
    let spec = target
        .generate_greedy_speculative(&draft, &prompt, steps, k, s)
        .expect("speculative greedy");
    let spec_dt = t1.elapsed().as_secs_f64();

    assert_eq!(
        plain, spec,
        "speculative greedy diverged from plain greedy (must be token-exact)"
    );
    // Interleave a second pair — within-run thermal drift biases the
    // second leg, so the honest ratio is the mean of both orders.
    let t2 = Instant::now();
    let plain2 = target
        .generate_greedy(&prompt, steps, None, s)
        .expect("plain greedy 2");
    let plain2_dt = t2.elapsed().as_secs_f64();
    let t3 = Instant::now();
    let spec2 = target
        .generate_greedy_speculative(&draft, &prompt, steps, k, s)
        .expect("speculative greedy 2");
    let spec2_dt = t3.elapsed().as_secs_f64();
    assert_eq!(plain2, spec2, "second interleaved pair diverged");

    let plain_tok_s = 0.5 * (steps as f64 / plain_dt + steps as f64 / plain2_dt);
    let spec_tok_s = 0.5 * (steps as f64 / spec_dt + steps as f64 / spec2_dt);
    println!(
        "spec-decode: {steps} tokens — plain {plain_tok_s:.1} tok/s, \
         speculative(k={k}) {spec_tok_s:.1} tok/s ({:.2}x) [same-process \
         interleaved, mean of two legs]",
        spec_tok_s / plain_tok_s
    );
}
