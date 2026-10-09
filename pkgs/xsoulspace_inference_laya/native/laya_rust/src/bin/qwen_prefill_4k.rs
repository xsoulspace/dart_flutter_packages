//! R5 UI-coexistence runner: a 4k-token chunked prefill with optional
//! cooperative yields between chunks — the pattern a UI scheduler uses to
//! keep the GPU compositor fed during long prefills. The Swift frame gate
//! (tool/frame_gate.swift) spawns this and counts dropped vsyncs.
//!
//! Usage: qwen_prefill_4k [pace_ms]
//!   pace_ms = 0  → chunks back-to-back (unpaced)
//!   pace_ms = N  → sleep N ms after every 256-token chunk

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
    let pace_ms: u64 = std::env::args()
        .nth(1)
        .and_then(|v| v.parse().ok())
        .unwrap_or(0);
    let metallib = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        let _ = laya_native::mlx::set_metallib_path(&metallib);
    }
    let s = laya_native::mlx::gpu().expect("Metal");
    let snap = snapshot();
    let model = laya_native::qwen::Qwen3::load(&snap).expect("model loads");

    // 4k prompt: the fixture prompt repeated (BPE-stable).
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
    let mut ids: Vec<i32> = Vec::with_capacity(4096);
    while ids.len() < 4096 {
        ids.extend_from_slice(&base);
    }
    ids.truncate(4096);

    // Warmup so load-time compile costs don't pollute the window.
    let mut cache = laya_native::qwen::KvCache::new(model.cfg.layers);
    let warm = Array4k::from(&base[..8]);
    let _ = model.forward_hidden(&warm, &mut cache, s);

    let mut cache = laya_native::qwen::KvCache::new(model.cfg.layers);
    let t0 = std::time::Instant::now();
    let mut chunks = 0usize;
    let mut rest: &[i32] = &ids;
    const CHUNK: usize = 256;
    while rest.len() > 1 {
        let n = CHUNK.min(rest.len() - 1);
        let t = laya_native::mlx::Array::from_data_i32(&rest[..n], &[1, n]).unwrap();
        let _ = model.forward_hidden(&t, &mut cache, s).unwrap();
        // Await the chunk (what a UI driver does — the yield only means
        // something if the GPU work is actually submitted and done).
        if let Some(k0) = &cache.layers_ref()[0].k {
            let _ = k0.eval();
        }
        laya_native::mlx::synchronize_stream(s).unwrap();
        rest = &rest[n..];
        chunks += 1;
        if pace_ms > 0 {
            std::thread::sleep(std::time::Duration::from_millis(pace_ms));
        }
    }
    // One final 1-token step (computes logits — the real TTFT tail).
    let last = laya_native::mlx::Array::from_data_i32(&[rest[0]], &[1, 1]).unwrap();
    let logits = model.forward_step(&last, &mut cache, s).unwrap();
    let _ = logits.eval();
    laya_native::mlx::synchronize_stream(s).unwrap();
    let _ = cache.offset;
    println!(
        "{{\"ttft_ms\": {:.1}, \"chunks\": {}, \"pace_ms\": {}, \"prompt\": {}}}",
        t0.elapsed().as_secs_f64() * 1e3,
        chunks,
        pace_ms,
        ids.len()
    );
}

/// Tiny helper so the warmup can build an array without importing serde
/// paths everywhere.
struct Array4k;
impl Array4k {
    fn from(ids: &[i32]) -> laya_native::mlx::Array {
        laya_native::mlx::Array::from_data_i32(ids, &[1, ids.len()]).unwrap()
    }
}
