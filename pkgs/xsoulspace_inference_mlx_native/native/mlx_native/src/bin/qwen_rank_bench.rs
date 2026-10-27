//! L-G6 bench — RANK the legal labels vs GENERATE free text, on the SAME rows.
//!
//! The frozen gate (MTP-GATES.md Part 4, L-G6) asks one question: can the
//! legal labels be RANKED instead of GENERATED? `ranked(base) >= the
//! `untagged` adapter accuracy - 0.05` on BOTH tasks ⇒ the LoRA line is not
//! bought.
//!
//! WHAT THIS BENCH MEASURES (and what it does NOT):
//!
//!   * RANKING cost per prompt: one shared prompt prefill + one short
//!     forward per legal label (`mlx_native::qwen_rank`).
//!   * GENERATION cost per prompt: the lane's own greedy path
//!     (`Qwen3::generate_greedy`, EOS stop) on the SAME prompt ids.
//!   * The RATIO of the two. Absolute ms are NON-CLAIMS on this box (the
//!     same prebuilt binary took 53 s on a quiet box and 4 m 47 s on a
//!     loaded one); the RATIO is the measurement, and the A/B is
//!     INTERLEAVED (the cell order rotates per row/repetition) so thermal
//!     drift cannot silently favour one arm.
//!   * RANKING accuracy vs GENERATION accuracy on the SAME items, under
//!     BOTH length normalizations (sum and mean), plus how often the two
//!     normalizations DISAGREE. If they never disagree on this sample,
//!     length normalization is UNTESTED by this sample and is reported as
//!     such — not as "the normalization does not matter".
//!
//! MLX IS LAZY: every timed arm forces the real output (the ranking's
//! log-probability readback and the generation's per-step argmax readback),
//! so the timings are execution, not graph construction. A dummy eval
//! measured a 28.7x error in this lane (2026-10-20).
//!
//! POWER: perf numbers without a power state are non-claims. The power
//! state and the REAL charge current (ioreg `Amperage`, not the `pmset`
//! source flag) are printed beside every number and carried in the JSON.
//!
//! ROWS: by default the SAME scored rows the lane's adapter arms used —
//! the nursery corpora (`perm_corpus_clause.jsonl`, `veto_branch_dataset.jsonl`),
//! the SAME deterministic split (sha256(id) % 100 < 25 ⇒ test) and the SAME
//! first-N-of-the-test-rows truncation. The prompt is the lane's own
//! `BASE_PROMPT`, rendered through the Qwen3 chat template for one user
//! turn with `enable_thinking=False` (verified against the snapshot's
//! `tokenizer_config.json` on 2026-10-21). `--chat none` gives the raw
//! `BASE_PROMPT` instead (the shape the Python `rank_labels.py` arm uses).
//!
//! BOUNDARY: the scored continuation is the BARE label by default. The
//! lane's own cached completions are bare labels (`allow_once`, not
//! ` allow_once`), so a leading space would score a string the model is
//! never asked to produce. `--boundary space|newline` scores the other
//! boundaries for comparison; the boundary-mismatch count is reported either
//! way.
//!
//! OUTPUT: the human-readable report goes to STDERR; a machine-readable
//! JSON summary goes to STDOUT (and to `--out` when given), so stdout can
//! be piped straight into a parser.
//!
//! Usage:
//!   qwen_rank_bench [--prompts N] [--prompts-file FILE] [--labels a,b,c]
//!                    [--max-labels N] [--reps N] [--model-fragment FRAG]
//!                    [--out FILE] [--tasks perm,veto] [--chat qwen3|none]
//!                    [--boundary space|none|newline] [--norm sum|mean]
//!                    [--max-tokens N] [--snapshot-dir DIR]
//!
//! Env: LAYA_MTP_SNAPSHOT_DIR / QWEN3_TARGET_SNAPSHOT pin the checkpoint.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::time::Instant;

use mlx_native::bpe::ByteLevelBpe;
use mlx_native::mlx;
use mlx_native::power;
use mlx_native::qwen::Qwen3;
use mlx_native::qwen_rank as rank;

/// The lane's prompt template (verbatim from
/// `tool/nursery/adapter_conditioning.py`).
const BASE_PROMPT: &str =
    "Classify the text. Answer with exactly one of: {labels}\n\nText: {text}\nAnswer:";

/// The `untagged` adapter's scored accuracy per task (MTP-GATES.md Part 4:
/// "the reference number these gates are measured against"). These are the
/// NUMBERS a no-training path has to approach.
const REFERENCE_UNTAGGED: [(&str, f64); 2] = [("perm", 0.8733333333333333), ("veto", 0.78)];

/// The frozen gate's margin (MTP-GATES.md Part 4, L-G6).
const GATE_MARGIN: f64 = 0.05;

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

struct Row {
    id: String,
    gold: String,
    text: String,
    labels: Vec<String>,
}

struct Args {
    prompts: usize,
    prompts_file: Option<PathBuf>,
    labels: Option<Vec<String>>,
    max_labels: usize,
    reps: usize,
    model_fragment: String,
    out: Option<PathBuf>,
    tasks: Vec<String>,
    chat: bool,
    boundary: rank::ContinuationBoundary,
    norm: rank::LengthNormalization,
    max_tokens: usize,
    snapshot_dir: Option<PathBuf>,
    adapter: Option<PathBuf>,
    adapter_scale: f32,
    dump_rows: Option<PathBuf>,
}

fn usage() -> String {
    "qwen_rank_bench — L-G6: rank the legal labels vs generate free text\n\n\
     Usage: qwen_rank_bench [options]\n\n\
     Options:\n\
     \x20 --prompts N            scored rows PER TASK (default 150 — the lane's\n\
     \x20                         scored-set size)\n\
     \x20 --prompts-file FILE    a JSONL file of {prompt, gold, labels?} rows\n\
     \x20                         (overrides the nursery corpora)\n\
     \x20 --labels a,b,c         override the legal label set for every row\n\
     \x20 --max-labels N         cap the ranked candidates per row (the prompt\n\
     \x20                         still names the FULL legal set; the gate must\n\
     \x20                         be run without this flag)\n\
     \x20 --reps N               timed repetitions (default 3; the median is\n\
     \x20                         reported)\n\
     \x20 --model-fragment FRAG  checkpoint fragment under the HF cache\n\
     \x20                         (default Qwen3-0.6B-4bit)\n\
     \x20 --tasks perm,veto      which corpora to run (default both)\n\
     \x20 --chat qwen3|none      render the Qwen3 chat template (default qwen3)\n\
     \x20 --boundary none|space|newline  the scored continuation's boundary\n\
     \x20                         (default none — the BARE label, which is what\n\
     \x20                         the lane's cached completions actually emit)\n\
     \x20 --norm sum|mean        the PRIMARY length normalization of the argmax\n\
     \x20                         (default mean; both are always reported)\n\
     \x20 --max-tokens N         the generation cap (default 16)\n\
     \x20 --out FILE             write the JSON summary here as well\n\
     \x20 --adapter FILE         rank+generate UNDER this runtime-LoRA adapter
     \x20                         (mlx-lm artifact; scale from --adapter-scale)
     \x20 --adapter-scale F       the adapter scale (default 20.0)
     \x20 --dump-rows FILE        per-row per-label records (span ids + sums)\n\
     \x20                         for EVERY row of rep 0 — the cross-engine read\n\
     \x20 --snapshot-dir DIR     pin the checkpoint directory\n\
     -h, --help                this text\n\n\
     The human report goes to STDERR; the JSON summary goes to STDOUT.\n\n\
     Env: LAYA_MTP_SNAPSHOT_DIR, QWEN3_TARGET_SNAPSHOT"
        .to_string()
}

fn parse_args() -> Result<Args, String> {
    let mut a = Args {
        prompts: 150,
        prompts_file: None,
        labels: None,
        max_labels: 0,
        reps: 3,
        model_fragment: "Qwen3-0.6B-4bit".to_string(),
        out: None,
        tasks: vec!["perm".to_string(), "veto".to_string()],
        chat: true,
        boundary: rank::ContinuationBoundary::NoSpace,
        norm: rank::LengthNormalization::Mean,
        max_tokens: 16,
        snapshot_dir: None,
        adapter: None,
        adapter_scale: 20.0,
        dump_rows: None,
    };
    let argv: Vec<String> = std::env::args().collect();
    let mut i = 1;
    while i < argv.len() {
        match argv[i].as_str() {
            "--prompts" => {
                a.prompts = arg_value(&argv, i)?
                    .parse()
                    .map_err(|e| format!("--prompts: {e}"))?;
                i += 1;
            }
            "--prompts-file" => {
                a.prompts_file = Some(PathBuf::from(arg_value(&argv, i)?));
                i += 1;
            }
            "--labels" => {
                a.labels = Some(
                    arg_value(&argv, i)?
                        .split(',')
                        .map(|s| s.trim().to_string())
                        .filter(|s| !s.is_empty())
                        .collect(),
                );
                i += 1;
            }
            "--max-labels" => {
                a.max_labels = arg_value(&argv, i)?
                    .parse()
                    .map_err(|e| format!("--max-labels: {e}"))?;
                i += 1;
            }
            "--reps" => {
                a.reps = arg_value(&argv, i)?
                    .parse()
                    .map_err(|e| format!("--reps: {e}"))?;
                i += 1;
            }
            "--model-fragment" => {
                a.model_fragment = arg_value(&argv, i)?;
                i += 1;
            }
            "--out" => {
                a.out = Some(PathBuf::from(arg_value(&argv, i)?));
                i += 1;
            }
            "--tasks" => {
                a.tasks = arg_value(&argv, i)?
                    .split(',')
                    .map(|s| s.trim().to_string())
                    .filter(|s| !s.is_empty())
                    .collect();
                i += 1;
            }
            "--chat" => {
                a.chat = match arg_value(&argv, i)?.as_str() {
                    "qwen3" => true,
                    "none" | "raw" => false,
                    other => return Err(format!("--chat: {other} (qwen3|none)")),
                };
                i += 1;
            }
            "--boundary" => {
                a.boundary = rank::ContinuationBoundary::parse(&arg_value(&argv, i)?)
                    .ok_or_else(|| "--boundary: space|none|newline".to_string())?;
                i += 1;
            }
            "--norm" => {
                a.norm = rank::LengthNormalization::parse(&arg_value(&argv, i)?)
                    .ok_or_else(|| "--norm: sum|mean".to_string())?;
                i += 1;
            }
            "--max-tokens" => {
                a.max_tokens = arg_value(&argv, i)?
                    .parse()
                    .map_err(|e| format!("--max-tokens: {e}"))?;
                i += 1;
            }
            "--adapter" => {
                a.adapter = Some(PathBuf::from(arg_value(&argv, i)?));
                i += 1;
            }
            "--dump-rows" => {
                a.dump_rows = Some(PathBuf::from(arg_value(&argv, i)?));
                i += 1;
            }
            "--adapter-scale" => {
                a.adapter_scale = arg_value(&argv, i)?
                    .parse()
                    .map_err(|e| format!("--adapter-scale: {e}"))?;
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

/// The value of the flag at `i` (the flag's own value is `argv[i + 1]`).
fn arg_value(argv: &[String], i: usize) -> Result<String, String> {
    argv.get(i + 1)
        .cloned()
        .ok_or_else(|| format!("{} needs a value", argv[i]))
}

/// The cached HF-hub snapshot dir for a model-name fragment.
fn snapshot(fragment: &str, pinned: Option<&Path>) -> Option<PathBuf> {
    if let Some(p) = pinned {
        return if p.is_dir() {
            Some(p.to_path_buf())
        } else {
            None
        };
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

/// The real charge current in mA (strongly positive = actually charging).
/// `pmset`'s "AC Power" is the SOURCE, not the current.
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

/// `int(sha256(id).hexdigest(), 16) % 100` — the lane's deterministic split.
fn id_hash_mod100(id: &str) -> u32 {
    let hex = mlx_native::nursery::sha256_hex(id.as_bytes());
    let mut acc: u32 = 0;
    for c in hex.chars() {
        let d = c.to_digit(16).unwrap_or(0);
        acc = (acc * 16 + d) % 100;
    }
    acc
}

/// The lane's strict scorer: the stripped completion must EQUAL a label.
fn extract_label_strict(text: &str, labels: &[String]) -> Option<String> {
    if text.is_empty() {
        return None;
    }
    let t = if let Some(i) = text.find("</think>") {
        &text[i + "</think>".len()..]
    } else if text.contains("<think>") {
        return None;
    } else {
        text
    };
    let s = t.trim().trim_matches('.').trim().to_lowercase();
    labels
        .iter()
        .find(|l| l.to_lowercase() == s)
        .map(|l| l.to_string())
}

fn build_prompt(row: &Row, chat: bool) -> String {
    let base = BASE_PROMPT
        .replace("{labels}", &row.labels.join(", "))
        .replace("{text}", &row.text);
    if chat {
        // The Qwen3 template rendered for ONE user turn with
        // enable_thinking=False (the snapshot's tokenizer_config.json).
        format!(
            "<|im_start|>user\n{base}<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
        )
    } else {
        base
    }
}

/// Load the nursery corpus for one task and take the lane's scored rows.
fn load_task_rows(
    data_dir: &Path,
    spec: &TaskSpec,
    limit: usize,
    override_labels: Option<&Vec<String>>,
) -> Result<Vec<Row>, String> {
    let path = data_dir.join(spec.file);
    let text = std::fs::read_to_string(&path).map_err(|e| format!("{}: {e}", path.display()))?;
    let mut rows: Vec<Row> = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let v: serde_json::Value =
            serde_json::from_str(line).map_err(|e| format!("{}: {e}", path.display()))?;
        let kind = v
            .get("kind")
            .and_then(|k| k.as_str())
            .unwrap_or_default()
            .to_string();
        let body = v
            .get("text")
            .and_then(|t| t.as_str())
            .unwrap_or_default()
            .trim()
            .to_string();
        if body.is_empty() {
            continue;
        }
        let labels: Vec<String> = match override_labels {
            Some(l) => l.clone(),
            None => {
                if !spec.labels.contains(&kind.as_str()) {
                    continue;
                }
                spec.labels.iter().map(|s| s.to_string()).collect()
            }
        };
        rows.push(Row {
            id: v
                .get("id")
                .and_then(|i| i.as_str())
                .unwrap_or_default()
                .to_string(),
            gold: kind,
            text: body,
            labels,
        });
    }
    // The lane's split: sha256(id) % 100 < 25 ⇒ the TEST rows, in file order.
    let test: Vec<Row> = rows
        .into_iter()
        .filter(|r| id_hash_mod100(&r.id) < 25)
        .collect();
    let mut test = test;
    test.truncate(limit);
    Ok(test)
}

/// Load rows from a JSONL file of {prompt, gold, labels?}.
fn load_prompt_file(
    path: &Path,
    limit: usize,
    override_labels: Option<&Vec<String>>,
) -> Result<Vec<Row>, String> {
    let text = std::fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let mut rows: Vec<Row> = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let v: serde_json::Value =
            serde_json::from_str(line).map_err(|e| format!("{}: {e}", path.display()))?;
        let prompt = v
            .get("prompt")
            .and_then(|p| p.as_str())
            .unwrap_or_default()
            .to_string();
        if prompt.is_empty() {
            continue;
        }
        let labels: Vec<String> = match v.get("labels").and_then(|l| l.as_array()) {
            Some(a) => a
                .iter()
                .filter_map(|x| x.as_str().map(|s| s.to_string()))
                .collect(),
            None => override_labels.cloned().unwrap_or_default(),
        };
        rows.push(Row {
            id: v
                .get("id")
                .and_then(|i| i.as_str())
                .unwrap_or_default()
                .to_string(),
            gold: v
                .get("gold")
                .and_then(|g| g.as_str())
                .unwrap_or_default()
                .to_string(),
            text: prompt,
            labels,
        });
    }
    rows.truncate(limit);
    Ok(rows)
}

fn median(v: &mut [f64]) -> f64 {
    v.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    if v.is_empty() {
        0.0
    } else {
        v[v.len() / 2]
    }
}

/// The argmax label under one normalization.
fn argmax_under(scores: &[rank::LabelScore], norm: rank::LengthNormalization) -> Option<String> {
    let mut best: Option<(f32, &str)> = None;
    for s in scores {
        let v = rank::primary_score(s, norm);
        let better = match best {
            None => true,
            Some((bv, _)) => v > bv,
        };
        if better {
            best = Some((v, s.label.as_str()));
        }
    }
    best.map(|(_, l)| l.to_string())
}

/// Per-task accumulators.
#[derive(Default)]
struct TaskStats {
    n: usize,
    ranked_mean_correct: usize,
    ranked_sum_correct: usize,
    gen_correct: usize,
    gen_outside: usize,
    sum_vs_mean_disagreements: usize,
    boundary_mismatches: usize,
    eos_dominant_rows: usize,
    gold_histogram: BTreeMap<String, usize>,
    rank_ms: Vec<f64>,
    gen_ms: Vec<f64>,
    sample_rows: Vec<serde_json::Value>,
}

fn main() {
    let args = match parse_args() {
        Ok(a) => a,
        Err(e) => {
            eprintln!("qwen_rank_bench: {e}\n\n{}", usage());
            std::process::exit(2);
        }
    };
    if args.reps == 0 {
        eprintln!("qwen_rank_bench: --reps must be >= 1");
        std::process::exit(2);
    }

    // ---- power: beside every number ----
    let facts = power::facts();
    let ma = charge_current_ma();
    let power_line = format!(
        "{} | charge current (ioreg Amperage): {ma} mA",
        facts.describe()
    );
    eprintln!("power: {power_line}");
    if ma <= 0 {
        eprintln!(
            "POWER-CONTAMINATED — non-baseline (ADR 0061): no real charge current; \
             the RATIOS below are the measurement, the absolute ms are non-claims"
        );
    }

    // ---- the checkpoint ----
    let metallib =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        let _ = mlx::set_metallib_path(&metallib);
    }
    let s = mlx::gpu().expect("Metal device");
    let model_dir = snapshot(&args.model_fragment, args.snapshot_dir.as_deref())
        .expect("checkpoint snapshot (Qwen3-0.6B-4bit) absent");
    let t0 = Instant::now();
    let mut model = Qwen3::load(&model_dir).expect("the model loads");
    let tokenizer = ByteLevelBpe::load(&model_dir)
        .or_else(|_| ByteLevelBpe::load_tokenizer_json(&model_dir))
        .expect("the tokenizer loads");
    eprintln!(
        "model: {} ({}L h{} V{}) | loaded in {:.1}s",
        model_dir.file_name().unwrap().to_string_lossy(),
        model.cfg.layers,
        model.cfg.hidden_size,
        model.cfg.vocab,
        t0.elapsed().as_secs_f64()
    );
    if let Some(adapter) = &args.adapter {
        let applied = model
            .attach_lora(adapter, args.adapter_scale, s)
            .unwrap_or_else(|e| panic!("--adapter {}: {e}", adapter.display()));
        eprintln!(
            "adapter: {} | {applied} runtime pairs at scale {} | the A/B below is              ranked(adapter) vs generated(adapter) on the same rows",
            adapter.display(),
            args.adapter_scale
        );
    }

    // The EOS ids the generation arm stops on.
    let mut eos_ids: Vec<i32> = Vec::new();
    for c in ["<|endoftext|>", "<|im_end|>"] {
        if let Some(id) = tokenizer.added_id(c) {
            eos_ids.push(id as i32);
        }
    }
    eprintln!("eos stop ids: {eos_ids:?}");

    // ---- the rows ----
    // CARGO_MANIFEST_DIR is `<package>/native/mlx_native`, so TWO levels up
    // is the package root — the directory that holds `bench/nursery/data`.
    // (Three levels up is `pkgs/`, and the corpus is not there.)
    let pkg_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..");
    let data_dir = pkg_root.join("bench/nursery/data");
    let mut task_rows: Vec<(String, Vec<Row>)> = Vec::new();
    if let Some(file) = &args.prompts_file {
        let rows = load_prompt_file(file, args.prompts, args.labels.as_ref())
            .expect("the prompt file loads");
        task_rows.push(("file".to_string(), rows));
    } else {
        for spec in TASKS.iter() {
            if !args.tasks.iter().any(|t| t == spec.name) {
                continue;
            }
            let rows = load_task_rows(&data_dir, spec, args.prompts, args.labels.as_ref())
                .expect("the corpus loads");
            task_rows.push((spec.name.to_string(), rows));
        }
    }
    if task_rows.is_empty() {
        eprintln!("qwen_rank_bench: no rows");
        std::process::exit(2);
    }

    let opts = rank::RankOptions {
        normalization: args.norm,
        boundary: args.boundary,
    };

    let mut stats: BTreeMap<String, TaskStats> = BTreeMap::new();
    let mut dumped_rows: Vec<serde_json::Value> = Vec::new();

    // ---- the interleaved A/B ----
    for rep in 0..args.reps {
        for (task_name, rows) in &task_rows {
            let st = stats.entry(task_name.clone()).or_default();
            for (ri, row) in rows.iter().enumerate() {
                let prompt = build_prompt(row, args.chat);
                let ids: Vec<i32> = tokenizer
                    .encode(&prompt)
                    .unwrap_or_default()
                    .into_iter()
                    .map(|t| t as i32)
                    .collect();
                if ids.is_empty() {
                    continue;
                }
                let mut labels: Vec<String> = row.labels.clone();
                if args.max_labels > 0 && labels.len() > args.max_labels {
                    labels.truncate(args.max_labels);
                }
                let label_refs: Vec<&str> = labels.iter().map(|s| s.as_str()).collect();

                // The A/B order rotates per (rep, row): thermal drift cannot
                // silently favour one arm.
                let rank_first = (rep + ri) % 2 == 0;
                let (rank_ms, gen_ms, outcome, completion) = if rank_first {
                    let tr = Instant::now();
                    let outcome =
                        rank::rank_labels_with(&model, &tokenizer, &prompt, &label_refs, opts, s)
                            .expect("ranking");
                    let rank_ms = tr.elapsed().as_secs_f64() * 1000.0;
                    let tg = Instant::now();
                    let out = model
                        .generate_greedy(&ids, args.max_tokens, Some(eos_ids.as_slice()), s)
                        .expect("generation");
                    let gen_ms = tg.elapsed().as_secs_f64() * 1000.0;
                    let completion = decode_generated(&tokenizer, &out, ids.len(), &eos_ids);
                    (rank_ms, gen_ms, Some(outcome), completion)
                } else {
                    let tg = Instant::now();
                    let out = model
                        .generate_greedy(&ids, args.max_tokens, Some(eos_ids.as_slice()), s)
                        .expect("generation");
                    let gen_ms = tg.elapsed().as_secs_f64() * 1000.0;
                    let tr = Instant::now();
                    let outcome =
                        rank::rank_labels_with(&model, &tokenizer, &prompt, &label_refs, opts, s)
                            .expect("ranking");
                    let rank_ms = tr.elapsed().as_secs_f64() * 1000.0;
                    let completion = decode_generated(&tokenizer, &out, ids.len(), &eos_ids);
                    (rank_ms, gen_ms, Some(outcome), completion)
                };

                let outcome = outcome.expect("the outcome");
                st.rank_ms.push(rank_ms);
                st.gen_ms.push(gen_ms);

                if rep == 0 {
                    let pred_mean = argmax_under(&outcome.scores, rank::LengthNormalization::Mean);
                    let pred_sum = argmax_under(&outcome.scores, rank::LengthNormalization::Sum);
                    let pred_primary = match opts.normalization {
                        rank::LengthNormalization::Mean => pred_mean.clone(),
                        rank::LengthNormalization::Sum => pred_sum.clone(),
                    };
                    st.n += 1;
                    *st.gold_histogram.entry(row.gold.clone()).or_insert(0) += 1;
                    if pred_mean.as_deref() == Some(row.gold.as_str()) {
                        st.ranked_mean_correct += 1;
                    }
                    if pred_sum.as_deref() == Some(row.gold.as_str()) {
                        st.ranked_sum_correct += 1;
                    }
                    if pred_mean != pred_sum {
                        st.sum_vs_mean_disagreements += 1;
                    }
                    st.boundary_mismatches += outcome.boundary_mismatches;
                    if outcome.scores.iter().any(|s| s.eos_dominates) {
                        st.eos_dominant_rows += 1;
                    }
                    let gen_pred = extract_label_strict(&completion, &labels);
                    if gen_pred.is_none() {
                        st.gen_outside += 1;
                    }
                    if gen_pred.as_deref() == Some(row.gold.as_str()) {
                        st.gen_correct += 1;
                    }
                    if args.dump_rows.is_some() {
                        let rec = serde_json::json!({
                            "id": row.id,
                            "gold": row.gold,
                            "ranked_mean": pred_mean,
                            "ranked_sum": pred_sum,
                            "generation_completion": completion,
                            "generation_pred": gen_pred,
                            "scores": outcome.scores.iter().map(|sc| serde_json::json!({
                                "label": sc.label,
                                "sum": sc.sum_logprob,
                                "mean": sc.mean_logprob,
                                "span": sc.tokens,
                                "scored_text": sc.scored_text,
                                "boundary_mismatch": sc.boundary_mismatch,
                            })).collect::<Vec<_>>(),
                        });
                        dumped_rows.push(rec);
                    }
                    if st.sample_rows.len() < 5 {
                        st.sample_rows.push(serde_json::json!({
                            "id": row.id,
                            "gold": row.gold,
                            "ranked_mean": pred_mean,
                            "ranked_sum": pred_sum,
                            "ranked_primary": pred_primary,
                            "generation_completion": completion.chars().take(80).collect::<String>(),
                            "generation_pred": gen_pred,
                            "ranked_scores": outcome.scores.iter().map(|s| serde_json::json!({
                                "label": s.label,
                                "sum": s.sum_logprob,
                                "mean": s.mean_logprob,
                                "tokens": s.tokens.len(),
                                "scored_text": s.scored_text,
                                "boundary_mismatch": s.boundary_mismatch,
                                "eos_dominates": s.eos_dominates,
                            })).collect::<Vec<_>>(),
                        }));
                    }
                }
            }
        }
        eprintln!("rep {rep} done");
    }

    if let Some(dump) = &args.dump_rows {
        let text = dumped_rows
            .iter()
            .map(|r| r.to_string())
            .collect::<Vec<_>>()
            .join("\n");
        std::fs::write(dump, text).expect("dump rows write");
        eprintln!("dumped {} rows to {}", dumped_rows.len(), dump.display());
    }

    // ---- the report ----
    let mut all_rank: Vec<f64> = Vec::new();
    let mut all_gen: Vec<f64> = Vec::new();
    let mut task_json = serde_json::Map::new();
    let mut gate_pass = true;
    let mut gate_known = true;

    for (task_name, st) in &stats {
        let mut row_rank = st.rank_ms.clone();
        let mut row_gen = st.gen_ms.clone();
        let row_rank_med = median(&mut row_rank);
        let row_gen_med = median(&mut row_gen);
        let n = st.n.max(1) as f64;
        let acc_mean = st.ranked_mean_correct as f64 / n;
        let acc_sum = st.ranked_sum_correct as f64 / n;
        let acc_gen = st.gen_correct as f64 / n;
        // The gate's number is the PRIMARY normalization's accuracy (mean by
        // default); the other one is reported beside it, never in place of it.
        let acc_primary = match args.norm {
            rank::LengthNormalization::Mean => acc_mean,
            rank::LengthNormalization::Sum => acc_sum,
        };

        let reference = REFERENCE_UNTAGGED
            .iter()
            .find(|(n, _)| *n == task_name.as_str())
            .map(|(_, a)| *a);
        let threshold = reference.map(|a| a - GATE_MARGIN);
        let passes = threshold.map(|t| acc_primary >= t);
        if let Some(p) = passes {
            if !p {
                gate_pass = false;
            }
        } else {
            gate_known = false;
        }

        eprintln!();
        eprintln!("=== task {task_name} ===");
        eprintln!(
            "rows {} (coverage {n:.3} of the loaded rows) | power: {power_line}",
            st.n
        );
        eprintln!(
            "ranked(base) accuracy: mean-norm {:.4} | sum-norm {:.4} | gold histogram {:?}",
            acc_mean, acc_sum, st.gold_histogram
        );
        eprintln!(
            "generation(base) accuracy: {:.4} | outside the label set: {}",
            acc_gen, st.gen_outside
        );
        eprintln!(
            "sum-vs-mean disagreements: {} | boundary mismatches: {} | rows where EOS beat the label's first token: {}",
            st.sum_vs_mean_disagreements, st.boundary_mismatches, st.eos_dominant_rows
        );
        eprintln!(
            "cost: ranking median {:.1} ms | generation median {:.1} ms | ratio {:.3}",
            row_rank_med,
            row_gen_med,
            row_rank_med / row_gen_med.max(1e-9)
        );
        if st.sum_vs_mean_disagreements == 0 {
            eprintln!(
                "NOTE: sum and mean never disagreed on this sample — length normalization is \
                 UNTESTED by this sample, not shown to be irrelevant."
            );
        }
        if let (Some(r), Some(t)) = (reference, threshold) {
            eprintln!(
                "gate L-G6: ranked(base) [{}-norm] {:.4} vs untagged-adapter reference {:.4} - {:.2} = {:.4} ⇒ {}",
                args.norm.as_str(),
                acc_primary,
                r,
                GATE_MARGIN,
                t,
                if acc_primary >= t { "PASS" } else { "FAIL" }
            );
        } else {
            eprintln!("gate L-G6: no reference number for this task — NOT EVALUATED");
        }

        all_rank.extend(st.rank_ms.iter().copied());
        all_gen.extend(st.gen_ms.iter().copied());

        task_json.insert(
            task_name.clone(),
            serde_json::json!({
                "n": st.n,
                "coverage": st.n as f64 / rows_len_for(task_name, &task_rows).max(1.0),
                "ranked_accuracy_mean": acc_mean,
                "ranked_accuracy_sum": acc_sum,
                "ranked_accuracy_primary": acc_primary,
                "primary_normalization": args.norm.as_str(),
                "generation_accuracy": acc_gen,
                "generation_outside_label_set": st.gen_outside,
                "sum_vs_mean_disagreements": st.sum_vs_mean_disagreements,
                "boundary_mismatches": st.boundary_mismatches,
                "eos_dominant_rows": st.eos_dominant_rows,
                "gold_histogram": st.gold_histogram,
                "reference_untagged_adapter_accuracy": reference,
                "gate_threshold_untagged_minus_0_05": threshold,
                "gate_reading_this_task": match passes {
                    Some(true) => "PASS",
                    Some(false) => "FAIL",
                    None => "NOT_EVALUATED",
                },
                "ranking_ms_median": row_rank_med,
                "generation_ms_median": row_gen_med,
                "ratio_ranking_over_generation": row_rank_med / row_gen_med.max(1e-9),
                "sample_rows": st.sample_rows,
            }),
        );
    }

    let mut rank_all = all_rank.clone();
    let mut gen_all = all_gen.clone();
    let rank_med = median(&mut rank_all);
    let gen_med = median(&mut gen_all);
    let ratio = rank_med / gen_med.max(1e-9);
    eprintln!();
    eprintln!("=== overall ===");
    eprintln!(
        "ranking median {:.1} ms | generation median {:.1} ms | RATIO (ranking / generation) {:.3}",
        rank_med, gen_med, ratio
    );
    eprintln!(
        "gate reading (both tasks): {}",
        if !gate_known {
            "NOT EVALUATED"
        } else if gate_pass {
            "PASS — the LoRA line is NOT bought (evidence, not a product decision)"
        } else {
            "FAIL — generation, and therefore the adapter, is load-bearing"
        }
    );

    let summary = serde_json::json!({
        "bench": "qwen_rank_bench",
        "gate": "L-G6 (MTP-GATES.md Part 4)",
        "model": {
            "fragment": args.model_fragment,
            "snapshot": model_dir.file_name().unwrap().to_string_lossy(),
            "layers": model.cfg.layers,
            "hidden_size": model.cfg.hidden_size,
            "vocab": model.cfg.vocab,
        },
        "power": {
            "describe": facts.describe(),
            "charge_current_ma": ma,
            "charge_current_is_real": ma > 0,
        },
        "config": {
            "prompts_per_task": args.prompts,
            "prompts_file": args.prompts_file.as_ref().map(|p| p.display().to_string()),
            "reps": args.reps,
            "chat": if args.chat { "qwen3" } else { "none" },
            "boundary": args.boundary.as_str(),
            "primary_normalization": args.norm.as_str(),
            "max_labels": args.max_labels,
            "max_generation_tokens": args.max_tokens,
            "tasks": args.tasks,
            "eos_stop_ids": eos_ids,
        },
        "tasks": serde_json::Value::Object(task_json),
        "timing": {
            "ranking_ms_median": rank_med,
            "generation_ms_median": gen_med,
            "ratio_ranking_over_generation": ratio,
            "note": "absolute ms are NON-CLAIMS on this box; the RATIO is the measurement",
        },
        "gate_reading": if !gate_known {
            "NOT_EVALUATED"
        } else if gate_pass {
            "PASS"
        } else {
            "FAIL"
        },
        "non_claims": [
            "absolute ms and tok/s are non-claims without a real charge current; the RATIO is the measurement",
            "one model, one device, one corpus, one split, one seed",
            "the rows are the lane's scored rows (same corpora, same id-hash split, same truncation), rendered through the Qwen3 chat template natively; the reference adapter numbers came from mlx-lm, so engine numerics differ slightly",
            "a PASS is eligibility, never a product decision (MTP-GATES.md Part 4)",
            "sum-vs-mean agreement on this sample does not show that length normalization is irrelevant; it shows this sample did not exercise it",
            "ranking here is NOT batched across candidates: the native engine's forward hardcodes batch 1, so each candidate is one short forward over the shared prefix's KV",
        ],
    });

    let text =
        serde_json::to_string_pretty(&summary).unwrap_or_else(|e| format!("{{\"error\":\"{e}\"}}"));
    println!("{text}");
    if let Some(out) = &args.out {
        if let Some(parent) = out.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        if let Err(e) = std::fs::write(out, format!("{text}\n")) {
            eprintln!("qwen_rank_bench: could not write {}: {e}", out.display());
        }
    }
}

/// The generated text (the completion only, not the prompt).
///
/// The EOS token is NOT part of the completion: `generate_greedy` keeps the
/// EOS token in its output (the HF convention) but mlx-lm — which produced
/// the lane's reference numbers — does not include it in the decoded text.
/// Leaving it in would make every completion `allow_once<|endoftext|>`
/// and therefore a miss under the strict scorer, so it is cut here (at the
/// FIRST EOS, which is where generation stopped).
fn decode_generated(
    tokenizer: &ByteLevelBpe,
    out: &[i32],
    prompt_len: usize,
    eos_ids: &[i32],
) -> String {
    let mut ids: Vec<u32> = Vec::new();
    for &t in out.iter().skip(prompt_len) {
        if eos_ids.contains(&t) {
            break;
        }
        ids.push(t as u32);
    }
    tokenizer.decode(&ids).unwrap_or_default()
}

/// The number of loaded rows for a task (for the coverage print).
fn rows_len_for(task_name: &str, task_rows: &[(String, Vec<Row>)]) -> f64 {
    task_rows
        .iter()
        .find(|(n, _)| n == task_name)
        .map(|(_, r)| r.len() as f64)
        .unwrap_or(0.0)
}
