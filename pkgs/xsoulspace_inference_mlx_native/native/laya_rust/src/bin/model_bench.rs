//! Consolidated text-model benchmark (ADR 0055 evidence ladder): load,
//! prefill throughput, and decode tok/s (fresh + 2k context) for every
//! cached checkpoint this dylib serves. Not a gate — a measurement tool;
//! the ADR owns verdicts. Power state and chip are recorded per the
//! ADR 0051 law (benchmarks state AC/battery).
//!
//! Prompts are synthetic (deterministic id sequence — timing only, not a
//! parity probe; parity fixtures are separate and pinned). A model row
//! skips honestly when its snapshot is absent or it fails to load (the
//! loader is proven per-arch by the parity gates; the bench only times
//! what loads).
//!
//! Usage: model_bench [steps=32] [prefill_tokens=512]

use std::path::{Path, PathBuf};
use std::time::Instant;

use laya_native::mlx::{self, Array, Dtype, Stream};

fn find_snapshot(fragment: &str) -> Option<PathBuf> {
    let home = std::env::var("HOME").ok()?;
    let hub = Path::new(&home).join(".cache/huggingface/hub");
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

fn power_state() -> String {
    if let Ok(out) = std::process::Command::new("pmset").args(["-g", "batt"]).output() {
        let s = String::from_utf8_lossy(&out.stdout);
        if s.contains("AC Power") {
            return "AC".into();
        }
        if s.contains("Battery Power") {
            return "battery".into();
        }
    }
    "unknown".into()
}

fn chip() -> String {
    std::process::Command::new("sysctl")
        .args(["-n", "machdep.cpu.brand_string"])
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_else(|| "unknown".into())
}

/// Deterministic synthetic ids in [0, 32000) — valid for every served
/// checkpoint (qwen vocab 151936, LFM2 65536); timing only.
fn synthetic_ids(n: usize) -> Vec<i32> {
    (0..n).map(|i| ((i as u64 * 7919 + 13) % 32000) as i32).collect()
}

fn pct(samples: &[f64], p: f64) -> f64 {
    let mut s = samples.to_vec();
    s.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let idx = ((s.len() as f64 - 1.0) * p).round() as usize;
    s[idx.min(s.len() - 1)]
}

/// Prefill `ids` (forward_hidden, no lm_head — what generate's chunk loop
/// does), then `steps` greedy single-token passes; returns (prefill
/// seconds, per-step ms).
fn run_qwen(
    model: &laya_native::qwen::Qwen3,
    ids: &[i32],
    steps: usize,
    s: Stream,
) -> Result<(f64, Vec<f64>), String> {
    let mut cache = laya_native::qwen::KvCache::new(model.cfg.layers);
    cache
        .reserve(model.table(), model.cfg.kv_heads, model.cfg.head_dim, ids.len() + steps, s)
        .map_err(|e| format!("reserve: mlx status {}", e.0))?;
    let t0 = Instant::now();
    let t = Array::from_data_i32(ids, &[1, ids.len()])
        .map_err(|e| format!("mlx status {}", e.0))?;
    let hidden = model
        .forward_hidden(&t, &mut cache, s)
        .map_err(|e| format!("prefill: mlx status {}", e.0))?;
    // The prefill graph is lazy — eval + sync INSIDE the prefill timer so
    // the first decode step pays only decode (the lazy-eval lesson:
    // synchronize alone waits for SUBMITTED work; eval schedules it).
    hidden.eval().map_err(|e| format!("prefill eval: mlx status {}", e.0))?;
    mlx::synchronize_stream(s).map_err(|e| format!("sync: mlx status {}", e.0))?;
    let prefill = t0.elapsed().as_secs_f64();
    let mut per_step = Vec::with_capacity(steps);
    let mut next = ids[ids.len() - 1];
    for _ in 0..steps {
        let st = Instant::now();
        let tokens =
            Array::from_data_i32(&[next], &[1usize, 1usize]).map_err(|e| format!("mlx status {}", e.0))?;
        let logits = model
            .forward_step(&tokens, &mut cache, s)
            .map_err(|e| format!("decode: mlx status {}", e.0))?;
        let am = logits.argmax_axis(-1, false, s).map_err(|e| format!("mlx status {}", e.0))?;
        let f = am.astype(Dtype::Float32, s).map_err(|e| format!("mlx status {}", e.0))?;
        let v = f.to_f32_vec(s).map_err(|e| format!("mlx status {}", e.0))?;
        per_step.push(st.elapsed().as_secs_f64() * 1000.0);
        next = *v.first().ok_or("empty argmax")? as i32;
    }
    Ok((prefill, per_step))
}

/// Same shape for the LFM2 hybrid (conv-state layers ride `cache`).
fn run_lfm2(
    model: &laya_native::lfm2::Lfm2,
    ids: &[i32],
    steps: usize,
    s: Stream,
) -> Result<(f64, Vec<f64>), String> {
    let mut cache = laya_native::lfm2::Lfm2Cache::new(&model.cfg.layer_types);
    cache
        .reserve(model.table(), model.cfg.kv_heads, model.cfg.head_dim, ids.len() + steps, s)
        .map_err(|e| format!("reserve: mlx status {}", e.0))?;
    let t0 = Instant::now();
    let t = Array::from_data_i32(ids, &[1, ids.len()])
        .map_err(|e| format!("mlx status {}", e.0))?;
    let hidden = model
        .forward_hidden(&t, &mut cache, s)
        .map_err(|e| format!("prefill: mlx status {}", e.0))?;
    // The prefill graph is lazy — eval + sync INSIDE the prefill timer so
    // the first decode step pays only decode (the lazy-eval lesson:
    // synchronize alone waits for SUBMITTED work; eval schedules it).
    hidden.eval().map_err(|e| format!("prefill eval: mlx status {}", e.0))?;
    mlx::synchronize_stream(s).map_err(|e| format!("sync: mlx status {}", e.0))?;
    let prefill = t0.elapsed().as_secs_f64();
    let mut per_step = Vec::with_capacity(steps);
    let mut next = ids[ids.len() - 1];
    for _ in 0..steps {
        let st = Instant::now();
        let tokens =
            Array::from_data_i32(&[next], &[1usize, 1usize]).map_err(|e| format!("mlx status {}", e.0))?;
        let logits = model
            .forward_step(&tokens, &mut cache, s)
            .map_err(|e| format!("decode: mlx status {}", e.0))?;
        let am = logits.argmax_axis(-1, false, s).map_err(|e| format!("mlx status {}", e.0))?;
        let f = am.astype(Dtype::Float32, s).map_err(|e| format!("mlx status {}", e.0))?;
        let v = f.to_f32_vec(s).map_err(|e| format!("mlx status {}", e.0))?;
        per_step.push(st.elapsed().as_secs_f64() * 1000.0);
        next = *v.first().ok_or("empty argmax")? as i32;
    }
    Ok((prefill, per_step))
}

enum Engine {
    Qwen(laya_native::qwen::Qwen3),
    Lfm2(laya_native::lfm2::Lfm2),
}

impl Engine {
    fn load(dir: &Path) -> Result<Engine, String> {
        let cfg = std::fs::read_to_string(dir.join("config.json"))
            .map_err(|e| e.to_string())?;
        let is_lfm2 = serde_json::from_str::<serde_json::Value>(&cfg)
            .ok()
            .and_then(|v| v.get("layer_types").cloned())
            .map(|v| !v.is_null())
            .unwrap_or(false);
        if is_lfm2 {
            laya_native::lfm2::Lfm2::load(dir)
                .map(Engine::Lfm2)
                .map_err(|e| format!("mlx status {}", e.0))
        } else {
            laya_native::qwen::Qwen3::load(dir)
                .map(Engine::Qwen)
                .map_err(|e| format!("mlx status {}", e.0))
        }
    }

    fn run(&self, ids: &[i32], steps: usize, s: Stream) -> Result<(f64, Vec<f64>), String> {
        match self {
            Engine::Qwen(model) => run_qwen(model, ids, steps, s),
            Engine::Lfm2(model) => run_lfm2(model, ids, steps, s),
        }
    }
}

struct Bench {
    name: &'static str,
    arch: &'static str,
    quant: &'static str,
}

/// One case: prefill THROUGHPUT (tok/s, sync included) and per-step ms.
fn bench_case(
    engine: &Engine,
    prefill_tokens: usize,
    steps: usize,
    s: Stream,
) -> Result<(f64, Vec<f64>), String> {
    let ids = synthetic_ids(prefill_tokens);
    let (prefill_s, per_step_ms) = engine.run(&ids, steps, s)?;
    let pre_tok_s = if prefill_s > 0.0 { prefill_tokens as f64 / prefill_s } else { 0.0 };
    Ok((pre_tok_s, per_step_ms))
}

fn main() {
    let steps: usize = std::env::args().nth(1).and_then(|v| v.parse().ok()).unwrap_or(32);
    let prefill_tokens: usize = std::env::args()
        .nth(2)
        .and_then(|v| v.parse().ok())
        .unwrap_or(512);

    let metallib = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        let _ = laya_native::mlx::set_metallib_path(&metallib);
    }
    let s = mlx::gpu().expect("Metal device");
    println!(
        "model_bench: {steps} decode steps/case, prefill {prefill_tokens}, power {}, chip `{}`, {}",
        power_state(),
        chip(),
        if cfg!(debug_assertions) { "DEBUG (not for verdicts)" } else { "release" }
    );

    let benches = [
        Bench { name: "Qwen3-0.6B-4bit", arch: "dense GQA", quant: "q4 g64" },
        Bench { name: "Qwen3-0.6B-bf16", arch: "dense GQA", quant: "bf16" },
        Bench { name: "Qwen3-1.7B-4bit", arch: "dense GQA", quant: "q4 g64" },
        Bench { name: "LFM2.5-1.2B-Instruct-MLX-4bit", arch: "hybrid conv+GQA", quant: "q4 g64" },
        Bench { name: "LFM2-700M-4bit", arch: "hybrid conv+GQA", quant: "q4 g64" },
    ];

    println!(
        "| model | load s | prefill {prefill_tokens} tok/s | decode tok/s | p50 ms | p90 ms | decode@2k tok/s | p50 ms | p90 ms |"
    );
    println!("|---|---|---|---|---|---|---|---|---|");
    for b in benches {
        let skip = |why: &str| {
            println!("| {} ({}, {}) | skip: {why} | | | | | | | |", b.name, b.arch, b.quant);
        };
        let Some(dir) = find_snapshot(b.name) else {
            skip("snapshot absent");
            continue;
        };
        let t0 = Instant::now();
        let engine = match Engine::load(&dir) {
            Ok(e) => e,
            Err(e) => {
                skip(&format!("load failed: {e}"));
                continue;
            }
        };
        let load_s = t0.elapsed().as_secs_f64();

        // Warmup (kernel first-touch / compile), then the measured cases.
        if let Err(e) = bench_case(&engine, 64, 2, s) {
            skip(&format!("warmup failed: {e}"));
            continue;
        }
        let Ok((pre_512, fresh_steps)) = bench_case(&engine, prefill_tokens, steps, s) else {
            skip(&format!("fresh case failed"));
            continue;
        };
        let fresh_tok_s =
            fresh_steps.len() as f64 / fresh_steps.iter().sum::<f64>() * 1000.0;
        let mut row = format!(
            "{load_s:.2} | {pre_512:.0} | {fresh_tok_s:.1} | {:.1} | {:.1}",
            pct(&fresh_steps, 0.5),
            pct(&fresh_steps, 0.9),
        );
        match bench_case(&engine, 2048, steps, s) {
            Ok((_, steps_2k)) => {
                let tok_s = steps_2k.len() as f64 / steps_2k.iter().sum::<f64>() * 1000.0;
                row.push_str(&format!(
                    " | {tok_s:.1} | {:.1} | {:.1}",
                    pct(&steps_2k, 0.5),
                    pct(&steps_2k, 0.9)
                ));
            }
            Err(_) => row.push_str(" | n/a | n/a | n/a"),
        }
        println!("| {} ({}, {}) | {row} |", b.name, b.arch, b.quant);
    }
}
