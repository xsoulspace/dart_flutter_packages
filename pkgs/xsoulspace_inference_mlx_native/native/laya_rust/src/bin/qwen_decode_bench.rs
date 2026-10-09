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
    // ADR 0055 spike chase: mark the steps where the KV cache had to GROW
    // (offset crossed a KV_STEP boundary) — the recorded hypothesis list is
    // growth reallocs, command-buffer cadence, and DVFS.
    let mut grew: Vec<bool> = Vec::with_capacity(steps);
    for i in 0..steps {
        let tokens = laya_native::mlx::Array::from_data_i32(&[next], &[1, 1]).unwrap();
        let grew_i = (cache.offset + 1) > cache
            .layers_ref()
            .first()
            .and_then(|l| l.k.as_ref())
            .map(|k| k.dim(2) as usize)
            .unwrap_or(0);
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
        grew.push(grew_i);
        next = v[0] as i32;
        if std::env::var_os("LAYA_DECODE_SAMPLES").is_some_and(|v| !v.is_empty()) {
            println!(
                "step {i:3} offset {:5} grow={:5} {:7.2}ms",
                cache.offset, grew_i, samples[i]
            );
        }
    }
    let grew_median: Vec<f64> = samples
        .iter()
        .zip(&grew)
        .filter(|(_, g)| **g)
        .map(|(s, _)| *s)
        .collect();
    if !grew_median.is_empty() {
        let mut g = grew_median.clone();
        g.sort_by(|a, b| a.partial_cmp(b).unwrap());
        println!(
            "growth steps: n={} p50={:.2}ms ({})",
            g.len(),
            g[g.len() / 2],
            grew
                .iter()
                .enumerate()
                .filter(|(_, g)| **g)
                .map(|(i, _)| i.to_string())
                .collect::<Vec<_>>()
                .join(",")
        );
    }

    // In-process A/B (ADR 0055 spike fix): reserve the remaining window —
    // what generate_greedy now does up front — and keep decoding. Same
    // process, same power state; the ONLY difference is the reservation.
    let half = steps / 2;
    if half > 0 {
        cache
            .reserve(
                model.table(),
                model.cfg.kv_heads,
                model.cfg.head_dim,
                cache.offset + half + 1,
                s,
            )
            .expect("reserve");
        let mut after: Vec<f64> = Vec::with_capacity(half);
        for _ in 0..half {
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
            after.push(t0.elapsed().as_secs_f64() * 1e3);
            next = v[0] as i32;
        }
        after.sort_by(|a, b| a.partial_cmp(b).unwrap());
        println!(
            "after reserve ({} steps): p50={:.2}ms p90={:.2}ms",
            half,
            after[after.len() / 2],
            after[(after.len() as f64 * 0.9) as usize % after.len()]
        );
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
