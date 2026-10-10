//! ADR 0054 R6 gate: the declared lfm2 forward plan (hybrid short-conv +
//! GQA attention) must be bit-identical to the imperative walk it
//! replaces. Both paths submit the same ops in the same order through the
//! same binding table; this test proves that on the live model — decode
//! logits compared as raw f32 bits across consecutive steps, prefill caches
//! (KV buffers AND conv states) compared as bf16-truncated bits over two
//! chunks crossing the 256-token growth boundary — then asserts the greedy
//! ids agree.
//!
//! Skips (with a note) when the snapshot or fixture is absent. The full
//! fixture gate under plan routing runs as
//! `LAYA_LFM2_PLAN=1 cargo test --test lfm2_parity` (plan is already the
//! default; `LAYA_LFM2_PLAN=0` proves the opt-out matches too).

use mlx_native::lfm2::{Lfm2, Lfm2Cache};
use mlx_native::mlx::{self, Dtype};
use serde::Deserialize;

#[derive(Deserialize)]
struct ParityFixture {
    snapshot: String,
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

fn pin_metallib_and_gpu() -> Option<mlx::Stream> {
    // Test binaries don't sit beside a metallib; pin the cmake-built one
    // BEFORE the first gpu() call (see lib.rs l0_ops).
    let metallib = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        mlx_native::mlx::set_metallib_path(&metallib);
    }
    match mlx::gpu() {
        Ok(s) => Some(s),
        Err(_) => {
            eprintln!("skipping: no Metal device");
            None
        }
    }
}

#[test]
fn lfm2_plan_step_bit_matches_imperative() {
    let Some(fx) = fixture() else {
        eprintln!("skipping: lfm2 parity fixture absent");
        return;
    };
    let Some(snap) = snapshot_dir(&fx) else {
        eprintln!("skipping: LFM2 snapshot absent");
        return;
    };
    let Some(s) = pin_metallib_and_gpu() else { return };

    let prompt = &fx.prompt_ids;
    let steps = fx.greedy_ids.len().min(8);

    // Leg A: the imperative walk (plan-mode default applies to the shared
    // prefill on both legs — exactly what generate_greedy does; the decode
    // legs below are what this gate compares).
    let model = Lfm2::load(&snap).expect("lfm2 loads");
    let mut cache = Lfm2Cache::new(&model.cfg.layer_types);
    cache
        .reserve(model.table(), model.cfg.kv_heads, model.cfg.head_dim, prompt.len() + steps, s)
        .expect("reserve");
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
    let model = Lfm2::load(&snap).expect("lfm2 loads");
    let mut cache = Lfm2Cache::new(&model.cfg.layer_types);
    cache
        .reserve(model.table(), model.cfg.kv_heads, model.cfg.head_dim, prompt.len() + steps, s)
        .expect("reserve");
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
    println!("lfm2 plan parity: {steps} steps bit-identical, ids {imp_ids:?}");
}

/// The prefill plan (l > 1, causal, KV/conv-only tail) must be bit-identical
/// to the imperative walk too — caches compared over BOTH chunks, crossing
/// the 256-token cache-growth boundary so the growth/trim policy runs on
/// both legs. Conv states ride the same comparison (the stateful part the
/// qwen gate doesn't have).
#[test]
fn lfm2_prefill_plan_bit_matches_imperative() {
    let Some(fx) = fixture() else {
        eprintln!("skipping: lfm2 parity fixture absent");
        return;
    };
    let Some(snap) = snapshot_dir(&fx) else {
        eprintln!("skipping: LFM2 snapshot absent");
        return;
    };
    let Some(s) = pin_metallib_and_gpu() else { return };

    let prompt: &[i32] = &fx.prompt_ids;
    let mut ids: Vec<i32> = Vec::with_capacity(300);
    while ids.len() < 300 {
        ids.extend_from_slice(prompt);
    }
    ids.truncate(300);
    let (c1, c2) = ids.split_at(200); // second chunk crosses offset 256

    let read_cache = |cache: &Lfm2Cache, s: mlx::Stream| -> Vec<Vec<u16>> {
        let mut bits = Vec::new();
        for slot in &cache.layers {
            match slot {
                mlx_native::lfm2::LayerCache::Attn { k, v } => {
                    for buf in [k, v] {
                        let b = buf.as_ref().expect("cache buffer");
                        let v = b
                            .astype(Dtype::Float32, s)
                            .expect("cast")
                            .to_f32_vec(s)
                            .expect("readback");
                        bits.push(v.into_iter().map(f32_to_bf16_bits).collect());
                    }
                }
                mlx_native::lfm2::LayerCache::Conv(st) => {
                    let b = st.as_ref().expect("conv state");
                    let v = b
                        .astype(Dtype::Float32, s)
                        .expect("cast")
                        .to_f32_vec(s)
                        .expect("readback");
                    bits.push(v.into_iter().map(f32_to_bf16_bits).collect());
                }
            }
        }
        bits
    };

    // Leg A: imperative.
    let model = Lfm2::load(&snap).expect("lfm2 loads");
    let mut cache = Lfm2Cache::new(&model.cfg.layer_types);
    for chunk in [c1, c2] {
        let t = mlx::Array::from_data_i32(chunk, &[1, chunk.len()]).expect("tokens");
        model.hidden_states(&t, &mut cache, false, s).expect("imperative prefill");
    }
    mlx::synchronize_stream(s).unwrap();
    let imp = read_cache(&cache, s);
    drop(model);

    // Leg B: the declared plan.
    let model = Lfm2::load(&snap).expect("lfm2 loads");
    let mut cache = Lfm2Cache::new(&model.cfg.layer_types);
    for chunk in [c1, c2] {
        let t = mlx::Array::from_data_i32(chunk, &[1, chunk.len()]).expect("tokens");
        model.hidden_states(&t, &mut cache, true, s).expect("plan prefill");
    }
    mlx::synchronize_stream(s).unwrap();
    let plan = read_cache(&cache, s);

    if imp.len() != plan.len() || imp.iter().zip(&plan).any(|(a, b)| a.len() != b.len()) {
        let imp_lens: Vec<usize> = imp.iter().map(|b| b.len()).collect();
        let plan_lens: Vec<usize> = plan.iter().map(|b| b.len()).collect();
        panic!(
            "cache shapes diverge: imp {} buffers {imp_lens:?}, plan {} buffers {plan_lens:?}",
            imp.len(),
            plan.len()
        );
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
    println!(
        "lfm2 prefill plan parity: 2 chunks (300 tokens, growth crossed, conv states included) bit-identical"
    );
}

/// Prefill exactly like generate_greedy (the chunk split is parity-
/// load-bearing): all-but-last token through KV/conv-only chunks, last
/// token rides the decode loop.
fn prefill(model: &Lfm2, prompt: &[i32], cache: &mut Lfm2Cache, s: mlx::Stream) {
    const PREFILL_STEP: usize = 2048;
    let mut rest = prompt;
    while rest.len() > 1 {
        let n = PREFILL_STEP.min(rest.len() - 1);
        let t = mlx::Array::from_data_i32(&rest[..n], &[1, n]).expect("prefill tokens");
        model.forward_hidden(&t, cache, s).expect("prefill chunk");
        rest = &rest[n..];
    }
}

/// Truncate-to-bf16 bits view of an f32 (comparison-stable; both legs run
/// the same buffers, so the truncated bits are exactly the buffers).
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
