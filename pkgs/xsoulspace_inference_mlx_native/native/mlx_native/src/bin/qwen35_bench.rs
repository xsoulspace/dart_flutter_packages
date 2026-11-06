//! qwen35_bench — prefill/decode throughput for the Qwen3.5-0.8B text
//! tower, in the measurement shape of qwen_fused_bench.rs (median of
//! rounds, forced eval, AC/battery power facts, JSON receipt).
//!
//! METHOD (documented, unlike the fused bench's internal clocks):
//!   prefill  — fresh reserved cache; the KV/state-only forward over
//!              prompt[:-1] (chunks of <= 2048, the generation pipeline's
//!              shape), forced eval; tok/s = prompt tokens / wall.
//!   decode   — fresh reserved cache; prefill run UNTIMED (forced eval),
//!              then N timed greedy steps (full sampler readback per step:
//!              logsumexp + argmax + host sync — what a serving loop pays).
//!
//! KNOWN SHAPE (honest numbers, not a regression claim): the gated-delta
//! recurrence runs the mlx-lm packed kernel ONE CALL PER LAYER PER FORWARD
//! (prefill batches all T tokens in that one call; decode is one token per
//! call), but every other op is the plain mlx-c graph — no declared plan,
//! no fused epilogues yet. Those are separate increments (the qwen.rs
//! plan-path history is the template).
//!
//! Contention courtesy (2026-11-05 coordinator notice): run ONCE, not in
//! loops; the receipt records the load average, and under contention the
//! numbers are NON-CLAIMS per POWER.md (ratios survive, absoltes don't).
//!
//! Usage:
//!   cargo run --release --bin qwen35_bench -- [--model DIR] [--rounds 3] \
//!       [--decode-tokens 64] [--out FILE]

use mlx_native::bpe::ByteLevelBpe;
use mlx_native::mlx::{self, Array, Dtype, Stream};
use mlx_native::qwen3_5::{Qwen35, Qwen35Cache};

fn median(xs: &mut [f64]) -> f64 {
    xs.sort_by(|a, b| a.partial_cmp(b).unwrap());
    xs[xs.len() / 2]
}

fn power_facts() -> (String, String) {
    match std::process::Command::new("pmset").arg("-g").arg("ps").output() {
        Ok(o) => {
            let txt = String::from_utf8_lossy(&o.stdout).to_string();
            let ac = txt.contains("AC Power");
            (
                if ac { "AC" } else { "battery" }.to_string(),
                txt.lines().last().unwrap_or("").trim().to_string(),
            )
        }
        Err(_) => ("unknown".to_string(), "pmset unavailable".to_string()),
    }
}

fn load_avg() -> String {
    std::process::Command::new("sysctl")
        .args(["-n", "vm.loadavg"])
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_else(|| "unknown".to_string())
}

fn chrono_utc() -> String {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| {
            let secs = d.as_secs();
            let days = secs / 86400;
            let (y, m, dd) = civil_from_days(days as i64);
            let rem = secs % 86400;
            format!(
                "{y:04}-{m:02}-{dd:02}T{:02}:{:02}:{:02}Z",
                rem / 3600,
                (rem % 3600) / 60,
                rem % 60
            )
        })
        .unwrap_or_else(|_| "unknown".to_string())
}

fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u64;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (if m <= 2 { y + 1 } else { y }, m, d)
}

const PREFILL_STEP: usize = 2048;

/// The generation pipeline's prefill: chunks of <= 2048 over ids[..len-1],
/// KV/state-only forwards, forced. Returns the wall time. (`ids.len() >= 2`
/// — the bench's prompts satisfy it.)
fn timed_prefill(model: &Qwen35, ids: &[i32], cache: &mut Qwen35Cache, s: Stream) -> f64 {
    let t0 = std::time::Instant::now();
    let mut rest = &ids[..ids.len() - 1];
    while !rest.is_empty() {
        let n = PREFILL_STEP.min(rest.len());
        let t = Array::from_data_i32(&rest[..n], &[1, n]).expect("arr");
        let h = model.forward(&t, cache, false, s).expect("prefill forward");
        h.eval().expect("eval");
        rest = &rest[n..];
    }
    t0.elapsed().as_secs_f64()
}

/// One greedy step's sampler readback (the fixture's token choice).
fn sampler_next(logits_row: &Array, s: Stream) -> i32 {
    let lse = logits_row
        .logsumexp_axis(-1, true, s)
        .expect("logsumexp");
    let adj = logits_row.sub(&lse, s).expect("sub");
    let am = adj.argmax_axis(-1, false, s).expect("argmax");
    let f = am.astype(Dtype::Float32, s).expect("cast");
    let v = f.to_f32_vec(s).expect("readback");
    v.first().copied().expect("one token") as i32
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let mut model_dir: Option<String> = None;
    let mut out = String::new();
    let mut rounds = 3usize;
    let mut decode_tokens = 64usize;
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--model" => {
                model_dir = Some(args[i + 1].clone());
                i += 1;
            }
            "--out" => {
                out = args[i + 1].clone();
                i += 1;
            }
            "--rounds" => {
                rounds = args[i + 1].parse().expect("rounds");
                i += 1;
            }
            "--decode-tokens" => {
                decode_tokens = args[i + 1].parse().expect("decode-tokens");
                i += 1;
            }
            other => {
                eprintln!("unknown arg {other}");
                std::process::exit(2);
            }
        }
        i += 1;
    }

    let dir = match model_dir {
        Some(p) => std::path::PathBuf::from(p),
        None => mlx_native::qwen3_5::default_snapshot_dir().unwrap_or_else(|| {
            eprintln!("QWEN35_CHECKPOINT_ABSENT: set QWEN35_SNAPSHOT or --model");
            std::process::exit(1);
        }),
    };
    let metallib = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        mlx::set_metallib_path(&metallib);
    }
    let s = mlx::gpu().unwrap_or_else(|e| {
        eprintln!("NO_METAL_DEVICE: {e:?}");
        std::process::exit(1);
    });
    let (power, power_line) = power_facts();
    let contention = load_avg();
    eprintln!("qwen35_bench — power: {power_line}");
    eprintln!("load_avg: {contention}");

    let model = Qwen35::load(&dir).unwrap_or_else(|e| {
        eprintln!("QWEN35_LOAD_FAILED: {e}");
        std::process::exit(1);
    });
    let tok = ByteLevelBpe::load(&dir).expect("tokenizer loads");

    // Prompt set: the parity fixture's short prompt plus a ~512-token
    // synthetic (repeat-and-truncate), so prefill has a meaningful slope.
    let short = "The capital of France is";
    let long_text = "Explain why a batched matrix multiply is not bit-identical to the same row alone. ".repeat(60);
    let prompts: Vec<(String, Vec<i32>)> = [short, long_text.as_str()]
        .iter()
        .map(|t| {
            let mut ids: Vec<i32> = tok
                .encode(t)
                .expect("encode")
                .into_iter()
                .map(|x| x as i32)
                .collect();
            if ids.len() > 512 {
                ids.truncate(512);
            }
            (t.chars().take(48).collect::<String>(), ids)
        })
        .collect();

    let mut rows = Vec::new();
    for (label, ids) in &prompts {
        let prompt_toks = ids.len() - 1; // the prefill's token count
        let mut prefill_samples = Vec::new();
        let mut decode_samples = Vec::new();
        for _ in 0..rounds {
            // prefill (timed, fresh cache each round)
            let mut cache = Qwen35Cache::new(&model.cfg);
            cache
                .reserve(1, model.cfg.kv_heads, model.cfg.head_dim, ids.len() + decode_tokens, s)
                .expect("reserve");
            let w = timed_prefill(&model, ids, &mut cache, s);
            prefill_samples.push(prompt_toks as f64 / w.max(1e-9));

            // decode (prefill untimed on a fresh cache, then timed steps)
            let mut cache = Qwen35Cache::new(&model.cfg);
            cache
                .reserve(1, model.cfg.kv_heads, model.cfg.head_dim, ids.len() + decode_tokens, s)
                .expect("reserve");
            let _ = timed_prefill(&model, ids, &mut cache, s);
            let mut next = ids[ids.len() - 1];
            let t0 = std::time::Instant::now();
            for _ in 0..decode_tokens {
                let t = Array::from_data_i32(&[next], &[1, 1]).expect("arr");
                let logits = model.forward(&t, &mut cache, true, s).expect("forward");
                let row = logits.reshape(&[1, model.cfg.vocab], s).expect("reshape");
                next = sampler_next(&row, s);
            }
            let dt = t0.elapsed().as_secs_f64();
            decode_samples.push(decode_tokens as f64 / dt);
        }
        let prefill_med = median(&mut prefill_samples);
        let decode_med = median(&mut decode_samples);
        eprintln!(
            "prompt {label:?} ({} tokens): prefill {:.1} tok/s, decode {:.1} tok/s",
            ids.len(),
            prefill_med,
            decode_med
        );
        rows.push(serde_json::json!({
            "prompt": label,
            "prompt_tokens": ids.len(),
            "prefill_tok_s_median": prefill_med,
            "decode_tok_s_median": decode_med,
            "decode_tokens": decode_tokens,
        }));
    }

    // Analytic memory (a property, not a measurement): KV per token over
    // the full-attention layers; the constant gated-delta state.
    let full_layers = model
        .cfg
        .layer_types
        .iter()
        .filter(|k| **k == mlx_native::qwen3_5::LayerKind::FullAttention)
        .count();
    let kv_per_token = 2 * full_layers * model.cfg.kv_heads * model.cfg.head_dim * 2;
    let gdn_state_bytes = model.cfg.layer_types.len().saturating_sub(full_layers)
        * (model.cfg.lin_v_heads * model.cfg.lin_v_dim * model.cfg.lin_k_dim * 4
            + (model.cfg.conv_kernel - 1)
                * (2 * model.cfg.lin_k_heads * model.cfg.lin_k_dim
                    + model.cfg.lin_v_heads * model.cfg.lin_v_dim)
                * 2);

    let doc = serde_json::json!({
        "contract": "nursery.qwen35-bench.v1",
        "when_utc": chrono_utc(),
        "model_dir": dir.display().to_string(),
        "rounds": rounds,
        "method": "prefill: timed KV-only forward over prompt[:-1]; decode: untimed prefill + timed greedy steps with full sampler readback",
        "power": { "source": power, "line": power_line },
        "contention": {
            "load_avg": contention,
            "note": "run once per coordinator contention notice; under contention these absolutes are NON-CLAIMS per POWER.md",
        },
        "rows": rows,
        "memory": {
            "kv_bytes_per_token": kv_per_token,
            "gdn_state_bytes_constant": gdn_state_bytes,
        },
        "known_shape": "one packed-GDN kernel call per linear layer per forward; plain mlx-c graph elsewhere (no declared plan yet)",
    });
    let text = serde_json::to_string_pretty(&doc).expect("json");
    if out.is_empty() {
        println!("{text}");
    } else {
        std::fs::write(&out, text).expect("write out");
        eprintln!("wrote {out}");
    }
}
