//! qwen35_parity — the RUST half's digest receipt against the python-first
//! reference (house pattern: python at tool/nursery/wm_qwen35_*.py, durable
//! fixture at testdata/qwen35_parity_digests.json).
//!
//! Emits, per prompt, the SAME contract as the python side:
//!   { prompt_id, prompt_token_ids, first_32_token_ids (the first
//!     min(32, max_tokens) GENERATED tokens), generated_steps,
//!     digest_steps, per_step_sha256,
//!     logits_digest_sha256_of_first_8_steps_fp32_rounded_6dp }
//!
//! Rounding rule (NORMATIVE, quoted from the fixture): the raw bf16 logits
//! row for the last position (vocab order, BEFORE logsumexp) is widened to
//! f32 exactly, every value formatted C fixed-point `{:.6}` (ties-to-even,
//! `-0.0` → `-0.000000`), values joined with `','`, step texts joined with
//! `'\n'` plus one trailing `'\n'`, UTF-8, SHA-256 lowercase hex. Token
//! choice: `argmax(logits - logsumexp(logits, keepdims))` (mlx-lm greedy
//! sampler). Prefill: chunks of <= 2048 over prompt[:-1]; last prompt token
//! is the first decode step. EOS stop OFF.
//!
//! Parity receipt: the python generator tool/nursery/wm_qwen35_digest.py
//! has LANDED; its normative rounding rule and this bin's implementation
//! were cross-checked line-by-line on 2026-11-06 ("%.6f" == "{:.6}" on the
//! exact f32 widening of bf16; steps joined with '\n' + one trailing '\n';
//! per_step_sha256 = sha256(step_text + '\n'); argmax(logits - logsumexp)
//! sampler; chunks of <= 2048 over prompt[:-1]; EOS off), and the digest
//! equality is asserted by tests/qwen35_parity.rs against the durable
//! fixture testdata/qwen35_parity_digests.json. If the python rule is ever
//! amended, re-align `qwen3_5::format_logits_row` / `steps_sha256` with the
//! fixture's "rounding_rule" text and re-run this bin once.
//!
//! Usage:
//!   cargo run --release --bin qwen35_parity -- \
//!       [--model DIR] [--prompts FILE] [--max-tokens 24] [--digest-steps 8] \
//!       [--fixture PATH] [--out FILE] [--assert]
//!
//!   --prompts FILE   one prompt per line (default: the fixture's prompts)
//!   --assert         exit 1 when any digest/token comparison mismatches
//!
//! The run is ONCE per invocation (machine-contention courtesy, 2026-11-05);
//! it prints the load average it ran under.

use mlx_native::bpe::ByteLevelBpe;
use mlx_native::mlx::{self, Stream};
use mlx_native::qwen3_5::{self, Qwen35};
use serde::Deserialize;

#[derive(Deserialize)]
struct Fixture {
    rounding_rule: String,
    provenance: serde_json::Value,
    results: Vec<FixtureResult>,
}

#[derive(Deserialize)]
struct FixtureResult {
    prompt_id: usize,
    prompt: String,
    prompt_token_ids: Vec<i32>,
    first_32_token_ids: Vec<i32>,
    generated_steps: usize,
    digest_steps: usize,
    vocab_size: usize,
    per_step_sha256: Vec<String>,
    logits_digest_sha256_of_first_8_steps_fp32_rounded_6dp: String,
}

fn fixture_path(arg: &Option<String>) -> std::path::PathBuf {
    if let Some(p) = arg {
        return std::path::PathBuf::from(p);
    }
    std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../testdata/qwen35_parity_digests.json")
}

fn load_avg() -> String {
    std::fs::read_to_string("/proc/loadavg")
        .ok()
        .or_else(|| {
            std::process::Command::new("sysctl")
                .args(["-n", "vm.loadavg"])
                .output()
                .ok()
                .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        })
        .unwrap_or_else(|| "unknown".to_string())
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

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let mut model_dir: Option<String> = None;
    let mut prompts_file: Option<String> = None;
    let mut fixture_arg: Option<String> = None;
    let mut out = String::new();
    let mut max_tokens_arg: Option<usize> = None;
    let mut digest_steps_arg: Option<usize> = None;
    let mut assert_parity = false;
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--model" => {
                model_dir = Some(args[i + 1].clone());
                i += 1;
            }
            "--prompts" => {
                prompts_file = Some(args[i + 1].clone());
                i += 1;
            }
            "--fixture" => {
                fixture_arg = Some(args[i + 1].clone());
                i += 1;
            }
            "--out" => {
                out = args[i + 1].clone();
                i += 1;
            }
            "--max-tokens" => {
                max_tokens_arg = Some(args[i + 1].parse().expect("max-tokens"));
                i += 1;
            }
            "--digest-steps" => {
                digest_steps_arg = Some(args[i + 1].parse().expect("digest-steps"));
                i += 1;
            }
            "--assert" => assert_parity = true,
            other => {
                eprintln!("unknown arg {other}");
                std::process::exit(2);
            }
        }
        i += 1;
    }

    let fixture: Fixture = serde_json::from_str(
        &std::fs::read_to_string(fixture_path(&fixture_arg))
            .expect("fixture readable (in-repo durable contract)"),
    )
    .expect("fixture parses");

    // Defaults come FROM the fixture (it is the contract): 24 steps, 8
    // digest steps for the pinned run.
    let max_tokens = max_tokens_arg
        .or_else(|| fixture.results.first().map(|r| r.generated_steps))
        .unwrap_or(24);
    let digest_steps = digest_steps_arg
        .or_else(|| fixture.results.first().map(|r| r.digest_steps))
        .unwrap_or(8);

    let dir = match model_dir {
        Some(p) => std::path::PathBuf::from(p),
        None => qwen3_5::default_snapshot_dir().unwrap_or_else(|| {
            eprintln!("QWEN35_CHECKPOINT_ABSENT: no snapshot dir (set QWEN35_SNAPSHOT or --model)");
            std::process::exit(1);
        }),
    };
    if !dir.is_dir() {
        eprintln!("QWEN35_CHECKPOINT_ABSENT: {dir:?} is not a directory");
        std::process::exit(1);
    }

    // Test/bench binaries don't sit beside a metallib; pin the cmake-built
    // one BEFORE the first gpu() call (the lfm2_parity test idiom).
    let metallib = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        mlx::set_metallib_path(&metallib);
    }
    let s: Stream = mlx::gpu().unwrap_or_else(|e| {
        eprintln!("NO_METAL_DEVICE: {e:?}");
        std::process::exit(1);
    });

    let prompts: Vec<(usize, String)> = match prompts_file {
        Some(p) => std::fs::read_to_string(&p)
            .unwrap_or_else(|e| panic!("prompts file {p}: {e}"))
            .lines()
            .filter(|l| !l.is_empty())
            .enumerate()
            .map(|(i, l)| (i, l.to_string()))
            .collect(),
        None => fixture
            .results
            .iter()
            .map(|r| (r.prompt_id, r.prompt.clone()))
            .collect(),
    };

    eprintln!("qwen35_parity — rust half receipt");
    eprintln!("model: {}", dir.display());
    eprintln!("load_avg: {}", load_avg());
    let (power, power_line) = power_facts();
    eprintln!("power: {power_line}");

    let t0 = std::time::Instant::now();
    let model = Qwen35::load(&dir).unwrap_or_else(|e| {
        eprintln!("QWEN35_LOAD_FAILED: {e}");
        std::process::exit(1);
    });
    let tok = ByteLevelBpe::load(&dir).unwrap_or_else(|e| {
        eprintln!("QWEN35_TOKENIZER_FAILED: {e}");
        std::process::exit(1);
    });
    let load_ms = t0.elapsed().as_secs_f64() * 1e3;

    let digest_steps_eff = digest_steps.min(max_tokens);
    let mut rows: Vec<serde_json::Value> = Vec::new();
    let mut all_match = true;

    for (pid, prompt) in &prompts {
        let ids: Vec<i32> = tok
            .encode(prompt)
            .unwrap_or_else(|e| panic!("tokenize {prompt:?}: {e}"))
            .into_iter()
            .map(|x| x as i32)
            .collect();
        if let Some(fx) = fixture.results.iter().find(|r| r.prompt_id == *pid) {
            assert_eq!(
                model.cfg.vocab, fx.vocab_size,
                "vocab_size disagrees with the fixture contract"
            );
        }

        let mut step_texts: Vec<String> = Vec::new();
        let mut per_step: Vec<String> = Vec::new();
        let mut generated: Vec<i32> = Vec::new();
        let gen = model
            .generate_greedy(
                &ids,
                max_tokens,
                digest_steps_eff,
                s,
                &mut |step, token, logits| {
                    generated.push(token);
                    if let Some(row) = logits {
                        let f32s = qwen3_5::logits_row_f32(row, s).expect("logits readback");
                        let text = qwen3_5::format_logits_row(&f32s);
                        per_step.push(qwen3_5::per_step_sha256(&text));
                        step_texts.push(text);
                        let _ = step;
                    }
                },
            )
            .unwrap_or_else(|e| {
                eprintln!("QWEN35_GENERATE_FAILED prompt {pid}: {e:?}");
                std::process::exit(1);
            });
        assert_eq!(gen, generated, "callback and return agree");
        let combined = qwen3_5::steps_sha256(&step_texts);

        let mut row = serde_json::json!({
            "prompt_id": pid,
            "prompt": prompt,
            "prompt_token_count": ids.len(),
            "prompt_token_ids": ids,
            "first_32_token_ids": generated.iter().take(32).copied().collect::<Vec<_>>(),
            "generated_steps": generated.len(),
            "digest_steps": digest_steps_eff,
            "vocab_size": model.cfg.vocab,
            "logits_dtype": "bfloat16",
            "per_step_sha256": per_step,
            "logits_digest_sha256_of_first_8_steps_fp32_rounded_6dp": combined,
        });

        // Parity verdict against the fixture (when this prompt is in it).
        if let Some(fx) = fixture.results.iter().find(|r| r.prompt_id == *pid) {
            let ids_match = fx.prompt_token_ids == ids;
            let tokens_match = fx.first_32_token_ids == generated[..generated.len().min(fx.first_32_token_ids.len())]
                && generated.len() >= fx.first_32_token_ids.len();
            let steps_match = fx.per_step_sha256 == per_step;
            let combined_match = fx.logits_digest_sha256_of_first_8_steps_fp32_rounded_6dp == combined;
            let matched = ids_match && tokens_match && steps_match && combined_match;
            all_match &= matched;
            row["parity"] = serde_json::json!({
                "prompt_token_ids_match": ids_match,
                "generated_tokens_match": tokens_match,
                "per_step_sha256_match": steps_match,
                "combined_digest_match": combined_match,
                "verdict": if matched { "MATCH" } else { "MISMATCH" },
            });
            eprintln!(
                "prompt {pid}: ids={ids_match} tokens={tokens_match} steps={steps_match} combined={combined_match} -> {}",
                if matched { "MATCH" } else { "MISMATCH" }
            );
            if !steps_match {
                for (i, (a, b)) in per_step.iter().zip(fx.per_step_sha256.iter()).enumerate() {
                    if a != b {
                        eprintln!("  first divergent step: {i}");
                        break;
                    }
                }
            }
        }
        rows.push(row);
    }

    let doc = serde_json::json!({
        "contract": "nursery.qwen35-parity.v1",
        "when_utc": chrono_utc(),
        "side": "rust (pkgs/xsoulspace_inference_mlx_native native/mlx_native)",
        "model_dir": dir.display().to_string(),
        "load_ms": load_ms,
        "max_tokens": max_tokens,
        "digest_steps": digest_steps_eff,
        "contention": { "load_avg": load_avg() },
        "power": { "source": power, "line": power_line },
        "python_provenance": fixture.provenance,
        "rounding_rule_echo": fixture.rounding_rule,
        "results": rows,
        "all_match": all_match,
    });
    let text = serde_json::to_string_pretty(&doc).expect("json");
    if out.is_empty() {
        println!("{text}");
    } else {
        std::fs::write(&out, text).expect("write out");
        eprintln!("wrote {out}");
    }
    if assert_parity && !all_match {
        std::process::exit(1);
    }
}
