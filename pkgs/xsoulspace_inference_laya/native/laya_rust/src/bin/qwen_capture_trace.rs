//! ADR 0055 P1 capture harness: prefill to a target context, then record a
//! GPU trace (`mlx_metal_start_capture` — an MTLCaptureManager document) of
//! N decode steps. The trace's per-command timings are the kernel-level
//! attribution the 3–4× long-context decode gap needs.
//!
//! Usage: qwen_capture_trace [ctx_len] [steps] [out.gputrace]
//!   ctx_len default 2048, steps default 8, out default
//!   /tmp/qwen_decode_rust.gputrace. Per-step wall time prints for the
//! captured window; the gputrace package carries the per-kernel truth.

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
    let steps: usize = std::env::args().nth(2).and_then(|v| v.parse().ok()).unwrap_or(8);
    let out = std::env::args()
        .nth(3)
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp/qwen_decode_rust.gputrace"));

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

    // Prefill outside the capture; sync so the trace window holds only the
    // decode steps.
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

    let _ = std::fs::remove_file(&out);
    laya_native::mlx::start_capture(&out).expect("capture starts");
    let mut next = *rest.last().unwrap();
    let mut wall = std::time::Duration::ZERO;
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
        wall += t0.elapsed();
        next = v[0] as i32;
    }
    laya_native::mlx::stop_capture().expect("capture stops");
    println!(
        "captured {steps} decode steps @ ctx {ctx_len}: wall {wall:?} ({:.2} ms/step) → {}",
        wall.as_secs_f64() * 1e3 / steps as f64,
        out.display()
    );
}
