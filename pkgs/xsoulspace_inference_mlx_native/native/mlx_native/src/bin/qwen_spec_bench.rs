//! ADR 0057 bottleneck-1 measurement bench: plain AR decode vs draft-model
//! speculative greedy decode at K in {2,4,8}, on the fixture-proven Qwen3
//! engine. Companion to tests/qwen_spec_decode.rs (the exactness gate);
//! this binary measures the honest tok/s multiplier and the acceptance
//! rate Line B's projections need.
//!
//! POWER law (ADR 0061): every run records the FRESH power state beside
//! its numbers (`power::facts().describe()`); on battery the run is
//! annotated POWER-CONTAMINATED — non-baseline — and no gate asserts
//! (this bench asserts nothing about speed; it only reports).
//!
//! Method: cells = base + each K; 2 warmup + 3 measured runs per
//! (prompt, cell); runs INTERLEAVED round-robin with the cell order
//! rotated per repetition so thermal drift hits all cells equally.
//! Decode-only time is measured with the clock at the SAME place for both
//! legs: the base leg runs an operation-identical replica of the
//! `generate_greedy` decode loop (same chunked prefill, same
//! forward_step+argmax+f32 readback) with the clock started after prefill;
//! the speculative leg carries the in-loop decode clock from
//! `generate_greedy_speculative_with_stats`. Every run's generated suffix
//! must equal the plain greedy reference token-for-token (greedy
//! verification is exact); any divergence is reported and fails the exit
//! code.
//!
//! Usage: qwen_spec_bench [steps] [k_list]   (defaults 128, "2,4,8")
//! Env: QWEN3_TARGET_SNAPSHOT / QWEN3_DRAFT_SNAPSHOT override the HF-hub
//! snapshot discovery (fragments "Qwen3-1.7B-4bit" / "Qwen3-0.6B-4bit");
//! LAYA_SPEC_SNAPSHOT_DIR pins ONE dir for both (the gate test's knob).
//! LAYA_SPEC_WARMUP / LAYA_SPEC_REPS override 2 / 3.

use mlx_native::mlx::{self, Array, Dtype, MlxResult};
use mlx_native::power::{facts, PowerSource};
use mlx_native::qwen::{KvCache, Qwen3, SpecStats};
use std::path::{Path, PathBuf};
use std::time::Instant;

fn snapshot(fragment: &str) -> Option<PathBuf> {
    if let Some(dir) = std::env::var_os("LAYA_SPEC_SNAPSHOT_DIR") {
        let p = PathBuf::from(dir);
        return if p.is_dir() { Some(p) } else { None };
    }
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

fn explicit(env: &str) -> Option<PathBuf> {
    std::env::var_os(env).map(PathBuf::from).filter(|p| p.is_dir())
}

fn weights_bytes(dir: &Path) -> u64 {
    // model.safetensors entries (symlinks into the blob store — metadata
    // follows them). Single-shard for both sizes used here.
    let st = dir.join("model.safetensors");
    if let Ok(m) = std::fs::metadata(&st) {
        return m.len();
    }
    let mut total = 0u64;
    if let Ok(idx) = std::fs::read_to_string(dir.join("model.safetensors.index.json")) {
        if let Ok(v) = serde_json::from_str::<serde_json::Value>(&idx) {
            if let Some(map) = v["weight_map"].as_object() {
                let mut shards: Vec<&str> = map.values().filter_map(|v| v.as_str()).collect();
                shards.sort();
                shards.dedup();
                for shard in shards {
                    if let Ok(m) = std::fs::metadata(dir.join(shard)) {
                        total += m.len();
                    }
                }
            }
        }
    }
    total
}

fn rss_kb() -> u64 {
    let pid = std::process::id().to_string();
    if let Ok(out) = std::process::Command::new("ps").args(["-o", "rss=", "-p", &pid]).output() {
        if out.status.success() {
            if let Ok(t) = String::from_utf8(out.stdout) {
                if let Ok(v) = t.trim().parse::<u64>() {
                    return v;
                }
            }
        }
    }
    0
}

fn power_now() -> (String, bool) {
    let f = facts();
    (f.describe(), f.source == PowerSource::Battery)
}

fn median(v: &mut [f64]) -> f64 {
    v.sort_by(|a, b| a.partial_cmp(b).unwrap());
    if v.is_empty() {
        0.0
    } else {
        v[v.len() / 2]
    }
}

struct Cell {
    name: String,
    k: usize, // 0 = plain greedy baseline
}

struct Run {
    rep: usize,
    warmup: bool,
    prompt: usize,
    cell: usize,
    wall: f64,
    decode: f64,
    stats: Option<SpecStats>,
    rss_kb: u64,
    power: String,
    exact: bool,
}

/// Operation-identical replica of the `generate_greedy` decode loop (same
/// up-front KV reservation, same chunked prefill over prompt[..len-1],
/// same forward_step + argmax + f32 readback) with the clock started after
/// prefill and stopped after the last readback — the same clock placement
/// as `SpecStats::decode`, so base and speculative decode-only times are
/// measured the same way. The caller verifies the returned tokens against
/// the `generate_greedy` reference every run.
fn plain_decode(
    target: &Qwen3,
    prompt: &[i32],
    steps: usize,
    s: mlx_native::mlx::Stream,
) -> MlxResult<(Vec<i32>, std::time::Duration)> {
    let mut cache = KvCache::new(target.cfg.layers);
    cache.reserve(
        target.table(),
        target.cfg.kv_heads,
        target.cfg.head_dim,
        prompt.len() + steps,
        s,
    )?;
    let mut rest: &[i32] = prompt;
    const CHUNK: usize = 2048;
    while rest.len() > 1 {
        let n = CHUNK.min(rest.len() - 1);
        let t = Array::from_data_i32(&rest[..n], &[1, n])?;
        target.forward_hidden(&t, &mut cache, s)?;
        rest = &rest[n..];
    }
    let clock = Instant::now();
    let mut next = rest[0];
    let mut out = Vec::with_capacity(steps);
    for _ in 0..steps {
        let tokens = Array::from_data_i32(&[next], &[1, 1])?;
        let logits = target.forward_step(&tokens, &mut cache, s)?;
        let am = logits.argmax_axis(-1, false, s)?;
        let v = am.astype(Dtype::Float32, s)?.to_f32_vec(s)?;
        next = v.first().copied().ok_or(mlx::MlxError(-978))? as i32;
        out.push(next);
    }
    Ok((out, clock.elapsed()))
}

fn main() {
    let steps: usize = std::env::args().nth(1).and_then(|v| v.parse().ok()).unwrap_or(128);
    let k_list: Vec<usize> = std::env::args()
        .nth(2)
        .unwrap_or_else(|| "2,4,8".to_string())
        .split(',')
        .filter_map(|v| v.parse().ok())
        .filter(|k: &usize| *k > 0)
        .collect();
    let warmups: usize = std::env::var("LAYA_SPEC_WARMUP").ok().and_then(|v| v.parse().ok()).unwrap_or(2);
    let reps: usize = std::env::var("LAYA_SPEC_REPS").ok().and_then(|v| v.parse().ok()).unwrap_or(3);
    if k_list.is_empty() {
        eprintln!("k_list must contain at least one K > 0 (e.g. \"2,4,8\")");
        std::process::exit(2);
    }

    let (power0, battery0) = power_now();
    let machine = std::process::Command::new("sysctl")
        .args(["-n", "machdep.cpu.brand_string"])
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_else(|| "unknown".to_string());
    println!("machine: {machine}");
    println!("power at start: {power0}");
    if battery0 {
        println!("POWER-CONTAMINATED — non-baseline (ADR 0061): running on battery; numbers are NOT baseline and no gate applies");
    }

    let metallib = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        let _ = mlx::set_metallib_path(&metallib);
    }
    let s = mlx::gpu().expect("Metal device");

    let target_dir = explicit("QWEN3_TARGET_SNAPSHOT")
        .or_else(|| snapshot("Qwen3-1.7B-4bit"))
        .expect("target snapshot (Qwen3-1.7B-4bit) absent");
    let draft_dir = explicit("QWEN3_DRAFT_SNAPSHOT")
        .or_else(|| snapshot("Qwen3-0.6B-4bit"))
        .expect("draft snapshot (Qwen3-0.6B-4bit) absent");
    let t0 = Instant::now();
    let target = Qwen3::load(&target_dir).expect("target loads");
    let draft = Qwen3::load(&draft_dir).expect("draft loads");
    println!(
        "target: {} ({}L h{} kv{} dh{}, {:.2} GB on disk) | draft: {} ({}L h{} kv{} dh{}, {:.2} GB) | loaded in {:.1}s",
        target_dir.file_name().unwrap().to_string_lossy(),
        target.cfg.layers, target.cfg.hidden_size, target.cfg.kv_heads, target.cfg.head_dim,
        weights_bytes(&target_dir) as f64 / 1e9,
        draft_dir.file_name().unwrap().to_string_lossy(),
        draft.cfg.layers, draft.cfg.hidden_size, draft.cfg.kv_heads, draft.cfg.head_dim,
        weights_bytes(&draft_dir) as f64 / 1e9,
        t0.elapsed().as_secs_f64()
    );

    let bpe = mlx_native::bpe::ByteLevelBpe::load(&target_dir)
        .or_else(|_| mlx_native::bpe::ByteLevelBpe::load_tokenizer_json(&target_dir))
        .expect("tokenizer loads from target snapshot");

    let prompt_texts: [&str; 3] = [
        // (1) short chat
        "Write a friendly two-sentence thank-you note to a friend who lent you their favorite book.",
        // (2) code-ish
        "Write a Rust function `fn median(mut v: Vec<f64>) -> f64` that returns the median of a \
         vector, handling even lengths by averaging the two middle values, then explain the steps \
         in two sentences.",
        // (3) long continuation (~200 tokens of prose ending mid-thought)
        "The tide leaves a thin silver film on the black basalt as it withdraws, and for a few \
         seconds the whole shelf of rock shines like the inside of a shell. Gulls stand at the \
         edge with their backs to the wind, not hunting, just holding their ground the way old \
         fishermen hold a rail. Further out the swell moves through the kelp in long slow \
         breaths, each one lifting the fronds and letting them fall without a sound. The path \
         above the beach is already warm, and a farmer's tractor ticks somewhere behind the \
         hedge, doing whatever tractors do on a morning too fine to hurry. Continue this text \
         in the same voice:",
    ];
    let prompts: Vec<Vec<i32>> = prompt_texts
        .iter()
        .map(|t| bpe.encode(t).expect("encode").into_iter().map(|u| u as i32).collect())
        .collect();
    for (i, (text, ids)) in prompt_texts.iter().zip(&prompts).enumerate() {
        let preview: String = text.chars().take(28).collect();
        println!("prompt {i}: {} tokens — \"{preview}...\"", ids.len());
    }

    let mut cells: Vec<Cell> = vec![Cell { name: "base".to_string(), k: 0 }];
    cells.extend(k_list.iter().map(|k| Cell { name: format!("k{k}"), k: *k }));

    // Per-prompt greedy REFERENCE from the fixture-proven crate path
    // (untimed; every measured run — base replica AND speculative — must
    // reproduce this suffix token-for-token). This call also absorbs the
    // engine's one-time per-process costs before any clock starts.
    let mut reference: Vec<Vec<i32>> = Vec::with_capacity(prompts.len());
    for (i, p) in prompts.iter().enumerate() {
        let t = Instant::now();
        let out = target.generate_greedy(p, steps, None, s).expect("reference greedy");
        println!(
            "reference prompt {i}: generate_greedy {} tokens in {:.2}s (whole call, context only)",
            out.len() - p.len(),
            t.elapsed().as_secs_f64()
        );
        reference.push(out[p.len()..].to_vec());
    }

    // Interleaved matrix: each repetition sweeps every (prompt, cell) once
    // with the cell order rotated, so warm-up legs and measured legs see
    // the same thermal schedule.
    let mut runs: Vec<Run> = Vec::new();
    let mut diverged_measured = 0usize;
    let mut battery_seen = battery0;

    for rep in 0..(warmups + reps) {
        let warmup = rep < warmups; // warmups FIRST, then measured
        for pi in 0..prompts.len() {
            for ci in 0..cells.len() {
                let rotated = (ci + rep) % cells.len();
                let cell = &cells[rotated];
                let (power, battery) = power_now();
                battery_seen |= battery;
                let t = Instant::now();
                let (suffix, decode, stats) = if cell.k == 0 {
                    let (out, dt) =
                        plain_decode(&target, &prompts[pi], steps, s).expect("plain decode");
                    (out, dt.as_secs_f64(), None)
                } else {
                    let (out, st) = target
                        .generate_greedy_speculative_with_stats(&draft, &prompts[pi], steps, cell.k, s)
                        .expect("speculative greedy");
                    (out, st.decode.as_secs_f64(), Some(st))
                };
                let wall = t.elapsed().as_secs_f64();
                let exact = suffix == reference[pi];
                if !exact {
                    if warmup {
                        eprintln!("WARMUP divergence prompt {pi} cell {} — reported, not fatal", cell.name);
                    } else {
                        diverged_measured += 1;
                        eprintln!("DIVERGENCE prompt {pi} cell {} vs plain greedy reference", cell.name);
                    }
                }
                let rss = rss_kb();
                println!(
                    "{:>4} {} prompt {pi} cell {:>4}: wall {:7.3}s decode {:7.3}s {:6.1} tok/s{:} rss {rss} KB [{}]",
                    if warmup { "warm" } else { "meas" },
                    if exact { "ok " } else { "BAD" },
                    cell.name,
                    wall,
                    decode,
                    steps as f64 / decode.max(1e-9),
                    stats.map(|st| format!(" acc {}/{} ({:.0}%) rounds {}", st.accepted, st.drafted, 100.0 * st.accepted as f64 / st.drafted.max(1) as f64, st.rounds)).unwrap_or_default(),
                    power,
                );
                runs.push(Run {
                    rep,
                    warmup,
                    prompt: pi,
                    cell: rotated,
                    wall,
                    decode,
                    stats,
                    rss_kb: rss,
                    power,
                    exact,
                });
            }
        }
    }

    let (power_end, battery_end) = power_now();
    battery_seen |= battery_end;

    // Summary: measured legs only. Medians per (prompt, cell); multiplier
    // against the SAME prompt's base cell, both on the decode-only clock.
    if reps == 0 {
        println!("\nno measured runs (LAYA_SPEC_REPS=0) — smoke/validate mode, no speed data");
        if diverged_measured > 0 {
            std::process::exit(1);
        }
        return;
    }
    println!("\n=== SUMMARY (medians of {reps} measured runs; decode-only clock after prefill; multiplier on decode-only) ===");
    let mut summary = serde_json::Map::new();
    for pi in 0..prompts.len() {
        let base_decode = {
            let mut v: Vec<f64> = runs
                .iter()
                .filter(|r| !r.warmup && r.prompt == pi && r.cell == 0 && r.exact)
                .map(|r| r.decode)
                .collect();
            median(&mut v)
        };
        for (ci, cell) in cells.iter().enumerate() {
            let mut ds: Vec<f64> = runs
                .iter()
                .filter(|r| !r.warmup && r.prompt == pi && r.cell == ci && r.exact)
                .map(|r| r.decode)
                .collect();
            let mut ws: Vec<f64> = runs
                .iter()
                .filter(|r| !r.warmup && r.prompt == pi && r.cell == ci && r.exact)
                .map(|r| r.wall)
                .collect();
            let (d, w) = (median(&mut ds), median(&mut ws));
            let (acc, drafted) = runs
                .iter()
                .filter(|r| !r.warmup && r.prompt == pi && r.cell == ci)
                .fold((0usize, 0usize), |(a, d), r| {
                    (a + r.stats.map(|s| s.accepted).unwrap_or(0), d + r.stats.map(|s| s.drafted).unwrap_or(0))
                });
            let mult = d / base_decode.max(1e-9);
            println!(
                "prompt {pi} cell {:>4}: decode {:6.1} tok/s (wall {:6.1})  x{mult:.2} vs base  acc {}/{} ({:.0}%)",
                cell.name,
                steps as f64 / d.max(1e-9),
                steps as f64 / w.max(1e-9),
                acc,
                drafted,
                if drafted > 0 { 100.0 * acc as f64 / drafted as f64 } else { 0.0 },
            );
            summary.insert(
                format!("p{pi}_{}", cell.name),
                serde_json::json!({
                    "decode_tok_s": steps as f64 / d.max(1e-9),
                    "wall_tok_s": steps as f64 / w.max(1e-9),
                    "x_vs_base": mult,
                    "accepted": acc,
                    "drafted": drafted,
                }),
            );
        }
    }

    // Whole-prompt-pooled curve per cell (mean of per-prompt decode-only
    // medians) — the multiplier-vs-K line for the results doc.
    println!("\n=== multiplier-vs-K curve (mean of per-prompt decode-only multipliers) ===");
    let mut curve = serde_json::Map::new();
    for (ci, cell) in cells.iter().enumerate() {
        let mut mults = vec![];
        for pi in 0..prompts.len() {
            let base = {
                let mut v: Vec<f64> = runs
                    .iter()
                    .filter(|r| !r.warmup && r.prompt == pi && r.cell == 0 && r.exact)
                    .map(|r| r.decode)
                    .collect();
                median(&mut v)
            };
            let mut v: Vec<f64> = runs
                .iter()
                .filter(|r| !r.warmup && r.prompt == pi && r.cell == ci && r.exact)
                .map(|r| r.decode)
                .collect();
            mults.push(median(&mut v) / base.max(1e-9));
        }
        let m = mults.iter().sum::<f64>() / mults.len().max(1) as f64;
        println!("cell {:>4}: x{m:.2}", cell.name);
        curve.insert(cell.name.clone(), serde_json::json!(m));
    }

    let peak_rss = runs.iter().map(|r| r.rss_kb).max().unwrap_or(0);
    let mut powers: Vec<String> = runs.iter().map(|r| r.power.clone()).collect();
    powers.sort();
    powers.dedup();
    if battery_seen {
        println!("\nPOWER-CONTAMINATED — non-baseline (ADR 0061): battery was the source at some point in this run; treat every number as non-baseline");
    }
    println!("peak rss (ps, sampled per run): {peak_rss} KB");
    println!("power states seen during runs: {powers:?}");
    println!("power at end: {power_end}");
    println!(
        "self-consistency: {diverged_measured} measured divergences vs plain greedy (must be 0 — greedy verification is exact)"
    );

    println!(
        "##SPEC_JSON## {}",
        serde_json::json!({
            "machine": machine,
            "power_start": power0,
            "power_end": power_end,
            "power_states_seen": powers,
            "battery_seen": battery_seen,
            "steps": steps,
            "warmups": warmups,
            "reps": reps,
            "peak_rss_kb": peak_rss,
            "diverged_measured": diverged_measured,
            "summary": summary,
            "curve": curve,
            "runs": runs.iter().map(|r| serde_json::json!({
                "rep": r.rep, "warmup": r.warmup, "prompt": r.prompt, "cell": cells[r.cell].name,
                "wall_s": r.wall, "decode_s": r.decode,
                "accepted": r.stats.map(|s| s.accepted), "drafted": r.stats.map(|s| s.drafted),
                "rss_kb": r.rss_kb, "power": r.power, "exact": r.exact,
            })).collect::<Vec<_>>(),
        })
    );

    if diverged_measured > 0 {
        std::process::exit(1);
    }
}
