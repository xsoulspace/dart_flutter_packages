//! L-G4 bench — the batched-decode lever.
//!
//! WHAT THIS BENCH MEASURES, AND WHAT IT DOES NOT.
//!
//! L-G4 asks: can this device decode more tokens per second by running N
//! sequences at once? The gate's threshold is the aggregate ratio
//! `tok/s(8) / tok/s(1)` on the same prompt set: `>= 1.5` ⇒ batching IS a
//! lever; `< 1.5` ⇒ it is NOT, and the acceleration program rests on
//! train-once/reuse instead.
//!
//! **The honest problem: a FUSED batched forward does not exist in this
//! crate yet.** `qwen.rs` builds every forward with the batch dim hardcoded
//! to `1`, so the trunk cannot be asked for a `[B, L]` forward without
//! editing `qwen.rs` (which this unit may not do). What this bench
//! therefore measures is FOUR things, and it labels each one:
//!
//!   1. **THE CONTROL (the lockstep batch).** [`generate_greedy_batched`]
//!      advances N sequences in lockstep, each with its own KV cache, one
//!      `forward_step` per sequence per step. This is the "N sequences at
//!      once" reading that needs no new kernel — and it does NOT amortize
//!      the weight read (one weight read per sequence per token). Its
//!      aggregate tok/s ratio IS measured and printed, and it is labelled
//!      **NOT A GATE INPUT**: it is the number a reader would quote if the
//!      batch were a no-op, and quoting it as the gate verdict would
//!      measure the control, not the lever.
//!   2. **THE ARITHMETIC OF THE LEVER** — the amortization probe: the
//!      cost of the REAL tied vocabulary projection and of a REAL body
//!      layer's quantized GEMM stack at `[B, L, H]`, forced-evaluated
//!      through the trunk's own plan ops and binding table. The derived
//!      factor `B * cost(1) / cost(B)` says what a FUSED batch would buy:
//!      it is the whole question, measured on the real weights, without
//!      pretending the fused forward exists.
//!   3. **THE PRECONDITION** — whether a batched matmul changes the
//!      NUMBERS (bit for bit) relative to the same row computed alone. If
//!      it does, a fused batch would not reproduce a sequential decode and
//!      no number measured through it is a measurement at all.
//!   4. **THE INVARIANCE** — whether the batched decode is
//!      batch-invariant at the DECODE level: the same prompts decoded
//!      sequentially and in the batch, compared token for token.
//!
//! THE MEASUREMENT IS REAL. MLX is lazy: every timed region forces the
//! ACTUAL output it is timing (`Array::eval()` + a stream sync), never an
//! unrelated dummy array. The lane has a measured 28.7x error from exactly
//! that mistake.
//!
//! THE RATIO IS THE MEASUREMENT. Absolute ms and tok/s on this box are
//! non-claims (the same prebuilt binary took 53 s on a quiet box and 4 m
//! 47 s on a loaded one). Every number below is printed beside the power
//! state and the REAL charge current (ioreg `Amperage`, not the `pmset`
//! source flag), and the concurrency levels are INTERLEAVED so thermal
//! drift cancels instead of biasing the ratio.
//!
//! Usage:
//!   cargo run --release --bin qwen_batch_bench \
//!     [--prompts N | --prompts-file PATH] [--concurrency 1,2,4,8,16] \
//!     [--max-tokens N] [--reps N] [--model-fragment Qwen3-0.6B-4bit] \
//!     [--out PATH]
//!
//! Env:
//!   LAYA_QWEN_BATCH_SNAPSHOT_DIR  pin ONE snapshot dir
//!   QWEN3_TARGET_SNAPSHOT         pin the snapshot dir explicitly
//!   LAYA_QWEN_BATCH_WARMUP        warmup repetitions (default 1)
//!   LAYA_QWEN_BATCH_REPS          measured repetitions (default 3)

use std::path::{Path, PathBuf};
use std::time::Instant;

use mlx_native::mlx::{self, Stream};
use mlx_native::power::{facts, PowerSource};
use mlx_native::qwen::Qwen3;
use mlx_native::qwen_batch::{
    self, AmortizationReport, BatchRequest, FUSED_BATCH_FORWARD_AVAILABLE, FUSED_BATCH_FORWARD_NOTE,
};
use serde_json::{json, Value};

/// A JSON-safe number: NaN and infinity are NOT valid JSON, and a bench
/// that panics on a missing measurement is worse than one that reports
/// `null` for it.
fn jnum(v: f64) -> Value {
    if v.is_finite() {
        json!(v)
    } else {
        Value::Null
    }
}

/// The cached HF-hub snapshot dir for a model-name fragment.
fn snapshot(fragment: &str) -> Option<PathBuf> {
    if let Some(dir) = std::env::var_os("LAYA_QWEN_BATCH_SNAPSHOT_DIR") {
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
                let p = s.path();
                if p.is_dir() && p.join("config.json").is_file() {
                    return Some(p);
                }
            }
        }
    }
    None
}

/// The REAL charge current in mA (strongly positive = actually charging).
/// `pmset`'s "AC Power" is the SOURCE, not the current (POWER.md's
/// charge-current hole) — so the gate input is this number.
fn charge_current_ma() -> i64 {
    let Ok(out) = std::process::Command::new("ioreg")
        .args(["-rc", "AppleSmartBattery"])
        .output()
    else {
        return 0;
    };
    let text = String::from_utf8_lossy(&out.stdout).to_string();
    for line in text.lines() {
        let t = line.trim();
        if let Some(rest) = t.strip_prefix("\"Amperage\" = ") {
            return rest.trim().parse::<i64>().unwrap_or(0);
        }
    }
    0
}

/// The power state plus the real charge current — printed beside every
/// number, because a perf number without a power state is a non-claim.
fn power_now() -> String {
    let f = facts();
    let mut s = f.describe();
    s.push_str(&format!(" charge {} mA", charge_current_ma()));
    s
}

fn on_battery() -> bool {
    facts().source == PowerSource::Battery
}

fn median(v: &mut [f64]) -> f64 {
    v.sort_by(|a, b| a.partial_cmp(b).unwrap());
    if v.is_empty() {
        f64::NAN
    } else {
        v[v.len() / 2]
    }
}

fn usage() -> String {
    "qwen_batch_bench — L-G4: the batched-decode lever\n\n\
     Usage: qwen_batch_bench [--prompts N | --prompts-file PATH] \
     [--concurrency 1,2,4,8,16]\n\
     \x20   [--max-tokens N] [--reps N] [--model-fragment Qwen3-0.6B-4bit] [--out PATH]\n\n\
     Options:\n\
     \x20 --prompts N       how many prompts to decode (default 8)\n\
     \x20 --prompts-file P  one prompt per line; overrides --prompts\n\
     \x20 --concurrency L   comma-separated concurrency levels (default 1,2,4,8,16)\n\
     \x20 --max-tokens N    generated tokens per prompt (default 16)\n\
     \x20 --reps N          measured repetitions per level (default 3)\n\
     \x20 --model-fragment F  HF snapshot dir fragment (default Qwen3-0.6B-4bit)\n\
     \x20 --out PATH        write the JSON summary to PATH as well\n\
     -h, --help           this text\n\n\
     Env: LAYA_QWEN_BATCH_SNAPSHOT_DIR, QWEN3_TARGET_SNAPSHOT,\n\
     \x20    LAYA_QWEN_BATCH_WARMUP, LAYA_QWEN_BATCH_REPS"
        .to_string()
}

/// The prompts: the built-in set, or a file (one prompt per line).
fn builtin_prompts() -> Vec<String> {
    vec![
        "Write a friendly two-sentence thank-you note to a friend who lent you their favorite book.".to_string(),
        "Write a Rust function `fn median(mut v: Vec<f64>) -> f64` that returns the median of a \
         vector, handling even lengths by averaging the two middle values, then explain the steps \
         in two sentences.".to_string(),
        "The tide leaves a thin silver film on the black basalt as it withdraws, and for a few \
         seconds the whole shelf of rock shines like the inside of a shell. Continue this text \
         in the same voice:".to_string(),
        "Summarize in one sentence why a prefix cache is safe only under the weights that produced \
         it.".to_string(),
        "A bus arrives every eleven minutes. A person arrives at the stop at a uniformly random \
         time and waits exactly eleven minutes for the next bus. What is the expected wait, and \
         why is it not five and a half minutes?".to_string(),
        "Explain the difference between a mutex and an atomic counter to someone who knows only \
         C, in three sentences.".to_string(),
        "The cat sat on the mat. Rewrite that sentence as a haiku about patience.".to_string(),
        "List three ways a mobile app can keep working when the network drops, and say which one \
         is easiest to get wrong.".to_string(),
    ]
}

fn read_prompt_file(path: &Path) -> Vec<String> {
    std::fs::read_to_string(path)
        .unwrap_or_default()
        .lines()
        .map(|l| l.trim().to_string())
        .filter(|l| !l.is_empty())
        .collect()
}

/// One measured concurrency level.
#[derive(Clone, Debug)]
struct LevelRun {
    rep: usize,
    /// Aggregate tokens per second over the WHOLE prompt set.
    aggregate_tok_s: f64,
    /// Per-sequence tokens per second: how fast ONE sequence advances
    /// while the level's sequences are in flight (the group's tokens over
    /// the group's wall).
    per_sequence_tok_s: f64,
    /// How many sequences were actually in flight (the prompt count caps
    /// the requested level).
    effective_concurrency: usize,
    /// Total generated tokens (the numerator).
    tokens: usize,
    /// Total decode wall (the denominator).
    decode_s: f64,
    /// The prefill wall, reported but NOT in the throughput number.
    prefill_s: f64,
    power: String,
}

/// Decode the whole prompt set at one concurrency level, timed on the
/// DECODE clock only (the prefill clock is reported separately, exactly as
/// the lane's other benches place it).
///
/// The prompt set is cut into groups of `concurrency`; each group is
/// decoded in lockstep and the groups run one after another (one GPU, one
/// stream). The aggregate number is the whole set's tokens over the whole
/// set's wall; the per-sequence number is one group's tokens over that
/// group's wall — how fast a single sequence advances while its
/// neighbours are in flight.
fn run_level(
    model: &Qwen3,
    reqs: &[BatchRequest],
    concurrency: usize,
    s: Stream,
) -> mlx_native::mlx::MlxResult<LevelRun> {
    let mut tokens = 0usize;
    let mut decode_s = 0.0f64;
    let mut prefill_s = 0.0f64;
    let mut group_tok_s: Vec<f64> = Vec::new();
    let mut effective = 0usize;
    for group in reqs.chunks(concurrency.max(1)) {
        let (outcome, timing) = qwen_batch::generate_greedy_batched_timed(model, group, None, s)?;
        let group_tokens: usize = outcome.completions.iter().map(|c| c.len()).sum();
        tokens += group_tokens;
        decode_s += timing.decode_s;
        prefill_s += timing.prefill_s;
        effective = effective.max(group.len());
        if timing.decode_s > 0.0 {
            group_tok_s.push(group_tokens as f64 / timing.decode_s);
        }
    }
    let aggregate_tok_s = if decode_s > 0.0 {
        tokens as f64 / decode_s
    } else {
        f64::NAN
    };
    let per_sequence_tok_s = median(&mut group_tok_s);
    Ok(LevelRun {
        rep: 0,
        aggregate_tok_s,
        per_sequence_tok_s,
        effective_concurrency: effective,
        tokens,
        decode_s,
        prefill_s,
        power: power_now(),
    })
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut n_prompts: usize = 8;
    let mut prompts_file: Option<PathBuf> = None;
    let mut levels: Vec<usize> = vec![1, 2, 4, 8, 16];
    let mut max_tokens: usize = 16;
    let mut reps: usize = 3;
    let mut fragment: String = "Qwen3-0.6B-4bit".to_string();
    let mut out_path: Option<PathBuf> = None;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "-h" | "--help" => {
                println!("{}", usage());
                return;
            }
            "--prompts" => {
                i += 1;
                n_prompts = args
                    .get(i)
                    .and_then(|v| v.parse().ok())
                    .unwrap_or(n_prompts);
            }
            "--prompts-file" => {
                i += 1;
                prompts_file = args.get(i).map(PathBuf::from);
            }
            "--concurrency" => {
                i += 1;
                levels = args
                    .get(i)
                    .map(|v| {
                        v.split(',')
                            .filter_map(|c| c.trim().parse::<usize>().ok())
                            .filter(|c| *c > 0)
                            .collect()
                    })
                    .filter(|v: &Vec<usize>| !v.is_empty())
                    .unwrap_or(levels);
            }
            "--max-tokens" => {
                i += 1;
                max_tokens = args
                    .get(i)
                    .and_then(|v| v.parse().ok())
                    .unwrap_or(max_tokens);
            }
            "--reps" => {
                i += 1;
                reps = args.get(i).and_then(|v| v.parse().ok()).unwrap_or(reps);
            }
            "--model-fragment" => {
                i += 1;
                fragment = args.get(i).cloned().unwrap_or(fragment);
            }
            "--out" => {
                i += 1;
                out_path = args.get(i).map(PathBuf::from);
            }
            other => {
                eprintln!("unknown argument: {other}\n\n{}", usage());
                std::process::exit(2);
            }
        }
        i += 1;
    }
    if levels.is_empty() {
        eprintln!("--concurrency must contain at least one level > 0");
        std::process::exit(2);
    }
    levels.sort_unstable();
    levels.dedup();
    let max_level = *levels.last().unwrap();

    let warmups: usize = std::env::var("LAYA_QWEN_BATCH_WARMUP")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(1);
    let reps: usize = std::env::var("LAYA_QWEN_BATCH_REPS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(reps);

    let power0 = power_now();
    let machine = std::process::Command::new("sysctl")
        .args(["-n", "machdep.cpu.brand_string"])
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_else(|| "unknown".to_string());
    println!("machine: {machine}");
    println!("power at start: {power0}");
    if on_battery() {
        println!(
            "POWER-CONTAMINATED — non-baseline (ADR 0061): running on battery; the numbers below \
             are NOT baseline and no gate applies"
        );
    }
    if !FUSED_BATCH_FORWARD_AVAILABLE {
        println!(
            "FUSED BATCH FORWARD UNAVAILABLE — the trunk's forward is batch-1 by construction \
             (qwen.rs hardcodes the batch dim to 1). The concurrency sweep below is the LOCKSTEP \
             CONTROL (no weight-read amortization) and is NOT a gate input; the amortization \
             probe is the number that says whether buying the fused forward is worth it."
        );
        println!("minimal qwen.rs change: {FUSED_BATCH_FORWARD_NOTE}");
    }

    let metallib =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        let _ = mlx::set_metallib_path(&metallib);
    }
    let s = mlx::gpu().expect("Metal device");

    let model_dir = snapshot(&fragment).unwrap_or_else(|| {
        eprintln!(
            "no HF snapshot matching fragment {fragment:?} (set LAYA_QWEN_BATCH_SNAPSHOT_DIR)"
        );
        std::process::exit(2);
    });
    let t0 = Instant::now();
    let model = Qwen3::load(&model_dir).expect("trunk loads");
    println!(
        "trunk: {} ({}L h{} kv{} dh{}, V{}) | loaded in {:.1}s",
        model_dir.file_name().unwrap().to_string_lossy(),
        model.cfg.layers,
        model.cfg.hidden_size,
        model.cfg.kv_heads,
        model.cfg.head_dim,
        model.cfg.vocab,
        t0.elapsed().as_secs_f64()
    );

    let bpe = mlx_native::bpe::ByteLevelBpe::load(&model_dir)
        .or_else(|_| mlx_native::bpe::ByteLevelBpe::load_tokenizer_json(&model_dir))
        .expect("tokenizer loads from the trunk snapshot");

    // ---- the prompt set (the SAME set for every level: the gate's
    // "same prompt set" requirement) ----
    let texts: Vec<String> = match prompts_file.as_ref() {
        Some(p) => {
            let t = read_prompt_file(p);
            if t.is_empty() {
                eprintln!("prompts file {} is empty", p.display());
                std::process::exit(2);
            }
            t
        }
        None => {
            let base = builtin_prompts();
            // At least `max_level` prompts, so every requested concurrency
            // level actually has that many sequences in flight (the ratio
            // would otherwise be measured at a lower level than asked for).
            let want = n_prompts.max(1).max(max_level);
            let mut out = Vec::new();
            for i in 0..want {
                out.push(base[i % base.len()].clone());
            }
            out
        }
    };
    let mut reqs: Vec<BatchRequest> = Vec::with_capacity(texts.len());
    for text in &texts {
        let ids = bpe.encode(text).expect("prompt encodes");
        let ids: Vec<i32> = ids.into_iter().map(|u| u as i32).collect();
        if ids.is_empty() {
            eprintln!("a prompt encoded to zero tokens; skipping it");
            continue;
        }
        reqs.push(BatchRequest {
            prompt_ids: ids,
            max_tokens,
        });
    }
    println!(
        "prompts: {} | max_tokens: {max_tokens} | levels: {levels:?} | reps: {reps}",
        reqs.len()
    );
    if reqs.len() < max_level {
        println!(
            "NOTE: the prompt set ({} prompts) is smaller than the largest concurrency level ({}); \
             that level runs at the prompt count.",
            reqs.len(),
            max_level
        );
    }

    // ---- warmup (the first touch of a checkpoint pays page faults) ----
    for _ in 0..warmups {
        let _ = run_level(&model, &reqs, max_level, s);
    }

    // ---- the AR reference BEFORE the sweep: the single-stream baseline ----
    let ar_before = run_level(&model, &reqs, 1, s).expect("the AR reference runs");
    println!(
        "AR reference (before): aggregate {:.2} tok/s | per-seq {:.2} tok/s | {} | power: {}",
        ar_before.aggregate_tok_s, ar_before.per_sequence_tok_s, ar_before.power, ar_before.power
    );

    // ---- the interleaved sweep ----
    //
    // The levels are INTERLEAVED and the order is ROTATED per repetition, so
    // a thermal drift across the sweep cancels in the ratio instead of
    // biasing it (POWER.md / ADR 0061).
    let mut per_level: Vec<Vec<LevelRun>> = vec![Vec::new(); levels.len()];
    for rep in 0..reps {
        // The order of the levels is ROTATED per repetition, so a thermal
        // drift across the sweep cancels in the ratio instead of biasing it
        // (POWER.md / ADR 0061).
        for k in 0..levels.len() {
            let slot = (k + rep) % levels.len();
            let conc = levels[slot];
            let mut run = run_level(&model, &reqs, conc, s).expect("a level runs");
            run.rep = rep;
            let idx = levels.iter().position(|c| *c == conc).unwrap();
            per_level[idx].push(run);
        }
    }

    let mut level_summaries = Vec::new();
    let mut ratios = serde_json::Map::new();
    let mut base_aggregate = f64::NAN;
    for (idx, conc) in levels.iter().enumerate() {
        let runs = &per_level[idx];
        if runs.is_empty() {
            continue;
        }
        let mut aggregates: Vec<f64> = runs.iter().map(|r| r.aggregate_tok_s).collect();
        let mut per_seq: Vec<f64> = runs.iter().map(|r| r.per_sequence_tok_s).collect();
        let aggregate = median(&mut aggregates);
        let per_sequence = median(&mut per_seq);
        if base_aggregate.is_nan() {
            base_aggregate = aggregate;
        }
        let ratio = if base_aggregate > 0.0 {
            aggregate / base_aggregate
        } else {
            f64::NAN
        };
        ratios.insert(conc.to_string(), jnum(ratio));
        println!(
            "concurrency {conc:>2} (effective {}): aggregate {:>8.2} tok/s | per-seq {:>7.2} tok/s | \
             ratio to c1 {:>5.3} | tokens {} | decode {:.3}s | power: {}",
            runs[0].effective_concurrency,
            aggregate,
            per_sequence,
            ratio,
            runs[0].tokens,
            runs[0].decode_s,
            runs[0].power
        );
        let mut decode_medians: Vec<f64> = runs.iter().map(|r| r.decode_s).collect();
        let mut prefill_medians: Vec<f64> = runs.iter().map(|r| r.prefill_s).collect();
        level_summaries.push(json!({
            "concurrency_requested": conc,
            "concurrency_effective": runs[0].effective_concurrency,
            "aggregate_tok_s_median": jnum(aggregate),
            "per_sequence_tok_s_median": jnum(per_sequence),
            "ratio_to_concurrency_1": jnum(ratio),
            "tokens": runs[0].tokens,
            "decode_s_median": jnum(median(&mut decode_medians)),
            "prefill_s_median": jnum(median(&mut prefill_medians)),
            "reps": runs.iter().map(|r| json!({
                "rep": r.rep,
                "aggregate_tok_s": r.aggregate_tok_s,
                "decode_s": r.decode_s,
                "power": r.power,
            })).collect::<Vec<_>>(),
        }));
    }

    // ---- the AR reference AFTER the sweep: the ordering bias, measured ----
    let ar_after = run_level(&model, &reqs, 1, s).expect("the AR reference runs");
    println!(
        "AR reference (after):  aggregate {:.2} tok/s | per-seq {:.2} tok/s | power: {}",
        ar_after.aggregate_tok_s, ar_after.per_sequence_tok_s, ar_after.power
    );
    let ar_drift = if ar_before.aggregate_tok_s > 0.0 {
        ar_after.aggregate_tok_s / ar_before.aggregate_tok_s
    } else {
        f64::NAN
    };
    println!(
        "AR ordering bias (after/before): {ar_drift:.3}  <- a value far from 1.0 means the sweep \
         was thermally contaminated"
    );

    // ---- the precondition: does a BATCHED matmul change the numbers? ----
    println!("\n--- batched-matmul numerics (the fused-batch precondition) ---");
    let numerics = qwen_batch::probe_batch_numerics(&model, &model_dir, max_level, 1, s)
        .expect("the numerics probe runs");
    let numerics_json = json!({
        "rows": max_level,
        "tied_projection": numerics.tied_projection.map(|p| json!({
            "bit_identical": p.bit_identical,
            "first_divergence": p.first_divergence,
            "max_abs_diff": p.max_abs_diff,
            "single_shape_class": p.single_shape_class,
            "batched_shape_class": p.batched_shape_class,
            "same_class_bit_identical": p.same_class_bit_identical,
            "same_class_first_divergence": p.same_class_first_divergence,
        })),
        "body_gemm": numerics.body_gemm.map(|p| json!({
            "bit_identical": p.bit_identical,
            "first_divergence": p.first_divergence,
            "max_abs_diff": p.max_abs_diff,
            "single_shape_class": p.single_shape_class,
            "batched_shape_class": p.batched_shape_class,
            "same_class_bit_identical": p.same_class_bit_identical,
            "same_class_first_divergence": p.same_class_first_divergence,
        })),
    });
    if let Some(p) = numerics.tied_projection {
        println!(
            "tied projection: bit-identical = {} | max |diff| = {:e} | dispatch: {} -> {} | \
             same-class control identical = {:?}",
            p.bit_identical,
            p.max_abs_diff,
            p.single_shape_class,
            p.batched_shape_class,
            p.same_class_bit_identical
        );
    }
    if let Some(p) = numerics.body_gemm {
        println!(
            "body q_proj:    bit-identical = {} | max |diff| = {:e} | dispatch: {} -> {} | \
             same-class control identical = {:?}",
            p.bit_identical,
            p.max_abs_diff,
            p.single_shape_class,
            p.batched_shape_class,
            p.same_class_bit_identical
        );
    }
    let numerics_invariant = numerics
        .tied_projection
        .map(|p| p.bit_identical)
        .unwrap_or(true)
        && numerics.body_gemm.map(|p| p.bit_identical).unwrap_or(true);
    println!(
        "batched-matmul numerics invariant: {numerics_invariant}  <- if false, a FUSED batch would \
         not reproduce a sequential decode and no number measured through it is a measurement"
    );
    println!(
        "NOTE the dispatch line above: a change of shape class (e.g. gemv -> skinny_gemm) is a \
         change of KERNEL, not of the batch dimension. The same-class control isolates the batch \
         dimension itself."
    );

    // ---- the decode-level invariance ----
    println!("\n--- decode-level batch invariance ---");
    let invariance = qwen_batch::check_batch_invariance(&model, &reqs, None, s)
        .expect("the invariance check runs");
    println!(
        "decode-level batch invariant: {} | compared {} tokens | first divergence: {:?} | \
         per-sequence: {:?}",
        invariance.invariant,
        invariance.compared_tokens,
        invariance.first_divergence,
        invariance.per_sequence
    );

    // ---- the arithmetic of the lever: what a FUSED batch would buy ----
    println!("\n--- amortization probe (the real weights, forced eval) ---");
    let amort = qwen_batch::probe_batch_amortization(&model, &model_dir, &levels, 1, reps, s)
        .expect("the amortization probe runs");
    print_amortization(&amort);

    // ---- the JSON summary (machine-readable; stdout) ----
    let summary = json!({
        "bench": "qwen_batch_bench",
        "gate": "L-G4",
        "machine": machine,
        "power_at_start": power0,
        "power_at_end": power_now(),
        "on_battery": on_battery(),
        "model": {
            "dir": model_dir.display().to_string(),
            "weight_identity": model.weight_identity(),
            "layers": model.cfg.layers,
            "hidden_size": model.cfg.hidden_size,
            "vocab": model.cfg.vocab,
        },
        "prompts": reqs.len(),
        "max_tokens": max_tokens,
        "reps": reps,
        "levels": level_summaries,
        "ratios_to_concurrency_1": ratios,
        "ar_reference": {
            "before": {
                "aggregate_tok_s": jnum(ar_before.aggregate_tok_s),
                "per_sequence_tok_s": jnum(ar_before.per_sequence_tok_s),
                "power": ar_before.power,
            },
            "after": {
                "aggregate_tok_s": jnum(ar_after.aggregate_tok_s),
                "per_sequence_tok_s": jnum(ar_after.per_sequence_tok_s),
                "power": ar_after.power,
            },
            "ordering_bias_ratio_after_over_before": jnum(ar_drift),
        },
        "batch_invariance": {
            "decode_level": {
                "invariant": invariance.invariant,
                "compared_tokens": invariance.compared_tokens,
                "first_divergence": invariance.first_divergence,
                "per_sequence": invariance.per_sequence,
            },
            "batched_matmul_numerics": numerics_json,
            "batched_matmul_numerics_invariant": numerics_invariant,
        },
        "amortization": amort_json(&amort),
        "fused_batch_forward_available": FUSED_BATCH_FORWARD_AVAILABLE,
        "fused_batch_forward_note": FUSED_BATCH_FORWARD_NOTE,
        "gate_input_eligible": false,
        "gate_input_reason": "A FUSED batched forward does not exist in this crate (qwen.rs \
             hardcodes the batch dim to 1), so the concurrency sweep is the LOCKSTEP CONTROL \
             (no weight-read amortization). The sweep's ratio is NOT the L-G4 gate number; the \
             amortization probe's whole-step factor is the estimate of what a fused batch would buy, \
             and the batched-matmul numerics verdict says whether a fused batch could even \
             reproduce a sequential decode token for token.",
        "gate_deciding_number": "amortization.whole_step_amortization at batch 8 (a projection \
             from measured per-op costs, not a measured decode) — compare it with the gate's 1.5.",
        "non_claims": [
            "Absolute tok/s and ms on this box are non-claims (the same prebuilt binary took 53 s \
             on a quiet box and 4 m 47 s on a loaded one). The RATIO is the measurement.",
            "The concurrency sweep is a LOCKSTEP CONTROL, not a fused batch: one weight read per \
             sequence per token, so it does NOT amortize. Its ratio is not the L-G4 gate input.",
            "The amortization probe covers the tied vocabulary projection and the body's quantized \
             GEMM stack. It excludes attention, the norms, and the cache write.",
            "One model, one device, under whatever power state is printed beside each number.",
        ],
    });
    let text = serde_json::to_string_pretty(&summary).expect("the summary serializes");
    println!("\n=== JSON SUMMARY (machine-readable) ===");
    println!("{text}");
    if let Some(path) = out_path.as_ref() {
        std::fs::write(path, format!("{text}\n")).expect("the summary file writes");
        println!("\nwrote {}", path.display());
    }
    println!(
        "\n=== L-G4 READING ===\n\
         The concurrency sweep above is the LOCKSTEP CONTROL: N sequences advance together but each \
         still runs its OWN forward, so the weight read is NOT amortized. Its ratio near 1.0 is \
         therefore NOT the gate's reading — it is what a NO-AMORTIZATION batch looks like, and it \
         is what the number would be if the batch were a no-op.\n\
         The number that decides the lever is the amortization probe's whole-step factor: a fused \
         batch would make one decode step serve B sequences, so the aggregate throughput ratio it \
         would buy is B * step(1) / step(B). Read THAT against the gate's 1.5.\n\
         Two preconditions before any fused number may be quoted: (a) the batched-matmul numerics \
         verdict — if a batched matmul changes the numbers, a fused batch would not reproduce a \
         sequential decode and any number measured through it is a function of the batch size; \
         (b) the decode-level invariance verdict.\n\
         No number in this run is a gate input until the fused forward exists (FUSED_BATCH_FORWARD_\
         AVAILABLE is false), so this run can only ESTABLISH whether the lever is worth buying."
    );
}

fn print_amortization(a: &AmortizationReport) {
    println!(
        "body GEMMs measured: {}/{} | layers {} | embed quantized: {} | projection table {} bytes | \
         table rows {}",
        a.measured_body_gems,
        a.expected_body_gems,
        a.layers,
        a.embed_is_quantized,
        a.projection_weight_bytes,
        a.table_rows
    );
    for (i, &batch) in a.batches.iter().enumerate() {
        println!(
            "batch {batch:>2}: projection {:>8.3} ms | body layer stack {:>8.3} ms | body linear \
             est {:>9.3} ms | whole-step est {:>9.3} ms | projection amort {:>5.3}x | body amort \
             {:>5.3}x | WHOLE-STEP amort {:>5.3}x",
            a.projection_ms[i],
            a.body_layer_gemm_ms[i],
            a.body_linear_estimate_ms[i],
            a.whole_step_estimate_ms[i],
            a.projection_amortization[i],
            a.body_linear_amortization[i],
            a.whole_step_amortization[i],
        );
    }
    println!(
        "amortization factor = B * cost(1) / cost(B): 1.0 means the batch bought NOTHING; B means \
         the batch is perfectly amortized."
    );
    println!(
        "READ THIS: a whole-step amortization near 1.0 means a FUSED batch would buy NOTHING on \
         this device and L-G4's lever does not exist; a factor well above 1.5 means it would, and \
         the qwen.rs change is worth buying."
    );
    println!(
        "The whole-step estimate is a PROJECTION from measured per-op costs (the body's linear \
         GEMMs x the layer count, plus the tied projection). Attention and the norms are excluded."
    );
}

fn amort_json(a: &AmortizationReport) -> serde_json::Value {
    let mut rows = Vec::new();
    for (i, &batch) in a.batches.iter().enumerate() {
        rows.push(json!({
            "batch": batch,
            "projection_ms": jnum(a.projection_ms[i]),
            "body_layer_gemm_ms": jnum(a.body_layer_gemm_ms[i]),
            "body_linear_estimate_ms": jnum(a.body_linear_estimate_ms[i]),
            "whole_step_estimate_ms": jnum(a.whole_step_estimate_ms[i]),
            "projection_amortization": jnum(a.projection_amortization[i]),
            "body_linear_amortization": jnum(a.body_linear_amortization[i]),
            "whole_step_amortization": jnum(a.whole_step_amortization[i]),
        }));
    }
    json!({
        "batches": rows,
        "measured_body_gems": a.measured_body_gems,
        "expected_body_gems": a.expected_body_gems,
        "layers": a.layers,
        "embed_is_quantized": a.embed_is_quantized,
        "projection_weight_bytes": a.projection_weight_bytes,
        "table_rows": a.table_rows,
        "definition": "amortization = B * cost(1) / cost(B); 1.0 = the batch bought nothing, B = \
             perfectly amortized. whole_step_amortization is the PROJECTED aggregate throughput \
             ratio a FUSED batch would buy (a projection from measured per-op costs, not a \
             measured decode).",
    })
}
