//! Op-level decode probe (ignored): times individual decode-step ops at
//! T=2048 in isolation (eval + sync per op), to attribute the measured
//! long-context decode gap vs the python reference. Run:
//!   cargo test --release --test qwen_ops_probe -- --nocapture --ignored

use laya_native::mlx::{self, Array, Dtype};
use laya_native::qwen::Qwen3;

fn snapshot() -> std::path::PathBuf {
    let home = std::env::var("HOME").unwrap();
    let hub = std::path::Path::new(&home).join(".cache/huggingface/hub");
    for e in std::fs::read_dir(hub).unwrap().flatten() {
        if e.file_name().to_string_lossy().contains("Qwen3-0.6B-4bit") {
            for s in std::fs::read_dir(e.path().join("snapshots")).unwrap().flatten() {
                if s.path().join("config.json").is_file() {
                    return s.path();
                }
            }
        }
    }
    panic!("snapshot missing");
}

fn time_it<F: FnMut() -> Array>(name: &str, iters: usize, mut f: F, s: mlx::Stream) {
    // warmup
    {
        let a = f();
        let _ = a.eval();
        mlx::synchronize_stream(s).ok();
    }
    let t0 = std::time::Instant::now();
    for _ in 0..iters {
        let a = f();
        let _ = a.eval();
        mlx::synchronize_stream(s).ok();
    }
    let per = t0.elapsed().as_secs_f64() * 1e3 / iters as f64;
    println!("{name}: {per:.3}ms/op");
}

#[test]
#[ignore]
fn ops_probe() {
    let metallib = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        laya_native::mlx::set_metallib_path(&metallib);
    }
    let s = mlx::gpu().expect("Metal");
    let model = Qwen3::load(&snapshot()).unwrap();
    let (h, kv, d) = (model.cfg.heads, model.cfg.kv_heads, model.cfg.head_dim);
    let t_cache = 2048usize;

    // bf16 helper tensors
    let bf16_bytes = |count: usize| -> Vec<u8> {
        // bf16 bit pattern ~0.5 (0x3F00) — values don't matter for timing.
        let mut v = vec![0u8; count * 2];
        for c in v.chunks_exact_mut(2) {
            c[0] = 0x00;
            c[1] = 0x3F;
        }
        v
    };
    let x = Array::from_data_bf16(&bf16_bytes(1024), &[1, 1, 1024]).unwrap();
    let q = Array::from_data_bf16(&bf16_bytes(16 * 128), &[1, h, 1, d]).unwrap();
    let k_full = Array::from_data_bf16(&bf16_bytes(8 * t_cache * 128), &[1, kv, t_cache, d])
        .unwrap();
    let k_new = Array::from_data_bf16(&bf16_bytes(8 * 128), &[1, kv, 1, d]).unwrap();
    let big_buf =
        Array::from_data_bf16(&bf16_bytes(8 * 2304 * 128), &[1, kv, 2304, d]).unwrap();

    // 1. decode GEMV through quantized_matmul (the lm_head shape)
    let embed_w = laya_native::safetensors::SafetensorsFile::open(
        &snapshot().join("model.safetensors"),
    )
    .unwrap();
    let eq = embed_w.take_quantized("model.embed_tokens").unwrap();
    time_it(
        "qmat lm_head [1,1,1024]x[151936,1024]",
        20,
        || Array::quantized_matmul(&x, &eq.w, &eq.scales, &eq.biases, true, 64, 4, s).unwrap(),
        s,
    );

    // 2. decode GEMV mid-size (gate_proj shape)
    let gq = embed_w.take_quantized("model.layers.0.mlp.gate_proj").unwrap();
    time_it(
        "qmat gate [1,1,1024]x[3072,1024]",
        50,
        || Array::quantized_matmul(&x, &gq.w, &gq.scales, &gq.biases, true, 64, 4, s).unwrap(),
        s,
    );

    // 3. sdpa decode over T=2048 (GQA 16:8), contiguous K/V
    time_it(
        "sdpa decode T=2048 contiguous",
        50,
        || {
            Array::sdp_attention_mode(&q, &k_full, &k_full, 0.088388, "", None, s).unwrap()
        },
        s,
    );

    // 4. sdpa decode over a STRIDED view (padded buffer sliced to 2048)
    time_it(
        "sdpa decode T=2048 strided(2304) view",
        50,
        || {
            let kv_view = big_buf
                .slice(&[0, 0, 0, 0], &[1, kv as i32, t_cache as i32, d as i32], &[1, 1, 1, 1], s)
                .unwrap();
            Array::sdp_attention_mode(&q, &kv_view, &kv_view, 0.088388, "", None, s).unwrap()
        },
        s,
    );

    // 5. slice_update copy (cache write step)
    time_it(
        "slice_update [1,8,2304,128] write 1 token",
        50,
        || {
            Array::slice_update(
                &big_buf,
                &k_new,
                &[0, 0, 2048, 0],
                &[1, kv as i32, 2049, d as i32],
                &[1, 1, 1, 1],
                s,
            )
            .unwrap()
        },
        s,
    );

    // 6. rope one token at offset 2048
    time_it(
        "rope [1,16,1,128] offset=2048",
        50,
        || q.rope(d as i32, 1_000_000.0, 2048, s).unwrap(),
        s,
    );

    // 7. rms_norm one token
    let w = Array::from_data_bf16(&bf16_bytes(1024), &[1024]).unwrap();
    time_it(
        "rms_norm [1,1,1024]",
        50,
        || Array::rms_norm(&x, &w, 1e-6, s).unwrap(),
        s,
    );
}

/// Fresh-process long-context decode: 2048-token prefill then 32 decode
/// steps, no other work — isolates allocator/process-history effects the
/// full bench's warmup rounds may inject.
#[test]
#[ignore]
fn decode_2k_fresh() {
    let metallib = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        laya_native::mlx::set_metallib_path(&metallib);
    }
    let s = mlx::gpu().unwrap();
    let snap = snapshot();
    let tok = laya_native::bpe::Qwen3Tokenizer::load(&snap).unwrap();
    let model = Qwen3::load(&snap).unwrap();
    let fx: serde_json::Value = serde_json::from_str(
        &std::fs::read_to_string(
            std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("testdata/qwen3_06b_parity.json"),
        )
        .unwrap(),
    )
    .unwrap();
    let prompt_ids_fx: Vec<i32> = fx["prompt_ids"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.as_i64().unwrap() as i32)
        .collect();
    let mut ids: Vec<i32> = prompt_ids_fx.clone();
    while ids.len() < 2048 {
        ids.extend_from_slice(&prompt_ids_fx);
    }
    ids.truncate(2048);
    let _ = tok;
    let t0 = std::time::Instant::now();
    let out = model.generate_greedy(&ids, 32, s).unwrap();
    let total = t0.elapsed().as_secs_f64() * 1e3;
    println!(
        "fresh 2k: total={total:.0}ms (prefill+32) -> ~{:.2}ms/tok; last ids {:?}",
        (total - 0.0) / 32.0,
        &out[out.len() - 4..],
    );
}
