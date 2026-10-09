//! ADR 0055 P0 gate: the declared qwen decode-step plan must be
//! bit-identical to the imperative walk it replaces. Both paths submit the
//! same ops in the same order through the same binding table; this test
//! proves that on the live model (logits compared as raw f32 bits across
//! consecutive decode steps), then asserts the greedy ids agree.
//!
//! Skips (with a note) when the snapshot or fixture is absent. The full
//! fixture gate under plan routing runs as
//! `LAYA_QWEN_PLAN=1 cargo test --test qwen3_parity`.

use laya_native::mlx::{self, Dtype};
use laya_native::qwen::Qwen3;
use serde::Deserialize;

#[derive(Deserialize)]
struct ParityFixture {
    snapshot: String,
    prompt_ids: Vec<i32>,
    greedy_ids: Vec<i32>,
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

fn snapshot_dir() -> Option<std::path::PathBuf> {
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

/// Prefill exactly like generate_greedy (the chunk split is parity-
/// load-bearing): all-but-last token through KV-only chunks, last token
/// rides the decode loop.
fn prefill(model: &Qwen3, prompt: &[i32], cache: &mut laya_native::qwen::KvCache, s: mlx::Stream) {
    const PREFILL_STEP: usize = 2048;
    let mut rest = prompt;
    while rest.len() > 1 {
        let n = PREFILL_STEP.min(rest.len() - 1);
        let t = mlx::Array::from_data_i32(&rest[..n], &[1, n]).expect("prefill tokens");
        model.forward_hidden(&t, cache, s).expect("prefill chunk");
        rest = &rest[n..];
    }
}

#[test]
fn plan_step_bit_matches_imperative() {
    let Some(fx) = fixture() else {
        eprintln!("skipping: parity fixture absent");
        return;
    };
    let Some(snap) = snapshot_dir() else {
        eprintln!("skipping: Qwen3-0.6B-4bit snapshot absent");
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

    let prompt = &fx.prompt_ids;
    let steps = fx.greedy_ids.len().min(8);

    // Leg A: the imperative walk.
    let model = Qwen3::load(&snap).expect("model loads");
    let mut cache = laya_native::qwen::KvCache::new(model.cfg.layers);
    prefill(&model, prompt, &mut cache, s);
    let mut next = *prompt.last().expect("non-empty prompt");
    let mut imp_bits: Vec<[u8; 4]> = Vec::new();
    let mut imp_ids: Vec<i32> = Vec::new();
    for _ in 0..steps {
        let tokens = mlx::Array::from_data_i32(&[next], &[1, 1]).expect("token");
        let logits = model
            .step_logits(&tokens, &mut cache, false, s)
            .expect("imperative step");
        let (bits, id) = argmax_bits(&logits, s);
        imp_bits.push(bits);
        imp_ids.push(id);
        next = id;
    }
    drop(model);

    // Leg B: the declared step plan.
    let model = Qwen3::load(&snap).expect("model loads");
    let mut cache = laya_native::qwen::KvCache::new(model.cfg.layers);
    prefill(&model, prompt, &mut cache, s);
    let mut next = *prompt.last().expect("non-empty prompt");
    let mut plan_bits: Vec<[u8; 4]> = Vec::new();
    let mut plan_ids: Vec<i32> = Vec::new();
    for _ in 0..steps {
        let tokens = mlx::Array::from_data_i32(&[next], &[1, 1]).expect("token");
        let logits = model
            .step_logits(&tokens, &mut cache, true, s)
            .expect("plan step");
        let (bits, id) = argmax_bits(&logits, s);
        plan_bits.push(bits);
        plan_ids.push(id);
        next = id;
    }

    assert_eq!(
        imp_bits, plan_bits,
        "plan-path logits are not bit-identical to the imperative walk"
    );
    assert_eq!(imp_ids, plan_ids, "greedy ids diverged between paths");
    // Sanity: the shared prefix also matches the recorded fixture.
    assert_eq!(
        imp_ids[..steps],
        fx.greedy_ids[..steps],
        "both paths diverge from the reference fixture"
    );
    println!("plan parity: {steps} steps bit-identical, ids {imp_ids:?}");
}

/// The prefill plan (l > 1, causal, KV-only tail) must be bit-identical to
/// the imperative walk too — caches compared over BOTH chunks, crossing the
/// 256-token cache-growth boundary so the growth/trim policy runs on both
/// legs.
#[test]
fn prefill_plan_bit_matches_imperative() {
    let Some(fx) = fixture() else {
        eprintln!("skipping: parity fixture absent");
        return;
    };
    let Some(snap) = snapshot_dir() else {
        eprintln!("skipping: Qwen3-0.6B-4bit snapshot absent");
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

    let prompt: &[i32] = &fx.prompt_ids;
    let mut ids: Vec<i32> = Vec::with_capacity(300);
    while ids.len() < 300 {
        ids.extend_from_slice(prompt);
    }
    ids.truncate(300);
    let (c1, c2) = ids.split_at(200); // second chunk crosses offset 256

    let read_cache = |model: &Qwen3,
                      cache: &laya_native::qwen::KvCache,
                      s: mlx::Stream|
     -> Vec<Vec<u16>> {
        let mut bits = Vec::new();
        for slot in cache.layers_ref() {
            for buf in [&slot.k, &slot.v] {
                let b = buf.as_ref().expect("cache buffer");
                let v = b
                    .astype(Dtype::Float32, s)
                    .expect("cast")
                    .to_f32_vec(s)
                    .expect("readback");
                bits.push(v.into_iter().map(f32_to_bf16_bits).collect());
            }
        }
        let _ = model;
        bits
    };

    // Leg A: imperative.
    let model = Qwen3::load(&snap).expect("model loads");
    let mut cache = laya_native::qwen::KvCache::new(model.cfg.layers);
    for chunk in [c1, c2] {
        let t = mlx::Array::from_data_i32(chunk, &[1, chunk.len()]).expect("tokens");
        model.hidden_states(&t, &mut cache, false, s).expect("imperative prefill");
    }
    mlx::synchronize_stream(s).unwrap();
    let imp = read_cache(&model, &cache, s);
    drop(model);

    // Leg B: the declared plan.
    let model = Qwen3::load(&snap).expect("model loads");
    let mut cache = laya_native::qwen::KvCache::new(model.cfg.layers);
    for chunk in [c1, c2] {
        let t = mlx::Array::from_data_i32(chunk, &[1, chunk.len()]).expect("tokens");
        model.hidden_states(&t, &mut cache, true, s).expect("plan prefill");
    }
    mlx::synchronize_stream(s).unwrap();
    let plan = read_cache(&model, &cache, s);

    if imp.len() != plan.len() || imp.iter().zip(&plan).any(|(a, b)| a.len() != b.len()) {
        panic!("cache shapes diverge: imp {} buffers, plan {} buffers", imp.len(), plan.len());
    }
    let mut worst: Option<(usize, usize, u16, u16)> = None; // (buffer, elem, a, b)
    for (bi, (a, b)) in imp.iter().zip(&plan).enumerate() {
        for (i, (&x, &y)) in a.iter().zip(b.iter()).enumerate() {
            if x != y && worst.is_none() {
                worst = Some((bi, i, x, y));
            }
        }
    }
    assert!(
        worst.is_none(),
        "prefill plan caches are not bit-identical; first divergence at \
         buffer {bi} elem {i}: imp {x} vs plan {y}",
        bi = worst.as_ref().unwrap().0,
        i = worst.as_ref().unwrap().1,
        x = worst.as_ref().unwrap().2,
        y = worst.as_ref().unwrap().3,
    );
    println!("prefill plan parity: 2 chunks (300 tokens, growth crossed) bit-identical");
}

/// Truncate-to-bf16 bits view of an f32 (comparison-stable; both legs run
/// the same bf16 buffers, so the truncated bits are exactly the buffers).
fn f32_to_bf16_bits(x: f32) -> u16 {
    (x.to_bits() >> 16) as u16
}

fn argmax_bits(logits: &mlx::Array, s: mlx::Stream) -> ([u8; 4], i32) {
    let v = logits.astype(Dtype::Float32, s).expect("cast").to_f32_vec(s).expect("readback");
    let mut best = 0usize;
    for (i, &x) in v.iter().enumerate() {
        if x > v[best] {
            best = i;
        }
    }
    let mut bits = [0u8; 4];
    bits.copy_from_slice(&v[best].to_le_bytes());
    (bits, best as i32)
}
