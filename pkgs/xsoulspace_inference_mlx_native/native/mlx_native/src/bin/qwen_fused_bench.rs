//! qwen_fused_bench — Tier A's measured numbers + L-G5's cost gate.
//!
//! Modes:
//!   decode        the fused batch's aggregate tok/s at B = 1/2/4/8/16
//!                 against the lockstep control (which does NOT amortize
//!                 the weight read), interleaved in one process. The 5.39x
//!                 projection (acceleration RESULTS §1.4) becomes a
//!                 measurement here — or fails to.
//!   rank          ranking economics: the sequential native ranker (one
//!                 candidate forward per label, KV-rewound) against the
//!                 fused ranker (all labels in ONE right-padded forward).
//!                 Ranking was more expensive than generation ONLY because
//!                 labels could not batch; this is the re-measurement.
//!   prompt-shape  L-G5: per-task option list vs the shared union list —
//!                 prompt bytes, prefill wall at concurrency 1 and 8 (the
//!                 fused batched prefill), peak KV bytes, and the prefix-
//!                 cache hit rate at a product-shaped (2048+) window.
//!
//! Every perf number here is AC-ONLY (ADR 0061 / POWER.md): on battery the
//! run completes but is marked POWER-CONTAMINATED — non-baseline; the
//! ratios are the measurement and even they are weakened. The decision
//! equalities the modes also report are not power-conditioned.
//!
//! Usage:
//!   cargo run --release --bin qwen_fused_bench -- --mode decode \
//!       [--out ../../bench/nursery/experiments/fused-decode.json] \
//!       [--rounds 5] [--max-tokens 48]

use mlx_native::bpe::ByteLevelBpe;
use mlx_native::mlx::{gpu, Stream};
use mlx_native::qwen::{KvCache, Qwen3};
use mlx_native::qwen_batch::{self, BatchRequest};
use mlx_native::qwen_fused::{self, plan_fused_batch};
use mlx_native::qwen_prefix::{CacheScope, PrefixPool};
use mlx_native::qwen_rank::{rank_labels_with, RankOptions};

fn median(xs: &mut [f64]) -> f64 {
    xs.sort_by(|a, b| a.partial_cmp(b).unwrap());
    xs[xs.len() / 2]
}

fn power_facts() -> (String, String) {
    let out = std::process::Command::new("pmset").arg("-g").arg("ps").output();
    match out {
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

fn snapshot_dir() -> Option<std::path::PathBuf> {
    if let Some(over) = std::env::var_os("QWEN3_SNAPSHOT") {
        let p = std::path::PathBuf::from(over);
        if p.is_dir() {
            return Some(p);
        }
        return None;
    }
    let home = std::env::var_os("HOME")?;
    let hub = std::path::PathBuf::from(home).join(".cache/huggingface/hub");
    for entry in std::fs::read_dir(&hub).ok()?.flatten() {
        if entry.file_name().to_string_lossy().contains("Qwen3-0.6B-4bit") {
            if let Ok(list) = std::fs::read_dir(entry.path().join("snapshots")) {
                for s in list.flatten() {
                    if s.path().is_dir() && s.path().join("config.json").is_file() {
                        return Some(s.path());
                    }
                }
            }
        }
    }
    None
}

const GEN_TEXTS: [&str; 16] = [
    "Summarize the plot of a short story about a lighthouse keeper who finds a message in a bottle.",
    "Yes.",
    "Write a haiku about deterministic floating-point arithmetic.",
    "Explain why a batched matrix multiply is not bit-identical to the same row alone.",
    "Classify the text. Answer with exactly one of: allow_once, abstain\n\nText: the nightly backup will overwrite yesterday's export.\nAnswer:",
    "Classify the text. Answer with exactly one of: allow_once, abstain\n\nText: anyone may read the public changelog.\nAnswer:",
    "Classify the text. Answer with exactly one of: allow_once, abstain\n\nText: the deploy script removes the target directory without asking.\nAnswer:",
    "Classify the text. Answer with exactly one of: allow_once, abstain\n\nText: the renderer reads ~/.ssh/id_rsa to sign its builds.\nAnswer:",
    "Translate to French: the weather is pleasant today and the market is open.",
    "List the first five prime numbers and explain why one is not prime.",
    "Name the instrument family for: a valve trombone played in a New Orleans second line.",
    "Name the instrument family for: a pedal steel guitar sliding under a country ballad.",
    "Classify the text. Answer with exactly one of: allow_once, abstain\n\nText: the CI runner may publish docs on tag release.\nAnswer:",
    "Classify the text. Answer with exactly one of: allow_once, abstain\n\nText: the app silently uploads the contact book on first launch.\nAnswer:",
    "Write two sentences about tide pools that a seven-year-old would enjoy.",
    "Explain the difference between a veto and an abstention in one paragraph.",
];

fn tokenize(model_texts: &[&str], tok: &ByteLevelBpe) -> Vec<Vec<i32>> {
    model_texts
        .iter()
        .map(|t| {
            let ids: Vec<i32> = tok.encode(t).expect("encode").into_iter().map(|x| x as i32).collect();
            assert!(ids.len() >= 2, "bench prompts must be >= 2 tokens");
            ids
        })
        .collect()
}

// ---- mode: decode ----

fn run_decode(model: &Qwen3, tok: &ByteLevelBpe, s: Stream, rounds: usize, max_tokens: usize) -> serde_json::Value {
    let ids = tokenize(&GEN_TEXTS, tok);
    let batch_sizes = [1usize, 2, 4, 8, 16];
    let mut fused_med: std::collections::HashMap<usize, f64> = Default::default();
    let mut lockstep_med: std::collections::HashMap<usize, f64> = Default::default();
    // Interleave the batch sizes inside every round so thermal drift
    // cancels rather than biasing one arm (the lane's interleaving law).
    let mut fused_samples: std::collections::HashMap<usize, Vec<f64>> = Default::default();
    let mut lockstep_samples: std::collections::HashMap<usize, Vec<f64>> = Default::default();
    for _ in 0..rounds {
        for &b in &batch_sizes {
            let reqs: Vec<BatchRequest> = ids[..b]
                .iter()
                .map(|p| BatchRequest {
                    prompt_ids: p.clone(),
                    max_tokens,
                })
                .collect();
            let (_, t) =
                qwen_fused::generate_greedy_fused_timed(model, &reqs, None, s).expect("fused");
            fused_samples
                .entry(b)
                .or_default()
                .push(t.tokens as f64 / t.decode_s);
            let (_, tl) =
                qwen_batch::generate_greedy_batched_timed(model, &reqs, None, s).expect("lockstep");
            lockstep_samples
                .entry(b)
                .or_default()
                .push(tl.tokens as f64 / tl.decode_s);
        }
    }
    for b in batch_sizes {
        fused_med.insert(b, median(fused_samples.get_mut(&b).unwrap()));
        lockstep_med.insert(b, median(lockstep_samples.get_mut(&b).unwrap()));
    }
    let base_f = fused_med[&1];
    let base_l = lockstep_med[&1];
    let rows: Vec<serde_json::Value> = batch_sizes
        .iter()
        .map(|&b| {
            serde_json::json!({
                "batch": b,
                "fused_agg_tok_s": fused_med[&b],
                "fused_ratio_vs_b1": fused_med[&b] / base_f,
                "lockstep_agg_tok_s": lockstep_med[&b],
                "lockstep_ratio_vs_b1": lockstep_med[&b] / base_l,
                "fused_vs_lockstep": fused_med[&b] / lockstep_med[&b],
            })
        })
        .collect();
    serde_json::json!({
        "mode": "decode",
        "rounds": rounds,
        "max_tokens": max_tokens,
        "prompt_tokens": ids.iter().map(|p| p.len()).collect::<Vec<_>>(),
        "rows": rows,
        "projection_whole_step_b8": 5.39,
        "bit_floor_note": "bit-level divergence across a batch dim is measured (0.0625 body / 0.0239 projection) and retired as a bar; the decision-level gate is tests/qwen_fused_batch_gate.rs",
    })
}

// ---- mode: rank ----

fn run_rank(model: &Qwen3, tok: &ByteLevelBpe, s: Stream, rounds: usize) -> serde_json::Value {
    let tasks: Vec<(&str, Vec<&str>)> = vec![
        ("perm", vec!["allow_once", "abstain"]),
        (
            "veto",
            vec!["no_grant", "destructive_op", "outside_workspace", "secret_path"],
        ),
    ];
    let bodies = [
        "the nightly backup will overwrite yesterday's export",
        "anyone may read the public changelog",
        "the deploy script removes the target directory without asking",
        "the renderer reads ~/.ssh/id_rsa to sign its builds",
    ];
    let mut rows = Vec::new();
    for (ti, (task, labels)) in tasks.iter().enumerate() {
        let prompt = format!(
            "Classify the text. Answer with exactly one of: {}\n\nText: {}\nAnswer:",
            labels.join(", "),
            bodies[ti % bodies.len()]
        );
        let mut seq_samples = Vec::new();
        let mut fus_samples = Vec::new();
        let mut labels_agree = true;
        let mut max_logprob_drift = 0.0f32;
        let seq_ref;
        {
            // One correctness comparison (not timed): the fused ranker must
            // pick the same label and land within the stated drift.
            let a = rank_labels_with(model, tok, &prompt, labels, RankOptions::default(), s)
                .expect("rank seq");
            let b = qwen_fused::rank_labels_fused(model, tok, &prompt, labels, RankOptions::default(), s)
                .expect("rank fused");
            labels_agree = a.label == b.label;
            for ((la, pa), (lb, pb)) in a.logprobs.iter().zip(b.logprobs.iter()) {
                assert_eq!(la, lb);
                max_logprob_drift = max_logprob_drift.max((pa - pb).abs());
            }
            seq_ref = serde_json::json!({
                "label_seq": a.label, "label_fused": b.label,
                "logprobs_seq": a.logprobs, "logprobs_fused": b.logprobs,
            });
        }
        for _ in 0..rounds {
            let t0 = std::time::Instant::now();
            let _ = rank_labels_with(model, tok, &prompt, labels, RankOptions::default(), s).expect("rank");
            seq_samples.push(t0.elapsed().as_secs_f64());
            let t1 = std::time::Instant::now();
            let _ = qwen_fused::rank_labels_fused(model, tok, &prompt, labels, RankOptions::default(), s)
                .expect("rank fused");
            fus_samples.push(t1.elapsed().as_secs_f64());
        }
        let seq_med = median(&mut seq_samples);
        let fus_med = median(&mut fus_samples);
        rows.push(serde_json::json!({
            "task": task,
            "labels_k": labels.len(),
            "seq_ms": seq_med * 1e3,
            "fused_ms": fus_med * 1e3,
            "fused_vs_seq": fus_med / seq_med,
            "labels_agree": labels_agree,
            "max_logprob_drift": max_logprob_drift,
            "correctness": seq_ref,
        }));
        eprintln!(
            "rank {task} (K={}): sequential {:.1} ms, fused {:.1} ms = {:.2}x | agree={} drift={max_logprob_drift:.4}",
            labels.len(), seq_med * 1e3, fus_med * 1e3, fus_med / seq_med, labels_agree
        );
    }
    serde_json::json!({ "mode": "rank", "rounds": rounds, "rows": rows })
}

// ---- mode: prompt-shape (L-G5) ----

const PERM_LABELS: &str = "allow_once, abstain";
const UNION_LABELS: &str =
    "allow_once, abstain, no_grant, destructive_op, outside_workspace, secret_path, strings, woodwind, brass, percussion";

fn run_prompt_shape(model: &Qwen3, tok: &ByteLevelBpe, s: Stream, rounds: usize) -> serde_json::Value {
    let bodies = [
        "the nightly backup will overwrite yesterday's export",
        "anyone may read the public changelog",
        "the deploy script removes the target directory without asking",
        "the renderer reads ~/.ssh/id_rsa to sign its builds",
        "the CI runner may publish docs on tag release",
        "the app silently uploads the contact book on first launch",
        "the linter may rewrite files inside the workspace",
        "the hook exfiltrates environment variables to a third party",
    ];
    let render = |labels: &str, body: &str| {
        format!("Classify the text. Answer with exactly one of: {labels}\n\nText: {body}\nAnswer:")
    };
    let shapes = [("per_task", PERM_LABELS), ("shared_union", UNION_LABELS)];

    // ---- prompt bytes + tokens ----
    let mut shape_stats = Vec::new();
    for (name, labels) in shapes {
        let texts: Vec<String> = bodies.iter().map(|b| render(labels, b)).collect();
        let bytes: Vec<usize> = texts.iter().map(|t| t.len()).collect();
        let toks: Vec<usize> = texts
            .iter()
            .map(|t| tok.encode(t).expect("encode").len())
            .collect();
        let tokens_median: usize = {
            let mut v = toks.clone();
            v.sort_unstable();
            v[v.len() / 2]
        };
        shape_stats.push(serde_json::json!({
            "shape": name,
            "bytes_median": bytes.iter().copied().fold(0, usize::min).max(bytes.iter().sum::<usize>() / bytes.len()),
            "bytes_all": bytes,
            "tokens_all": toks,
            "tokens_median": tokens_median,
        }));
        eprintln!("shape {name}: bytes median-ish {}, tokens {:?}", bytes[0], toks);
    }

    // ---- prefill wall, concurrency 1 and 8 (the fused batched prefill) ----
    // The wall is the KV-only prompt-ingestion forward (what a prefill
    // costs), forced-eval'd — the 28.7x lesson never sleeps.
    let prefill_wall = |texts: &[String]| -> (f64, f64) {
        // c=1: median single-prompt wall.
        let mut one = Vec::new();
        let mut batch = Vec::new();
        let ids: Vec<Vec<i32>> = texts
            .iter()
            .map(|t| tok.encode(t).expect("encode").into_iter().map(|x| x as i32).collect())
            .collect();
        for _ in 0..rounds {
            for p in &ids {
                let cache = &mut KvCache::new(model.cfg.layers);
                cache
                    .reserve(model.table(), 1, model.cfg.kv_heads, model.cfg.head_dim, p.len() + 2, s)
                    .expect("reserve");
                let arr = mlx_native::mlx::Array::from_data_i32(p, &[1, p.len()]).expect("arr");
                let t0 = std::time::Instant::now();
                let h = model.forward_hidden(&arr, cache, s).expect("forward");
                h.eval().expect("eval");
                one.push(t0.elapsed().as_secs_f64());
            }
        }
        // c=8: ONE left-padded batched prefill (the fused path), forced.
        for _ in 0..rounds {
            let reqs: Vec<BatchRequest> = ids
                .iter()
                .map(|p| BatchRequest {
                    prompt_ids: p.clone(),
                    max_tokens: 1,
                })
                .collect();
            let plan = plan_fused_batch(&reqs).expect("plan");
            let cache = &mut KvCache::new(model.cfg.layers);
            cache
                .reserve(
                    model.table(),
                    plan.batch,
                    model.cfg.kv_heads,
                    model.cfg.head_dim,
                    plan.l_max + 2,
                    s,
                )
                .expect("reserve");
            let arr =
                mlx_native::mlx::Array::from_data_i32(&plan.tokens, &[plan.batch, plan.l_max])
                    .expect("arr");
            let t0 = std::time::Instant::now();
            let h = if plan.has_padding {
                let mask = qwen_fused::prefill_mask(&plan, s).expect("mask");
                model.forward_masked(&arr, cache, &mask, false, s).expect("forward")
            } else {
                model.forward_hidden(&arr, cache, s).expect("forward")
            };
            h.eval().expect("eval");
            batch.push(t0.elapsed().as_secs_f64());
        }
        (median(&mut one), median(&mut batch))
    };

    let mut walls = Vec::new();
    for (name, labels) in shapes {
        let texts: Vec<String> = bodies.iter().map(|b| render(labels, b)).collect();
        let (c1, c8) = prefill_wall(&texts);
        eprintln!("shape {name}: prefill c1 {:.2} ms/prompt, c8 {:.2} ms/prompt (batched/8)", c1 * 1e3, c8 * 1e3 / 8.0);
        walls.push(serde_json::json!({
            "shape": name,
            "prefill_c1_ms": c1 * 1e3,
            "prefill_c8_batch_ms": c8 * 1e3,
            "prefill_c8_ms_per_prompt": c8 * 1e3 / 8.0,
        }));
    }

    // ---- peak KV bytes (analytic from the config — a property, not a
    // measurement) ----
    let kv_per_token = 2 * model.cfg.layers * model.cfg.kv_heads * model.cfg.head_dim * 2; // K+V, bf16
    let kv = serde_json::json!({
        "per_token_bytes": kv_per_token,
        "note": "K+V x layers x kv_heads x head_dim x bf16; peak = window x per_token x batch",
    });

    // ---- prefix-cache hit rate at a product-shaped window (2048+): the
    // shared union list makes the instruction prefix IDENTICAL across
    // tasks, so prompt 2..N should hit the cached 2048 block; the per-task
    // list changes the prefix per task and cannot. ----
    let filler = " the criterion is stable under the measured distributions and the reviewer signed the checklist without further comment.";
    // The pool rounds partial reuse DOWN to 2048-token blocks (matched /
    // 2048 * 2048) by design, so the SHARED part must itself cross 2048
    // tokens: instruction + option list + filler FIRST, task-specific tail
    // LAST. And the stream interleaves TWO tasks: with per-task lists the
    // instruction line changes at every task switch (no reusable prefix);
    // with the shared union list the first ~2100 tokens are IDENTICAL for
    // every task — that is the product claim under test.
    let long_body: String = filler.repeat(118);
    let tasks: [(&str, &str); 2] = [
        ("perm", PERM_LABELS),
        ("third", "strings, woodwind, brass, percussion"),
    ];
    let cache_rows = [0usize, 1, 0, 1]
        .iter()
        .map(|&ti| {
            let (task, _) = tasks[ti];
            let own = tasks[ti].1;
            // per-task list: the task's OWN option list; shared list: the
            // union for every task.
            let shared_head = |labels: &str| -> Vec<i32> {
                let txt = format!(
                    "Classify the text. Answer with exactly one of: {}\n\nText: {}",
                    labels, long_body
                );
                tok.encode(&txt).expect("encode").into_iter().map(|x| x as i32).collect()
            };
            let per_task_ids = {
                let mut v = shared_head(own);
                v.extend(tok.encode(&format!(" tail for {task}")).expect("encode").into_iter().map(|x| x as i32));
                v
            };
            let shared_ids = {
                let mut v = shared_head(UNION_LABELS);
                v.extend(tok.encode(&format!(" tail for {task}")).expect("encode").into_iter().map(|x| x as i32));
                v
            };
            (task.to_string(), per_task_ids, shared_ids)
        })
        .collect::<Vec<_>>();
    let run_stream = |name: &str, pick: usize| -> serde_json::Value {
        let mut pool = PrefixPool::default();
        let scope = CacheScope {
            actor: "l-g5-bench".to_string(),
            epoch: "e1".to_string(),
        };
        let mut hits = Vec::new();
        for (i, (task, per_task, shared)) in cache_rows.iter().enumerate() {
            let p = if pick == 0 { per_task } else { shared };
            let t0 = std::time::Instant::now();
            let (_, matched) = pool
                .generate(model, p, 1, None, s, Some(scope.clone()), false)
                .expect("pool generate");
            let wall = t0.elapsed().as_secs_f64();
            hits.push(serde_json::json!({
                "prompt_i": i,
                "task": task,
                "prompt_tokens": p.len(),
                "matched_prefix": matched,
                "hit_rate": matched as f64 / p.len() as f64,
                "wall_ms": wall * 1e3,
            }));
        }
        serde_json::json!({ "shape": name, "prompts": hits })
    };
    let cache_rows_json = vec![
        run_stream("per_task", 0),
        run_stream("shared_union", 1),
    ];

    serde_json::json!({
        "mode": "prompt-shape",
        "rounds": rounds,
        "prompt_shapes": shape_stats,
        "prefill_walls": walls,
        "kv_bytes": kv,
        "prefix_cache": cache_rows_json,
        "gate": "shared legal only if penalty <= 10% of per-task prefill wall AND 0 added bytes per request beyond the shared prefix",
    })
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let mut mode = "decode".to_string();
    let mut out = String::new();
    let mut rounds = 5usize;
    let mut max_tokens = 48usize;
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--mode" => {
                mode = args[i + 1].clone();
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
            "--max-tokens" => {
                max_tokens = args[i + 1].parse().expect("max-tokens");
                i += 1;
            }
            other => {
                eprintln!("unknown arg {other}");
                std::process::exit(2);
            }
        }
        i += 1;
    }
    eprintln!("qwen_fused_bench — Tier A measured numbers + L-G5 (mode {mode})");
    let Some(snap) = snapshot_dir() else {
        eprintln!("no Qwen3 snapshot (set QWEN3_SNAPSHOT)");
        std::process::exit(1);
    };
    let Ok(s) = gpu() else {
        eprintln!("no Metal device");
        std::process::exit(1);
    };
    let (source, ps) = power_facts();
    eprintln!("power: {ps}");
    let model = Qwen3::load(&snap).expect("model loads");
    let tok = ByteLevelBpe::load(&snap).expect("tokenizer loads");

    let payload = match mode.as_str() {
        "decode" => run_decode(&model, &tok, s, rounds, max_tokens),
        "rank" => run_rank(&model, &tok, s, rounds),
        "prompt-shape" => run_prompt_shape(&model, &tok, s, rounds),
        other => {
            eprintln!("unknown mode {other}");
            std::process::exit(2);
        }
    };

    let contaminated = source != "AC";
    let doc = serde_json::json!({
        "contract": "nursery.fused-bench.v1",
        "when_utc": chrono_utc(),
        "model": "mlx-community/Qwen3-0.6B-4bit",
        "mode": mode,
        "power": { "source": source, "line": ps, "contaminated": contaminated },
        "perf_gate_note": if contaminated {
            "POWER-CONTAMINATED — non-baseline (ADR 0061): the ratios are the measurement and even they are weakened"
        } else {
            "AC — perf numbers are baseline (ADR 0061)"
        },
        "payload": payload,
    });
    let text = serde_json::to_string_pretty(&doc).expect("json");
    if out.is_empty() {
        println!("{text}");
    } else {
        std::fs::write(&out, text).expect("write out");
        eprintln!("wrote {out}");
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
            format!("{y:04}-{m:02}-{dd:02}T{:02}:{:02}:{:02}Z", rem / 3600, (rem % 3600) / 60, rem % 60)
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
