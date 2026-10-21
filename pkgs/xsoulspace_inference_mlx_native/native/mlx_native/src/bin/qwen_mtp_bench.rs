//! MTP-GATES J-G4 bench: the plain greedy lane vs the native MTP draft-head
//! lane on the real Qwen3 checkpoint, INTERLEAVED in one process.
//!
//! WHAT IS MEASURED. Three legs, all on the same trunk:
//!
//!   * `base` — the plain greedy decode (the baseline).
//!   * `mtpK`  — the MTP decode at count K: K chained draft heads propose
//!     tokens, ONE batched trunk forward verifies them, the accepted prefix is
//!     committed. The draft head is a HEAD, not a second model.
//!
//! THE COST THAT MATTERS. The draft head must produce a TOKEN, so it pays
//! the trunk's tied vocab projection (the reference's `as_linear`) — once per
//! head, because the chain is sequential (head j needs head j-1's argmax to
//! pick its input token). That projection is NOT free (~6.3 ms on the 4-bit
//! checkpoint) and the old lane's cost model omitted it entirely, which made
//! the draft look ~100x cheaper than it is. This bench therefore reports the
//! head's own lm_head time SEPARATELY from the trunk's verify time, and the
//! ratio below is computed on the WHOLE cycle.
//!
//! THE MEASUREMENT IS REAL. MLX is lazy: `fn()` returns an unevaluated
//! graph. Every timed iteration forces the ACTUAL output (`eval()` on the
//! array the loop consumes, and a synchronized readback of the argmax), so
//! what is timed is execution, not graph construction.
//!
//! THE A/B IS INTERLEAVED (POWER.md / ADR 0061): both arms run in the same
//! process, the cell order is rotated per repetition, and the power state is
//! recorded beside every run. Cross-run comparisons are thermal-contaminated;
//! the RATIO is the measurement.
//!
//! THE EXACTNESS GATE. Greedy verification is exact: the MTP lane's output
//! MUST equal the plain greedy output token-for-token. Any divergence is
//! reported and fails the exit code (J-G4).
//!
//! Usage:
//!   qwen_mtp_bench [--steps N] [--k 1,2,3] [--prompts N] [--head FILE]
//! Env:
//!   MTP_HEAD               the head safetensors (model.mtp.d{j}.*)
//!   MTP_HEAD_SCALE         the head's residual scale (default 1.0)
//!   LAYA_MTP_SNAPSHOT_DIR  pin ONE trunk snapshot dir
//!   QWEN3_TARGET_SNAPSHOT  pin the trunk snapshot dir explicitly
//!   LAYA_MTP_WARMUP        warmup repetitions (default 2)
//!   LAYA_MTP_REPS          measured repetitions (default 3)

use mlx_native::mlx::{self, Array, Dtype, MlxResult, Stream};
use mlx_native::power::{facts, PowerSource};
use mlx_native::qwen::{KvCache, Qwen3};
use mlx_native::qwen_mtp::{generate_greedy_mtp, MtpChain, MtpHead, MtpStats, TiedEmbedding};
use std::path::{Path, PathBuf};
use std::time::Instant;

fn usage() -> String {
    "qwen_mtp_bench — plain greedy vs the native MTP draft-head lane (interleaved A/B)\n\n\
     Usage: qwen_mtp_bench [--steps N] [--k 1,2,3] [--prompts N] [--head FILE]\n\n\
     Options:\n\
     \x20 --steps N        generated tokens per run (default 64)\n\
     \x20 --k LIST         the MTP counts to measure, comma separated (default 1,2,3)\n\
     \x20 --prompts N      how many of the built-in prompts to use (default 3)\n\
     \x20 --head FILE      the head safetensors (model.mtp.d{j}.*); without it a\n\
     \x20                   deterministic UNTRAINED head is synthesised and the run is\n\
     \x20                   annotated as such\n\
     \x20 --prompt-source SOURCE  corpus | builtin (default: corpus when the nursery\n\
     \x20                   corpus is present — it is the head's training distribution)\n\
     -h, --help          this text\n\n\
     Env: MTP_HEAD, MTP_HEAD_SCALE, LAYA_MTP_SNAPSHOT_DIR, QWEN3_TARGET_SNAPSHOT,\n\
     \x20    LAYA_MTP_WARMUP, LAYA_MTP_REPS"
        .to_string()
}

/// The cached HF-hub snapshot dir for a model-name fragment.
fn snapshot(fragment: &str) -> Option<PathBuf> {
    if let Some(dir) = std::env::var_os("LAYA_MTP_SNAPSHOT_DIR") {
        let p = PathBuf::from(dir);
        return if p.is_dir() { Some(p) } else { None };
    }
    if let Some(dir) = std::env::var_os("QWEN3_TARGET_SNAPSHOT") {
        let p = PathBuf::from(dir);
        return if p.is_dir() { Some(p) } else { None };
    }
    let home = std::env::var("HOME").ok()?;
    let hub = Path::new(&home).join(".cache/huggingface/hub");
    for e in std::fs::read_dir(hub).ok()?.flatten() {
        if e.file_name().to_string_lossy().contains(fragment) {
            for s in std::fs::read_dir(e.path().join("snapshots"))
                .ok()?
                .flatten()
            {
                if s.path().join("config.json").is_file() {
                    return Some(s.path());
                }
            }
        }
    }
    None
}

/// The signed mA from `ioreg -rn AppleSmartBattery` (POWER.md: the pmset
/// "AC" flag is NOT charge current; the amperage is the gate input).
fn amperage_ma() -> Option<i64> {
    let out = std::process::Command::new("ioreg")
        .args(["-rn", "AppleSmartBattery"])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&out.stdout);
    let idx = text.find("\"Amperage\"")?;
    let rest = &text[idx..];
    let eq = rest.find('=')? + 1;
    let tail = rest[eq..].trim_start();
    let end = tail
        .find(|c: char| !c.is_ascii_digit() && c != '-')
        .unwrap_or(tail.len());
    let raw = tail[..end].trim();
    let (neg, digits) = match raw.strip_prefix('-') {
        Some(d) => (true, d),
        None => (false, raw),
    };
    // ioreg prints negative currents as unsigned 64-bit; the cast wraps back
    // to the signed value.
    let v: u64 = digits.parse().ok()?;
    let mut signed = v as i64;
    if neg {
        signed = -signed;
    }
    Some(signed)
}

fn power_now() -> String {
    let f = facts();
    let mut s = f.describe();
    if let Some(ma) = amperage_ma() {
        s.push_str(&format!(" amperage {ma} mA"));
    }
    s
}

fn battery_now() -> bool {
    facts().source == PowerSource::Battery
}

fn median(v: &mut [f64]) -> f64 {
    v.sort_by(|a, b| a.partial_cmp(b).unwrap());
    if v.is_empty() {
        0.0
    } else {
        v[v.len() / 2]
    }
}

/// SplitMix64 → a uniform in [0, 1) → a Box-Muller normal. Deterministic,
/// so the synthesised head is the same on every run.
struct Rng(u64);

impl Rng {
    fn next_u64(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }
    fn uniform(&mut self) -> f64 {
        (self.next_u64() >> 11) as f64 / (1u64 << 53) as f64
    }
    fn normal(&mut self) -> f64 {
        let u1 = self.uniform().max(1e-12);
        let u2 = self.uniform();
        (-2.0 * u1.ln()).sqrt() * (2.0 * std::f64::consts::PI * u2).cos()
    }
    fn normals(&mut self, n: usize, scale: f64) -> Vec<f32> {
        (0..n).map(|_| (self.normal() * scale) as f32).collect()
    }
}

/// Prompts from the head's TRAINING distribution (the package's nursery
/// corpus). A head trained on the corpus only predicts the trunk well on
/// corpus-like text: on an out-of-distribution prompt the same head's
/// acceptance collapses to ~0, which measures the prompt, not the lane. The
/// bench therefore defaults to the corpus and says which source it used.
fn corpus_prompts(n: usize, bpe: &mlx_native::bpe::ByteLevelBpe) -> Option<Vec<Vec<i32>>> {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../bench/nursery/data/dart_corpus.jsonl");
    let raw = std::fs::read_to_string(path).ok()?;
    let mut out: Vec<Vec<i32>> = Vec::new();
    for line in raw.lines() {
        let Ok(v) = serde_json::from_str::<serde_json::Value>(line) else {
            continue;
        };
        let Some(text) = v["text"].as_str() else {
            continue;
        };
        if text.chars().count() < 200 {
            continue;
        }
        let Ok(ids) = bpe.encode(text) else { continue };
        if ids.len() < 64 {
            continue;
        }
        let ids: Vec<i32> = ids.into_iter().map(|u| u as i32).collect();
        out.push(ids[..ids.len().min(128)].to_vec());
        if out.len() >= n {
            break;
        }
    }
    if out.is_empty() {
        None
    } else {
        Some(out)
    }
}

/// A deterministic UNTRAINED head with the reference's shapes and init
/// scale. It is a FALLBACK: without a trained head the acceptance number is
/// not a measurement of the head's quality, and the bench says so loudly.
fn synthetic_head(hidden: usize, mlp: usize, scale: f32, s: Stream) -> MlxResult<MtpHead> {
    let mut rng = Rng(0x4D54_5000_0000_0001);
    let proj = Array::from_data_f32(
        &rng.normals(hidden * 2 * hidden, 1.0 / (2.0 * hidden as f64).sqrt()),
        &[hidden, 2 * hidden],
    )?;
    let norm = Array::from_data_f32(&vec![1.0f32; hidden], &[hidden])?;
    let gate = Array::from_data_f32(
        &rng.normals(mlp * hidden, 1.0 / (hidden as f64).sqrt()),
        &[mlp, hidden],
    )?;
    let up = Array::from_data_f32(
        &rng.normals(mlp * hidden, 1.0 / (hidden as f64).sqrt()),
        &[mlp, hidden],
    )?;
    let down = Array::from_data_f32(
        &rng.normals(hidden * mlp, 1.0 / (mlp as f64).sqrt()),
        &[hidden, mlp],
    )?;
    let head = MtpHead {
        proj,
        norm,
        gate,
        up,
        down,
        scale,
        depth: 0,
        digest: "synthetic-untrained".to_string(),
    };
    for a in [&head.proj, &head.norm, &head.gate, &head.up, &head.down] {
        a.astype(Dtype::Float32, s)?;
    }
    Ok(head)
}

/// Operation-identical replica of the plain greedy decode loop (the same
/// chunked prefill, the same forward_step + argmax + f32 readback) with the
/// clock started after the prefill — the same clock placement as the MTP
/// lane's decode clock, so the two legs are measured the same way.
fn plain_decode(
    target: &Qwen3,
    prompt: &[i32],
    steps: usize,
    s: Stream,
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

struct Cell {
    name: String,
    k: usize, // 0 = the plain greedy baseline
}

struct Run {
    rep: usize,
    warmup: bool,
    prompt: usize,
    cell: usize,
    decode: f64,
    stats: Option<MtpStats>,
    power: String,
    exact: bool,
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut steps: usize = 64;
    let mut k_list: Vec<usize> = vec![1, 2, 3];
    let mut n_prompts: usize = 3;
    let mut head_arg: Option<PathBuf> = None;
    let mut prompt_source: Option<String> = None;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "-h" | "--help" => {
                println!("{}", usage());
                return;
            }
            "--steps" => {
                i += 1;
                steps = args.get(i).and_then(|v| v.parse().ok()).unwrap_or(steps);
            }
            "--k" => {
                i += 1;
                k_list = args
                    .get(i)
                    .map(|v| {
                        v.split(',')
                            .filter_map(|p| p.parse().ok())
                            .filter(|k: &usize| *k > 0)
                            .collect()
                    })
                    .unwrap_or(k_list);
            }
            "--prompts" => {
                i += 1;
                n_prompts = args
                    .get(i)
                    .and_then(|v| v.parse().ok())
                    .unwrap_or(n_prompts);
            }
            "--head" => {
                i += 1;
                head_arg = args.get(i).map(PathBuf::from);
            }
            "--prompt-source" => {
                i += 1;
                prompt_source = args.get(i).cloned();
            }
            other => {
                eprintln!("unknown argument: {other}\n\n{}", usage());
                std::process::exit(2);
            }
        }
        i += 1;
    }
    if k_list.is_empty() {
        eprintln!("--k must contain at least one count > 0");
        std::process::exit(2);
    }
    n_prompts = n_prompts.clamp(1, 3);

    let warmups: usize = std::env::var("LAYA_MTP_WARMUP")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(2);
    let reps: usize = std::env::var("LAYA_MTP_REPS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(3);
    let scale: f32 = std::env::var("MTP_HEAD_SCALE")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(1.0);

    let power0 = power_now();
    let battery0 = battery_now();
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

    let metallib =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        let _ = mlx::set_metallib_path(&metallib);
    }
    let s = mlx::gpu().expect("Metal device");

    let trunk_dir = snapshot("Qwen3-0.6B-4bit")
        .or_else(|| snapshot("Qwen3-0.6B"))
        .expect("trunk snapshot (Qwen3-0.6B-4bit) absent");
    let t0 = Instant::now();
    let trunk = Qwen3::load(&trunk_dir).expect("trunk loads");
    let embed = TiedEmbedding::load(&trunk_dir, s).expect("the tied embedding loads");
    println!(
        "trunk: {} ({}L h{} kv{} dh{}, V{}) | loaded in {:.1}s",
        trunk_dir.file_name().unwrap().to_string_lossy(),
        trunk.cfg.layers,
        trunk.cfg.hidden_size,
        trunk.cfg.kv_heads,
        trunk.cfg.head_dim,
        trunk.cfg.vocab,
        t0.elapsed().as_secs_f64()
    );

    // ---- the head ----
    let head_path = head_arg.or_else(|| {
        std::env::var_os("MTP_HEAD")
            .map(PathBuf::from)
            .filter(|p| p.is_file())
    });
    let head_source = match &head_path {
        Some(p) => format!("trained head: {}", p.display()),
        None => "SYNTHETIC UNTRAINED head (no MTP_HEAD given) — the acceptance \
                number below is NOT a measurement of a head's quality; it is the \
                floor of the lane"
            .to_string(),
    };
    println!("head: {head_source}");
    let chain: MtpChain = match &head_path {
        Some(p) => MtpChain::load(p, scale, s).expect("the head chain loads"),
        None => {
            let h = trunk.cfg.hidden_size;
            MtpChain {
                heads: vec![synthetic_head(h, 2 * h, scale, s).expect("synthetic head")],
                digest: "synthetic-untrained".to_string(),
                scale,
            }
        }
    };
    let max_k = chain.len();
    let k_list: Vec<usize> = k_list.into_iter().filter(|k| *k <= max_k).collect();
    if k_list.is_empty() {
        eprintln!("the head chain has {max_k} head(s); no requested count fits");
        std::process::exit(2);
    }
    if k_list.len() < 1 {
        eprintln!("no MTP count to measure");
        std::process::exit(2);
    }

    let bpe = mlx_native::bpe::ByteLevelBpe::load(&trunk_dir)
        .or_else(|_| mlx_native::bpe::ByteLevelBpe::load_tokenizer_json(&trunk_dir))
        .expect("tokenizer loads from the trunk snapshot");

    let prompt_texts: [&str; 3] = [
        "Write a friendly two-sentence thank-you note to a friend who lent you their favorite book.",
        "Write a Rust function `fn median(mut v: Vec<f64>) -> f64` that returns the median of a \
         vector, handling even lengths by averaging the two middle values, then explain the steps \
         in two sentences.",
        "The tide leaves a thin silver film on the black basalt as it withdraws, and for a few \
         seconds the whole shelf of rock shines like the inside of a shell. Continue this text \
         in the same voice:",
    ];
    // The prompt source decides what the ACCEPTANCE number means: a head
    // trained on the nursery corpus only predicts the trunk on corpus-like
    // text (on an out-of-distribution prompt the same head's acceptance
    // collapses to ~0, which measures the prompt, not the lane). The corpus
    // is therefore the default when it is present, and the run says which
    // source it used.
    let use_corpus = match prompt_source.as_deref().unwrap_or("auto") {
        "corpus" => true,
        "builtin" => false,
        _ => corpus_prompts(n_prompts, &bpe).is_some(),
    };
    let prompts: Vec<Vec<i32>> = if use_corpus {
        let p = corpus_prompts(n_prompts, &bpe).expect("the corpus prompts resolve");
        println!(
            "prompt source: the nursery corpus (the head's training distribution) — \
             an out-of-distribution prompt measures the prompt, not the lane"
        );
        p
    } else {
        println!(
            "prompt source: the built-in prompts (NOT the head's training \
             distribution — the acceptance number is NOT the head's quality)"
        );
        prompt_texts
            .iter()
            .take(n_prompts)
            .map(|t| {
                bpe.encode(t)
                    .expect("encode")
                    .into_iter()
                    .map(|u| u as i32)
                    .collect()
            })
            .collect()
    };
    for (i, ids) in prompts.iter().enumerate() {
        println!("prompt {i}: {} tokens", ids.len());
    }

    let mut cells: Vec<Cell> = vec![Cell {
        name: "base".to_string(),
        k: 0,
    }];
    cells.extend(k_list.iter().map(|k| Cell {
        name: format!("mtp{k}"),
        k: *k,
    }));

    // The per-prompt greedy REFERENCE (untimed): every measured run must
    // reproduce this suffix token-for-token.
    let mut reference: Vec<Vec<i32>> = Vec::with_capacity(prompts.len());
    for (i, p) in prompts.iter().enumerate() {
        let out = trunk
            .generate_greedy(p, steps, None, s)
            .expect("reference greedy");
        reference.push(out[p.len()..].to_vec());
        println!("reference prompt {i}: {} tokens", steps);
    }

    let mut runs: Vec<Run> = Vec::new();
    let mut diverged_measured = 0usize;
    let mut battery_seen = battery0;

    for rep in 0..(warmups + reps) {
        let warmup = rep < warmups;
        for pi in 0..prompts.len() {
            for ci in 0..cells.len() {
                let rotated = (ci + rep) % cells.len();
                let cell = &cells[rotated];
                let power = power_now();
                battery_seen |= battery_now();
                let t = Instant::now();
                let (suffix, decode, stats) = if cell.k == 0 {
                    let (out, dt) =
                        plain_decode(&trunk, &prompts[pi], steps, s).expect("plain decode");
                    (out, dt.as_secs_f64(), None)
                } else {
                    let sub = chain.sub(cell.k, s).expect("the sub-chain");
                    let (out, st) =
                        generate_greedy_mtp(&trunk, &embed, &sub, &prompts[pi], steps, s)
                            .expect("mtp greedy");
                    (
                        out[prompts[pi].len()..].to_vec(),
                        st.decode.as_secs_f64(),
                        Some(st),
                    )
                };
                let wall = t.elapsed().as_secs_f64();
                let exact = suffix == reference[pi];
                if !exact {
                    if warmup {
                        eprintln!(
                            "WARMUP divergence prompt {pi} cell {} — reported, not fatal",
                            cell.name
                        );
                    } else {
                        diverged_measured += 1;
                        eprintln!(
                            "DIVERGENCE prompt {pi} cell {} vs plain greedy reference",
                            cell.name
                        );
                    }
                }
                println!(
                    "{:>4} {} prompt {pi} cell {:>5}: wall {:7.3}s decode {:7.3}s {:6.1} tok/s{:} [{}]",
                    if warmup { "warm" } else { "meas" },
                    if exact { "ok " } else { "BAD" },
                    cell.name,
                    wall,
                    decode,
                    steps as f64 / decode.max(1e-9),
                    stats
                        .as_ref()
                        .map(|st| format!(
                            " acc {}/{} ({:.0}%) rounds {} | head_mlp {:.1}ms head_lm {:.1}ms verify {:.1}ms resync {:.1}ms",
                            st.accepted,
                            st.drafted,
                            100.0 * st.accepted as f64 / st.drafted.max(1) as f64,
                            st.rounds,
                            st.head_mlp_us as f64 / 1000.0,
                            st.head_lm_us as f64 / 1000.0,
                            st.verify_us as f64 / 1000.0,
                            st.resync_us as f64 / 1000.0,
                        ))
                        .unwrap_or_default(),
                    power,
                );
                runs.push(Run {
                    rep,
                    warmup,
                    prompt: pi,
                    cell: rotated,
                    decode,
                    stats: stats.clone(),
                    power,
                    exact,
                });
            }
        }
    }

    let power_end = power_now();
    battery_seen |= battery_now();

    if reps == 0 {
        println!("\nno measured runs (LAYA_MTP_REPS=0) — smoke mode, no speed data");
        if diverged_measured > 0 {
            std::process::exit(1);
        }
        return;
    }

    println!("\n=== SUMMARY (medians of {reps} measured runs; decode-only clock; interleaved same-process) ===");
    let mut summary = serde_json::Map::new();
    let mut ratios: Vec<f64> = Vec::new();
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
            let d = median(&mut ds);
            let (acc, drafted, rounds, head_mlp, head_lm, verify, resync) = runs
                .iter()
                .filter(|r| !r.warmup && r.prompt == pi && r.cell == ci)
                .fold(
                    (0usize, 0usize, 0usize, 0u64, 0u64, 0u64, 0u64),
                    |(a, dr, ro, ml, lm, vf, rs), r| {
                        let st = r.stats.as_ref();
                        (
                            a + st.map(|s| s.accepted).unwrap_or(0),
                            dr + st.map(|s| s.drafted).unwrap_or(0),
                            ro + st.map(|s| s.rounds).unwrap_or(0),
                            ml + st.map(|s| s.head_mlp_us).unwrap_or(0),
                            lm + st.map(|s| s.head_lm_us).unwrap_or(0),
                            vf + st.map(|s| s.verify_us).unwrap_or(0),
                            rs + st.map(|s| s.resync_us).unwrap_or(0),
                        )
                    },
                );
            // The per-depth acceptance (the reference's accept_self[j] and the
            // J-G1 metric): the fraction of rounds whose accepted prefix
            // reached depth j+1.
            let mut depth_acc: Vec<f64> = vec![0.0; cell.k];
            {
                let mut hist = vec![0usize; cell.k];
                let mut rounds_total = 0usize;
                for r in runs
                    .iter()
                    .filter(|r| !r.warmup && r.prompt == pi && r.cell == ci)
                {
                    if let Some(st) = r.stats.as_ref() {
                        rounds_total += st.rounds;
                        for (j, c) in st.prefix_hist.iter().enumerate() {
                            if j < hist.len() {
                                hist[j] += *c;
                            }
                        }
                    }
                }
                for j in 0..cell.k {
                    depth_acc[j] = if rounds_total > 0 {
                        hist[j] as f64 / rounds_total as f64
                    } else {
                        0.0
                    };
                }
            }
            let mult = base_decode / d.max(1e-9);
            if cell.k > 0 {
                ratios.push(mult);
            }
            let n = runs
                .iter()
                .filter(|r| !r.warmup && r.prompt == pi && r.cell == ci)
                .count()
                .max(1) as f64;
            println!(
                "prompt {pi} cell {:>5}: decode {:6.1} tok/s  x{mult:.2} vs base | accept by depth {:?} rounds {rounds} | prefix {acc}/{drafted} | per-run: head_mlp {:.1}ms head_lm {:.1}ms verify {:.1}ms resync {:.1}ms",
                cell.name,
                steps as f64 / d.max(1e-9),
                depth_acc
                    .iter()
                    .map(|p| format!("{:.0}%", 100.0 * p))
                    .collect::<Vec<_>>(),
                head_mlp as f64 / 1000.0 / n,
                head_lm as f64 / 1000.0 / n,
                verify as f64 / 1000.0 / n,
                resync as f64 / 1000.0 / n,
            );
            summary.insert(
                format!("p{pi}_{}", cell.name),
                serde_json::json!({
                    "decode_tok_s": steps as f64 / d.max(1e-9),
                    "x_vs_base": mult,
                    "accepted": acc,
                    "drafted": drafted,
                    "rounds": rounds,
                    "head_mlp_ms": head_mlp as f64 / 1000.0 / n,
                    "head_lm_ms": head_lm as f64 / 1000.0 / n,
                    "verify_ms": verify as f64 / 1000.0 / n,
                    "resync_ms": resync as f64 / 1000.0 / n,
                }),
            );
        }
    }

    let mean_ratio = if ratios.is_empty() {
        0.0
    } else {
        ratios.iter().sum::<f64>() / ratios.len() as f64
    };
    println!("\n=== MTP vs plain greedy (mean over the measured cells) ===");
    println!("speedup ratio: x{mean_ratio:.2}  (J-G2 threshold: 1.50x — the gate is NOT claimed by this bench, it is reported)");
    println!(
        "token-exactness: {} measured divergences (must be 0 — greedy verification is exact)",
        diverged_measured
    );

    // ---- the cost model: what acceptance the lane would NEED -------------
    //
    // The lane's cycle cost is MEASURED (the trunk's verify forward, the
    // head's own vocab projection per head, and the resync forward's
    // frequency). The acceptance p is the only free variable, so the lane's
    // break-even acceptance for the J-G2 threshold is a NUMBER, not a
    // verdict: below it the lane cannot pay on this hardware, whatever the
    // head's quality.
    //
    //   tokens per round = E[max(A, 1)] = sum_{j=1..K} p^j + (1 - p)
    //   cycle cost       = t_verify + K * t_head_lm + (1 - p) * t_resync
    //   speedup(p)       = tokens(p) * t_ar / cycle(p)
    println!(
        "\n=== the cost model (measured components; the acceptance is the only free variable) ==="
    );
    let mut cost_rows = Vec::new();
    for (ci, cell) in cells.iter().enumerate() {
        if cell.k == 0 {
            continue;
        }
        let mut base_decode = Vec::new();
        for pi in 0..prompts.len() {
            let mut v: Vec<f64> = runs
                .iter()
                .filter(|r| !r.warmup && r.prompt == pi && r.cell == 0 && r.exact)
                .map(|r| r.decode)
                .collect();
            base_decode.push(median(&mut v));
        }
        let t_ar =
            base_decode.iter().sum::<f64>() / base_decode.len().max(1) as f64 / steps.max(1) as f64;
        let mut cycle = Vec::new();
        let mut head_lm = Vec::new();
        let mut head_mlp = Vec::new();
        let mut verify = Vec::new();
        let mut resync = Vec::new();
        for pi in 0..prompts.len() {
            let sel: Vec<&Run> = runs
                .iter()
                .filter(|r| !r.warmup && r.prompt == pi && r.cell == ci)
                .collect();
            if sel.is_empty() {
                continue;
            }
            let rounds: f64 = sel
                .iter()
                .filter_map(|r| r.stats.as_ref().map(|s| s.rounds as f64))
                .sum();
            if rounds <= 0.0 {
                continue;
            }
            let d: f64 = sel.iter().map(|r| r.decode).sum();
            cycle.push(d / rounds);
            // Per-HEAD vocab projection time (the K heads of a round share the
            // figure) and the per-occurrence resync time. All the components
            // are kept in SECONDS here (the stats are microseconds), so the
            // model below is unit-consistent with t_ar.
            let lm_total: f64 = sel
                .iter()
                .filter_map(|r| r.stats.as_ref().map(|s| s.head_lm_us as f64))
                .sum();
            head_lm.push(lm_total / rounds / cell.k as f64 / 1e6);
            let ml_total: f64 = sel
                .iter()
                .filter_map(|r| r.stats.as_ref().map(|s| s.head_mlp_us as f64))
                .sum();
            head_mlp.push(ml_total / rounds / 1e6);
            let vf_total: f64 = sel
                .iter()
                .filter_map(|r| r.stats.as_ref().map(|s| s.verify_us as f64))
                .sum();
            verify.push(vf_total / rounds / 1e6);
            let rs_total: f64 = sel
                .iter()
                .filter_map(|r| r.stats.as_ref().map(|s| s.resync_us as f64))
                .sum();
            let rs_count: f64 = sel
                .iter()
                .filter_map(|r| r.stats.as_ref().map(|s| s.resyncs as f64))
                .sum();
            resync.push(if rs_count > 0.0 {
                rs_total / rs_count / 1e6
            } else {
                0.0
            });
        }
        if cycle.is_empty() {
            continue;
        }
        let t_cycle = cycle.iter().sum::<f64>() / cycle.len() as f64;
        let t_head_lm = head_lm.iter().sum::<f64>() / head_lm.len().max(1) as f64;
        let t_head_mlp = head_mlp.iter().sum::<f64>() / head_mlp.len().max(1) as f64;
        let t_verify = verify.iter().sum::<f64>() / verify.len().max(1) as f64;
        let t_resync = resync.iter().sum::<f64>() / resync.len().max(1) as f64;
        let k = cell.k as f64;
        let speedup_at = |p: f64| -> f64 {
            let mut tokens = 1.0 - p;
            let mut pw = p;
            for _ in 0..(cell.k) {
                tokens += pw;
                pw *= p;
            }
            let cost = t_verify + k * t_head_lm + k * t_head_mlp + (1.0 - p) * t_resync;
            tokens * t_ar / cost.max(1e-9)
        };
        // The break-even acceptance for 1.5x: the smallest p in [0, 1] whose
        // modelled speedup clears the threshold (the model is monotone in p).
        let mut best_p: Option<f64> = None;
        let mut p = 0.0;
        while p <= 1.0001 {
            if speedup_at(p) >= 1.5 {
                best_p = Some(p);
                break;
            }
            p += 0.001;
        }
        println!(
            "cell {:>5}: t_ar {:.2} ms/token | t_cycle {:.2} ms/round (verify {:.2} + {}x head_lm {:.2} + {}x head_mlp {:.2} + resync {:.2} per occurrence) | speedup at p=1.0: x{:.2} | break-even acceptance for 1.5x: {}",
            cell.name,
            t_ar * 1000.0,
            t_cycle * 1000.0,
            t_verify * 1000.0,
            cell.k,
            t_head_lm * 1000.0,
            cell.k,
            t_head_mlp * 1000.0,
            t_resync * 1000.0,
            speedup_at(1.0),
            match best_p {
                Some(v) => format!("p >= {v:.3}"),
                None => "NOT REACHABLE (even p=1.0 does not clear 1.5x)".to_string(),
            },
        );
        cost_rows.push(serde_json::json!({
            "cell": cell.name,
            "t_ar_ms": t_ar * 1000.0,
            "t_cycle_ms": t_cycle * 1000.0,
            "t_verify_ms": t_verify * 1000.0,
            "t_head_lm_ms": t_head_lm * 1000.0,
            "t_head_mlp_ms": t_head_mlp * 1000.0,
            "t_resync_ms": t_resync * 1000.0,
            "speedup_at_p1": speedup_at(1.0),
            "break_even_acceptance_for_1_5x": best_p,
        }));
    }
    println!(
        "token-exactness: {} measured divergences (must be 0 — greedy verification is exact)",
        diverged_measured
    );

    let mut powers: Vec<String> = runs.iter().map(|r| r.power.clone()).collect();
    powers.sort();
    powers.dedup();
    if battery_seen {
        println!("POWER-CONTAMINATED — non-baseline (ADR 0061): battery was the source at some point in this run");
    }
    println!("power states seen during runs: {powers:?}");
    println!("power at end: {power_end}");

    println!(
        "##MTP_JSON## {}",
        serde_json::json!({
            "machine": machine,
            "power_start": power0,
            "power_end": power_end,
            "power_states_seen": powers,
            "battery_seen": battery_seen,
            "steps": steps,
            "warmups": warmups,
            "reps": reps,
            "head_source": head_source,
            "head_scale": scale,
            "diverged_measured": diverged_measured,
            "speedup_ratio_mean": mean_ratio,
            "summary": summary,
            "cost_model": cost_rows,
            "runs": runs.iter().map(|r| serde_json::json!({
                "rep": r.rep, "warmup": r.warmup, "prompt": r.prompt, "cell": cells[r.cell].name,
                "decode_s": r.decode, "power": r.power, "exact": r.exact,
                "accepted": r.stats.as_ref().map(|s| s.accepted), "drafted": r.stats.as_ref().map(|s| s.drafted),
                "rounds": r.stats.as_ref().map(|s| s.rounds),
                "head_mlp_us": r.stats.as_ref().map(|s| s.head_mlp_us),
                "head_lm_us": r.stats.as_ref().map(|s| s.head_lm_us),
                "verify_us": r.stats.as_ref().map(|s| s.verify_us),
                "resync_us": r.stats.as_ref().map(|s| s.resync_us),
            })).collect::<Vec<_>>(),
        })
    );

    if diverged_measured > 0 {
        std::process::exit(1);
    }
}
