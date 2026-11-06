//! ws2_rust_generate — WS-2 cross-engine CANDIDATE generator (Rust engine).
//!
//! The Rust half of the WS-2 agreement run (weightmap PROGRAM.md Phase B):
//! loads ONE mirror checkpoint with the SAME engine API the FFI/Dart client
//! drives (`qwen::Qwen3::load` + `generate_greedy`, `bpe::ByteLevelBpe`),
//! generates every prompt from the shared prompts json, and writes the jsonl
//! the Dart certifier consumes.
//!
//! Contract (mirrors tool/runs/ws2_py_generate.py in
//! xsoulspace_inference_weightmap; PYTHON is ALWAYS the REFERENCE per the
//! cross_engine.dart Python-first law — this bin only produces the candidate
//! evidence, it certifies nothing):
//!   - greedy decode: `generate_greedy(prompt_ids, cap, stop=None)` — the
//!     engine's raw-logits GPU argmax loop (token choice equals
//!     argmax(logits - logsumexp) by monotonicity; the qwen35 parity
//!     fixture pins the two implementations against each other)
//!   - EOS stop OFF: `stop=None` runs EXACTLY cap steps (engine default,
//!     laya_native_qwen_client.dart: "stopOnEos is strictly opt-in")
//!   - prompts arrive PRE-TEMPLATED (one rendering shared with the python
//!     side); tokenization is this engine's own checkpoint BPE, and the
//!     prompt ids are recorded so an encoding divergence is attributable
//!   - loop-rate bookkeeping: content_tokens = first generated EOS index
//!     (eos ids from the prompts file), else cap; cap_hit = content >= cap
//!
//! Usage (run under the device lock; serial -j 1):
//!   cargo run --release --bin ws2_rust_generate -- \
//!       --model DIR --prompts prompts.json --mirror NAME --out FILE
//!
//! jsonl row: {mirror, prompt_id, token_ids, text, tokens, evidence{...}}
//! (the five required WS-2 keys plus nested evidence; wall_ms rows are
//! NON-CLAIMS under contention). Errors are NAMED on stderr, exit 1.

use std::path::PathBuf;
use std::time::Instant;

use mlx_native::bpe::ByteLevelBpe;
use mlx_native::qwen::Qwen3;
use serde::Deserialize;

#[derive(Deserialize)]
struct PromptsFile {
    eos_token_ids: Vec<i64>,
    #[allow(dead_code)] // recorded contract flag; see the comment in run()
    add_special_tokens: bool,
    cells: Vec<PromptCell>,
}

#[derive(Deserialize)]
struct PromptCell {
    prompt_id: String,
    group: String,
    cap: usize,
    templated: String,
}

struct Args {
    model: PathBuf,
    prompts: PathBuf,
    mirror: String,
    out: PathBuf,
}

fn parse_args() -> Result<Args, String> {
    let mut argv = std::env::args().skip(1);
    let mut get = |flag: &str| -> Result<String, String> {
        while let Some(a) = argv.next() {
            if a == flag {
                return argv
                    .next()
                    .ok_or_else(|| format!("ARGS_INVALID: {flag} without value"));
            }
        }
        Err(format!("ARGS_INVALID: missing {flag}"))
    };
    Ok(Args {
        model: PathBuf::from(get("--model")?),
        prompts: PathBuf::from(get("--prompts")?),
        mirror: get("--mirror")?,
        out: PathBuf::from(get("--out")?),
    })
}

fn sha256_file(path: &std::path::Path) -> Option<String> {
    let bytes = std::fs::read(path).ok()?;
    Some(mlx_native::nursery::sha256_hex(&bytes))
}

fn main() {
    if let Err(msg) = run() {
        eprintln!("{msg}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let args = parse_args()?;
    if !args.model.is_dir() {
        return Err(format!("MIRROR_DIR_MISSING: {}", args.model.display()));
    }
    let raw = std::fs::read_to_string(&args.prompts)
        .map_err(|e| format!("PROMPTS_FILE_UNREADABLE: {} ({e})", args.prompts.display()))?;
    let prompts: PromptsFile = serde_json::from_str(&raw)
        .map_err(|e| format!("PROMPTS_MALFORMED: {} ({e})", args.prompts.display()))?;
    // add_special_tokens is informational: under the frozen wm contract it
    // equals (bos_token is None), and BOTH branches make the python side a
    // PLAIN encode (add_special_tokens=True on a bos-less tokenizer adds
    // nothing; =False adds nothing by definition), which is exactly this
    // engine's plain BPE encode. Recorded in the evidence rows, never a
    // divergence source for the Qwen3 family this bin serves.
    let eos: Vec<i32> = prompts.eos_token_ids.iter().map(|&i| i as i32).collect();

    // Same metallib pin as the sibling bins (qwen_decode_bench.rs).
    let metallib = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        let _ = mlx_native::mlx::set_metallib_path(&metallib);
    }
    let s = mlx_native::mlx::gpu().map_err(|e| format!("GPU_UNAVAILABLE: mlx status {}", e.0))?;
    let power0 = mlx_native::power::facts().describe();
    let t_load = Instant::now();
    let model = Qwen3::load(&args.model).map_err(|e| format!("MODEL_LOAD_ERROR: mlx status {}", e.0))?;
    let bpe = ByteLevelBpe::load(&args.model).map_err(|e| format!("TOKENIZER_LOAD_ERROR: {e}"))?;
    let load_s = t_load.elapsed().as_secs_f64();
    let shard = args.model.join("model.safetensors");
    let model_sha = sha256_file(&shard);

    let mut lines: Vec<String> = Vec::new();
    let t_batch = Instant::now();
    for (i, cell) in prompts.cells.iter().enumerate() {
        let prompt_ids: Vec<i32> = bpe
            .encode(&cell.templated)
            .map_err(|e| format!("TOKENIZE_FAILED: {} ({e})", cell.prompt_id))?
            .into_iter()
            .map(|v| v as i32)
            .collect();
        let t0 = Instant::now();
        let full = model
            .generate_greedy(&prompt_ids, cell.cap, None, s)
            .map_err(|e| format!("GENERATE_FAILED: {} (mlx status {})", cell.prompt_id, e.0))?;
        let wall_ms = t0.elapsed().as_millis() as u64;
        if full.len() < prompt_ids.len() {
            return Err(format!(
                "ENGINE_CONTRACT_VIOLATION: {} returned {} ids for a {}-token prompt",
                cell.prompt_id,
                full.len(),
                prompt_ids.len()
            ));
        }
        let gen: Vec<i32> = full[prompt_ids.len()..].to_vec();
        let text = bpe
            .decode(&gen.iter().map(|&v| v as u32).collect::<Vec<_>>())
            .map_err(|e| format!("DECODE_FAILED: {} ({e})", cell.prompt_id))?;
        let first_eos = gen.iter().position(|t| eos.contains(t));
        let content_n = first_eos.unwrap_or(cell.cap);
        let cap_hit = content_n >= cell.cap;
        let row = serde_json::json!({
            "mirror": args.mirror,
            "prompt_id": cell.prompt_id,
            "token_ids": gen,
            "text": text,
            "tokens": gen.len(),
            "evidence": {
                "engine": "rust",
                "group": cell.group,
                "cap": cell.cap,
                "prompt_token_ids": prompt_ids,
                "content_tokens": content_n,
                "first_eos_index": first_eos,
                "cap_hit": cap_hit,
                "eos_stop": false,
                "sampler": "greedy: generate_greedy raw-logits argmax (stop=None)",
                "prefill_step_size": 2048,
                "model_dir": args.model.display().to_string(),
                "model_sha256": model_sha,
                "load_s": load_s,
                "wall_ms": wall_ms,
                "wall_ms_claim": false,
                "power": power0,
            },
        });
        lines.push(serde_json::to_string(&row).map_err(|e| format!("JSON_WRITE: {e}"))?);
        println!(
            "[{}/{}] {} {} tok={}/{} content={} hit={} {:.1}s",
            i + 1,
            prompts.cells.len(),
            args.mirror,
            cell.prompt_id,
            gen.len(),
            cell.cap,
            content_n,
            cap_hit,
            wall_ms as f64 / 1000.0
        );
    }

    let meta = serde_json::json!({
        "mirror": args.mirror,
        "prompt_id": "__meta__",
        "token_ids": [],
        "text": "",
        "tokens": 0,
        "evidence": {
            "engine": "rust",
            "kind": "batch_meta",
            "tool": "ws2_rust_generate (cargo bin)",
            "prompts_file": args.prompts.display().to_string(),
            "prompts_file_sha256": sha256_file(&args.prompts),
            "cells": prompts.cells.len(),
            "batch_wall_s": t_batch.elapsed().as_secs_f64(),
            "batch_wall_s_claim": false,
            "model_sha256": model_sha,
            "eos_token_ids": eos,
            "power_start": power0,
            "power_end": mlx_native::power::facts().describe(),
            "crate_version": env!("CARGO_PKG_VERSION"),
        },
    });
    lines.push(serde_json::to_string(&meta).map_err(|e| format!("JSON_WRITE: {e}"))?);

    if let Some(parent) = args.out.parent() {
        std::fs::create_dir_all(parent).map_err(|e| format!("OUT_UNWRITABLE: {e}"))?;
    }
    std::fs::write(&args.out, lines.join("\n") + "\n")
        .map_err(|e| format!("OUT_UNWRITABLE: {} ({e})", args.out.display()))?;
    println!(
        "GENERATE_OK {} {} cells -> {}",
        args.mirror,
        prompts.cells.len(),
        args.out.display()
    );
    Ok(())
}
