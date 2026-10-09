//! ADR 0055 P1 attribution driver: per-step decode wall time + (under
//! LAYA_QWEN_PROFILE=1) per-section sync-accurate GPU time, at a chosen
//! context length. Run across a ctx sweep and diff against the python
//! reference leg — the section that carries the superlinear gap is the
//! owner of the 3–4× long-context decode distance.
//!
//! Usage: qwen_decode_bench [ctx_len] [steps]   (defaults 2048, 16)

use std::path::PathBuf;

fn snapshot() -> std::path::PathBuf {
    if let Some(over) = std::env::var_os("QWEN3_SNAPSHOT") {
        return PathBuf::from(over);
    }
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
    panic!("Qwen3-0.6B-4bit snapshot missing");
}

fn main() {
    let ctx_len: usize = std::env::args().nth(1).and_then(|v| v.parse().ok()).unwrap_or(2048);
    let steps: usize = std::env::args().nth(2).and_then(|v| v.parse().ok()).unwrap_or(16);

    let metallib = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        let _ = laya_native::mlx::set_metallib_path(&metallib);
    }
    let s = laya_native::mlx::gpu().expect("Metal");
    let model = laya_native::qwen::Qwen3::load(&snapshot()).expect("model loads");

    let fixture: serde_json::Value = serde_json::from_str(
        &std::fs::read_to_string(
            PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("testdata/qwen3_06b_parity.json"),
        )
        .unwrap(),
    )
    .unwrap();
    let base: Vec<i32> = fixture["prompt_ids"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.as_i64().unwrap() as i32)
        .collect();
    let mut ids: Vec<i32> = Vec::with_capacity(ctx_len);
    while ids.len() < ctx_len {
        ids.extend_from_slice(&base);
    }
    ids.truncate(ctx_len);

    let mut cache = laya_native::qwen::KvCache::new(model.cfg.layers);
    let mut rest: &[i32] = &ids;
    const CHUNK: usize = 2048;
    while rest.len() > 1 {
        let n = CHUNK.min(rest.len() - 1);
        let t = laya_native::mlx::Array::from_data_i32(&rest[..n], &[1, n]).unwrap();
        model.forward_hidden(&t, &mut cache, s).unwrap();
        rest = &rest[n..];
    }
    laya_native::mlx::synchronize_stream(s).unwrap();

    let mut next = *rest.last().unwrap();
    let mut samples: Vec<f64> = Vec::with_capacity(steps);
    for _ in 0..steps {
        let tokens = laya_native::mlx::Array::from_data_i32(&[next], &[1, 1]).unwrap();
        let t0 = std::time::Instant::now();
        let logits = model.forward_step(&tokens, &mut cache, s).unwrap();
        let am = logits.argmax_axis(-1, false, s).unwrap();
        let v = am
            .astype(laya_native::mlx::Dtype::Float32, s)
            .unwrap()
            .to_f32_vec(s)
            .unwrap();
        laya_native::mlx::synchronize_stream(s).unwrap();
        samples.push(t0.elapsed().as_secs_f64() * 1e3);
        next = v[0] as i32;
    }
    samples.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let p50 = samples[samples.len() / 2];
    let p90 = samples[(samples.len() as f64 * 0.9) as usize % samples.len()];
    println!(
        "rust decode ctx={ctx_len} n={} p50={p50:.2}ms p90={p90:.2}ms",
        samples.len()
    );
    if std::env::var_os("LAYA_QWEN_PROFILE").is_some_and(|v| !v.is_empty()) {
        laya_native::qwen::qwen_profile_flush();
    }
}
