//! The native-surface capability number — the last owed Tier-C repair.
//!
//! The +0.31/+0.47 adapter capability is a PYTHON-path number: measured
//! through `mlx_lm.load(model, adapter_path=...)`. The merge surface refuses
//! a quantized base (correctly — K-G4), so the shipping surface could not
//! carry the claim. This bin closes that with the RUNTIME adapter
//! (`Qwen3::attach_lora`), the no-confound mirror: the SAME 4-bit base, the
//! SAME trained artifact, the SAME rows, greedy generation under the SAME
//! prompt.
//!
//! ROW IDENTITY BY CONSTRUCTION: the rows are read from the cached `untagged`
//! cells (id + gold, in order) and joined to the corpus by id — the same
//! scored split the python arm answered, so the comparison is paired.
//!
//! OUTPUT: `<out>/<arm>__<task>.jsonl` in the cache's own schema
//! (`{id, gold, completion, pred_strict, pred_legacy}`), so
//! `tool/nursery/fast_score.py --completions <out> --eval-rows all` scores it
//! with the ONE scorer definition. The per-row agreement with the python
//! arm's cached completion is computed here and printed — the cross-surface
//! greedy-agreement number — but the GATE is the accuracy bar frozen in
//! `RESULTS-native-surface-2026-10-27.md` BEFORE this ran.
//!
//! PERF NON-CLAIM (the adapter law): a model with a runtime adapter runs the
//! imperative path (the declared plan does not emit the delta ops, so it is
//! refused while an adapter is attached). Every wall clock below is an
//! imperative-path number; no throughput claim is made through this surface.
//!
//! Usage:
//!   qwen_adapter_surface [--tasks perm,veto] [--adapter FILE] [--scale 20.0]
//!                        [--cache-dir DIR] [--out DIR] [--arm nativeadapter]
//!                        [--max-tokens 64] [--snapshot-dir DIR]

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::time::Instant;

use mlx_native::bpe::ByteLevelBpe;
use mlx_native::mlx;
use mlx_native::power;
use mlx_native::qwen::Qwen3;

const BASE_PROMPT: &str =
    "Classify the text. Answer with exactly one of: {labels}\n\nText: {text}\nAnswer:";

struct TaskSpec {
    name: &'static str,
    file: &'static str,
    labels: &'static [&'static str],
}

const TASKS: [TaskSpec; 2] = [
    TaskSpec {
        name: "perm",
        file: "perm_corpus_clause.jsonl",
        labels: &["allow_once", "abstain"],
    },
    TaskSpec {
        name: "veto",
        file: "veto_branch_dataset.jsonl",
        labels: &[
            "no_grant",
            "destructive_op",
            "outside_workspace",
            "secret_path",
        ],
    },
];

struct Args {
    tasks: Vec<String>,
    adapter: PathBuf,
    scale: f32,
    cache_dir: PathBuf,
    out: PathBuf,
    arm: String,
    max_tokens: usize,
    snapshot_dir: Option<PathBuf>,
    reference_arm: String,
}

fn usage() -> String {
    "qwen_adapter_surface — the native-surface capability number (runtime LoRA)\n\n\
     Options:\n\
     \x20 --tasks perm,veto      which tasks to run (default both)\n\
     \x20 --adapter FILE         the mlx-lm adapter artifact\n\
     \x20                         (default: the untagged arm, the reference)\n\
     \x20 --scale F              the adapter scale (default 20.0 — the trainer's\n\
     \x20                         lora_parameters.scale)\n\
     \x20 --cache-dir DIR        the cached completions whose <ref>__<task>.jsonl\n\
     \x20                         rows define row identity (default the durable\n\
     \x20                         2026-10-21 copy)\n\
     \x20 --reference-arm NAME   which cached arm's rows to replay (default untagged)\n\
     \x20 --out DIR              where <arm>__<task>.jsonl lands\n\
     \x20 --arm NAME             the output arm name (default nativeadapter)\n\
     \x20 --max-tokens N         the generation cap (default 64, the run's cap)\n\
     \x20 --snapshot-dir DIR     pin the checkpoint directory\n\
     -h, --help                this text\n"
        .to_string()
}

fn parse_args() -> Result<Args, String> {
    let mut a = Args {
        tasks: vec!["perm".into(), "veto".into()],
        adapter: PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(
            "../../bench/nursery/experiments/adapter-conditioning-2026-10-21/adapter_untagged/adapters.safetensors",
        ),
        scale: 20.0,
        cache_dir: PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(
            "../../bench/nursery/experiments/adapter-conditioning-2026-10-21/completions",
        ),
        out: PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../bench/nursery/experiments/native-surface-2026-10-27/completions"),
        arm: "nativeadapter".to_string(),
        max_tokens: 64,
        snapshot_dir: None,
        reference_arm: "untagged".to_string(),
    };
    let argv: Vec<String> = std::env::args().collect();
    let mut i = 1;
    while i < argv.len() {
        match argv[i].as_str() {
            "--tasks" => {
                a.tasks = arg_value(&argv, i)?
                    .split(',')
                    .map(|s| s.trim().to_string())
                    .filter(|s| !s.is_empty())
                    .collect();
                i += 1;
            }
            "--adapter" => {
                a.adapter = PathBuf::from(arg_value(&argv, i)?);
                i += 1;
            }
            "--scale" => {
                a.scale = arg_value(&argv, i)?
                    .parse()
                    .map_err(|e| format!("--scale: {e}"))?;
                i += 1;
            }
            "--cache-dir" => {
                a.cache_dir = PathBuf::from(arg_value(&argv, i)?);
                i += 1;
            }
            "--reference-arm" => {
                a.reference_arm = arg_value(&argv, i)?;
                i += 1;
            }
            "--out" => {
                a.out = PathBuf::from(arg_value(&argv, i)?);
                i += 1;
            }
            "--arm" => {
                a.arm = arg_value(&argv, i)?;
                i += 1;
            }
            "--max-tokens" => {
                a.max_tokens = arg_value(&argv, i)?
                    .parse()
                    .map_err(|e| format!("--max-tokens: {e}"))?;
                i += 1;
            }
            "--snapshot-dir" => {
                a.snapshot_dir = Some(PathBuf::from(arg_value(&argv, i)?));
                i += 1;
            }
            "-h" | "--help" => {
                println!("{}", usage());
                std::process::exit(0);
            }
            other => return Err(format!("unknown argument: {other}")),
        }
        i += 1;
    }
    Ok(a)
}

fn arg_value(argv: &[String], i: usize) -> Result<String, String> {
    argv.get(i + 1)
        .cloned()
        .ok_or_else(|| format!("{} needs a value", argv[i]))
}

fn snapshot(fragment: &str, pinned: Option<&Path>) -> Option<PathBuf> {
    if let Some(p) = pinned {
        return if p.is_dir() { Some(p.to_path_buf()) } else { None };
    }
    for var in ["LAYA_MTP_SNAPSHOT_DIR", "QWEN3_TARGET_SNAPSHOT"] {
        if let Some(dir) = std::env::var_os(var) {
            let p = PathBuf::from(dir);
            if p.is_dir() {
                return Some(p);
            }
        }
    }
    let home = std::env::var("HOME").ok()?;
    let hub = Path::new(&home).join(".cache/huggingface/hub");
    for e in std::fs::read_dir(hub).ok()?.flatten() {
        if e.file_name().to_string_lossy().contains(fragment) {
            for s in std::fs::read_dir(e.path().join("snapshots")).ok()?.flatten() {
                let p = s.path();
                if p.is_dir() && p.join("config.json").is_file() {
                    return Some(p);
                }
            }
        }
    }
    None
}

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

/// The reference's cached cell: (id, gold, completion) in order.
fn load_reference_cell(cache_dir: &Path, arm: &str, task: &str) -> Result<Vec<(String, String, String)>, String> {
    let path = cache_dir.join(format!("{arm}__{task}.jsonl"));
    let text = std::fs::read_to_string(&path).map_err(|e| format!("{}: {e}", path.display()))?;
    let mut rows = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let v: serde_json::Value =
            serde_json::from_str(line).map_err(|e| format!("{}: {e}", path.display()))?;
        rows.push((
            v.get("id").and_then(|i| i.as_str()).unwrap_or_default().to_string(),
            v.get("gold").and_then(|g| g.as_str()).unwrap_or_default().to_string(),
            v.get("completion").and_then(|c| c.as_str()).unwrap_or_default().to_string(),
        ));
    }
    if rows.is_empty() {
        return Err(format!("{}: no rows", path.display()));
    }
    Ok(rows)
}

/// Corpus text by id (the `text` field; the gold cross-check uses `kind`).
fn corpus_by_id(data_dir: &Path, file: &str) -> Result<BTreeMap<String, (String, String)>, String> {
    let path = data_dir.join(file);
    let text = std::fs::read_to_string(&path).map_err(|e| format!("{}: {e}", path.display()))?;
    let mut map = BTreeMap::new();
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let v: serde_json::Value =
            serde_json::from_str(line).map_err(|e| format!("{}: {e}", path.display()))?;
        let id = v.get("id").and_then(|i| i.as_str()).unwrap_or_default().to_string();
        let body = v.get("text").and_then(|t| t.as_str()).unwrap_or_default().trim().to_string();
        let kind = v.get("kind").and_then(|k| k.as_str()).unwrap_or_default().to_string();
        if id.is_empty() || body.is_empty() {
            continue;
        }
        map.insert(id, (body, kind));
    }
    Ok(map)
}

/// The lane's strict scorer (`scoring.extract_label_strict`, ONE definition —
/// this is a byte-copy of the normalise-then-equal rule; the JSONL this bin
/// writes carries the SAME fields the run writes so `fast_score.py` can
/// re-derive and cross-check them).
fn extract_label_strict(text: &str, labels: &[&str]) -> Option<String> {
    let s = normalise_completion(text);
    if s.is_empty() {
        return None;
    }
    let low = s.to_lowercase();
    labels.iter().find(|l| low == l.to_lowercase()).map(|l| l.to_string())
}

/// The 2026-10-21 scorer, kept ONLY so the recorded `pred_legacy` field
/// matches the run's schema (never a gate).
fn extract_label_legacy(text: &str, labels: &[&str]) -> Option<String> {
    if text.is_empty() {
        return None;
    }
    let text = if let Some(i) = text.find("</think>") {
        &text[i + "</think>".len()..]
    } else if text.contains("<think>") {
        return None;
    } else {
        text
    };
    let low = text.to_lowercase();
    let mut best: Option<(usize, &str)> = None;
    for lab in labels {
        if let Some(pos) = low.find(&lab.to_lowercase()) {
            if best.is_none() || pos < best.unwrap().0 {
                best = Some((pos, lab));
            }
        }
    }
    best.map(|(_, l)| l.to_string())
}

fn normalise_completion(text: &str) -> String {
    if text.is_empty() {
        return String::new();
    }
    let text = if let Some(i) = text.find("</think>") {
        &text[i + "</think>".len()..]
    } else if text.contains("<think>") {
        return String::new();
    } else {
        text
    };
    text.trim().trim_matches('.').trim().to_string()
}

fn main() {
    let args = match parse_args() {
        Ok(a) => a,
        Err(e) => {
            eprintln!("qwen_adapter_surface: {e}\n\n{}", usage());
            std::process::exit(2);
        }
    };

    let facts = power::facts();
    let ma = charge_current_ma();
    eprintln!(
        "power: {} | charge current (ioreg Amperage): {ma} mA",
        facts.describe()
    );

    let metallib =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        let _ = mlx::set_metallib_path(&metallib);
    }
    let s = mlx::gpu().expect("Metal device");
    let model_dir = snapshot("Qwen3-0.6B-4bit", args.snapshot_dir.as_deref())
        .expect("checkpoint snapshot (Qwen3-0.6B-4bit) absent");
    let t0 = Instant::now();
    let mut model = Qwen3::load(&model_dir).expect("the model loads");
    let tokenizer = ByteLevelBpe::load(&model_dir)
        .or_else(|_| ByteLevelBpe::load_tokenizer_json(&model_dir))
        .expect("the tokenizer loads");
    let base_identity = model.weight_identity();
    let applied = model
        .attach_lora(&args.adapter, args.scale, s)
        .expect("the adapter attaches to the quantized base");
    eprintln!(
        "model: {} ({}L h{} V{}) | loaded in {:.1}s | runtime-lora: {applied} pairs, scale {} | identity moved: {}",
        model_dir.file_name().unwrap().to_string_lossy(),
        model.cfg.layers,
        model.cfg.hidden_size,
        model.cfg.vocab,
        t0.elapsed().as_secs_f64(),
        args.scale,
        model.weight_identity() != base_identity
    );
    if !model.has_runtime_lora() {
        eprintln!("REFUSAL: no runtime adapter attached — this bin measures the ADAPTER surface");
        std::process::exit(2);
    }

    let mut eos: Vec<i32> = Vec::new();
    for c in ["<|endoftext|>", "<|im_end|>"] {
        if let Some(id) = tokenizer.added_id(c) {
            eos.push(id as i32);
        }
    }

    let pkg_root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("..").join("..");
    let data_dir = pkg_root.join("bench/nursery/data");
    std::fs::create_dir_all(&args.out).expect("out dir");

    let mut summary = serde_json::Map::new();
    summary.insert(
        "adapter".into(),
        serde_json::json!({
            "path": args.adapter.display().to_string(),
            "scale": args.scale,
            "pairs": applied,
            "digest_prefix": model.weight_identity()[..16].to_string(),
        }),
    );
    summary.insert(
        "power".into(),
        serde_json::json!({
            "facts": facts.describe(),
            "charge_current_ma": ma,
            "note": "accuracy arm: no perf claim through this surface (adapter law: imperative path)",
        }),
    );

    for spec in TASKS.iter() {
        if !args.tasks.iter().any(|t| t == spec.name) {
            continue;
        }
        let reference = load_reference_cell(&args.cache_dir, &args.reference_arm, spec.name)
            .expect("the reference cell loads");
        let corpus = corpus_by_id(&data_dir, spec.file).expect("the corpus loads");
        let labels: Vec<&str> = spec.labels.to_vec();

        let mut out_lines = String::new();
        let (mut agree, mut strict_correct, mut t_gen) = (0usize, 0usize, 0.0f64);
        for (rid, gold, ref_completion) in &reference {
            let Some((body, corpus_kind)) = corpus.get(rid) else {
                panic!("{}/{}: id not in corpus", spec.name, rid);
            };
            assert_eq!(corpus_kind, gold, "{}/{}: gold drift vs corpus", spec.name, rid);
            let base = BASE_PROMPT
                .replace("{labels}", &labels.join(", "))
                .replace("{text}", body);
            let prompt = format!(
                "<|im_start|>user\n{base}<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
            );
            let ids: Vec<i32> = tokenizer
                .encode(&prompt)
                .expect("prompt encodes")
                .into_iter()
                .map(|t| t as i32)
                .collect();
            let t0 = Instant::now();
            let out = model
                .generate_greedy(&ids, args.max_tokens, Some(eos.as_slice()), s)
                .unwrap_or_else(|e| panic!("{}/{}: generation: {}", spec.name, rid, e.0));
            t_gen += t0.elapsed().as_secs_f64();
            let cont: Vec<u32> = out[ids.len()..].iter().map(|&t| t as u32).collect();
            let raw = tokenizer.decode(&cont).expect("continuation decodes");
            // The cache's schema: stripped, capped at 200 chars (the run's
            // own storage cap).
            let completion: String = raw
                .replace("<|im_end|>", "")
                .replace("<|endoftext|>", "")
                .trim()
                .chars()
                .take(200)
                .collect();
            let pred_strict = extract_label_strict(&completion, &labels);
            let pred_legacy = extract_label_legacy(&completion, &labels);
            if pred_strict.as_deref() == Some(gold.as_str()) {
                strict_correct += 1;
            }
            // Cross-surface greedy agreement on the SAME row (reported, not
            // gated — the gate is the accuracy bar).
            if completion.trim() == ref_completion.trim() {
                agree += 1;
            }
            out_lines.push_str(
                &serde_json::json!({
                    "id": rid,
                    "gold": gold,
                    "completion": completion,
                    "pred_strict": pred_strict,
                    "pred_legacy": pred_legacy,
                })
                .to_string(),
            );
            out_lines.push('\n');
        }
        let cell_path = args.out.join(format!("{}__{}.jsonl", args.arm, spec.name));
        std::fs::write(&cell_path, &out_lines).expect("cell writes");
        let n = reference.len();
        eprintln!(
            "{}: {n} rows | strict {}/{} = {:.4} | python-completion agreement {}/{} = {:.4} | gen wall {:.1}s",
            spec.name,
            strict_correct,
            n,
            strict_correct as f64 / n as f64,
            agree,
            n,
            agree as f64 / n as f64,
            t_gen
        );
        summary.insert(
            spec.name.to_string(),
            serde_json::json!({
                "rows": n,
                "strict_correct": strict_correct,
                "strict_accuracy": strict_correct as f64 / n as f64,
                "python_completion_agreement": agree as f64 / n as f64,
                "cell": cell_path.display().to_string(),
            }),
        );
    }

    println!(
        "{}",
        serde_json::to_string_pretty(&serde_json::Value::Object(summary)).expect("summary json")
    );
}
