//! The runtime-LoRA gate: the trained mlx-lm adapter applied UNMERGED on the
//! quantized base, natively — the no-confound mirror of the python path
//! (`mlx_lm.load(model, adapter_path=...)`).
//!
//! The one failure mode this surface exists to prevent is the SILENT
//! no-apply: an adapter that loads, validates, and then never changes a
//! single logit. So the load-bearing assertion here is behavioral: with the
//! adapter attached, the model's logits on a trained prompt MOVE (and a
//! trained prompt's greedy answer lands in the legal label set).
//!
//! Like every artifact gate this SKIPS on a clone that never ran the trainer
//! (the artifact lives under gitignored `bench/`); `QWEN_RUNTIME_LORA_ARTIFACT`
//! points it at any mlx-lm adapter. A gate that skips loudly is still a gate.

use std::path::PathBuf;

use mlx_native::bpe::ByteLevelBpe;
use mlx_native::mlx::{self, Dtype, Stream};
use mlx_native::qwen::{KvCache, Qwen3};
use mlx_native::qwen_rank as rank;

fn stream() -> Option<Stream> {
    let metallib =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        let _ = mlx::set_metallib_path(&metallib);
    }
    mlx::gpu().ok()
}

fn snapshot_dir() -> Option<PathBuf> {
    if let Some(over) = std::env::var_os("QWEN3_SNAPSHOT") {
        let p = PathBuf::from(over);
        return if p.is_dir() { Some(p) } else { None };
    }
    let home = std::env::var_os("HOME")?;
    let hub = PathBuf::from(home).join(".cache/huggingface/hub");
    for entry in std::fs::read_dir(hub).ok()?.flatten() {
        if entry
            .file_name()
            .to_string_lossy()
            .contains("Qwen3-0.6B-4bit")
        {
            if let Ok(snaps) = std::fs::read_dir(entry.path().join("snapshots")) {
                for s in snaps.flatten() {
                    let p = s.path();
                    if p.is_dir() && p.join("config.json").is_file() {
                        return Some(p);
                    }
                }
            }
        }
    }
    None
}

/// The `untagged` arm — the reference the capability numbers are measured
/// against (0.8737 perm / 0.7533 veto on the scored split).
fn artifact_path() -> PathBuf {
    if let Ok(p) = std::env::var("QWEN_RUNTIME_LORA_ARTIFACT") {
        return PathBuf::from(p);
    }
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(
        "../../bench/nursery/experiments/adapter-conditioning-2026-10-21/adapter_untagged/adapters.safetensors",
    )
}

/// The mlx-lm trainer's scale (`lora_parameters.scale` in the artifact's
/// adapter_config.json).
const SCALE: f32 = 20.0;

/// The untagged arm's chat prompt shape (byte-exact Qwen3 template,
/// `enable_thinking=False` — the shape the lane's fixtures pin).
fn chat_prompt(base: &str) -> String {
    format!("<|im_start|>user\n{base}<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n")
}

/// A minimal mlx-lm-format adapter safetensors file: 8-byte LE header length,
/// a JSON header, then raw F32 data. `module` is the target module name, so a
/// refusal test can name a module the model does not have.
fn write_mlx_lm_adapter(path: &std::path::Path, module: &str, r: usize, dim: usize) {
    let a_len = r * dim * 4;
    let b_len = dim * r * 4;
    let mut header = serde_json::Map::new();
    for (name, shape, start) in [
        (format!("{module}.lora_a"), vec![r, dim], 0),
        (format!("{module}.lora_b"), vec![dim, r], a_len),
    ] {
        let mut e = serde_json::Map::new();
        e.insert("dtype".into(), "F32".into());
        e.insert("shape".into(), serde_json::json!(shape));
        e.insert(
            "data_offsets".into(),
            serde_json::json!([start, start + if name.ends_with("a") { a_len } else { b_len }]),
        );
        header.insert(name, serde_json::Value::Object(e));
    }
    let header_json = serde_json::to_string(&header).expect("header json");
    let mut bytes = Vec::new();
    bytes.extend_from_slice(&(header_json.len() as u64).to_le_bytes());
    bytes.extend_from_slice(header_json.as_bytes());
    bytes.extend_from_slice(&vec![0u8; a_len + b_len]);
    std::fs::write(path, bytes).expect("write adapter fixture");
}

#[test]
fn the_runtime_adapter_applies_moves_logits_and_answers_in_set() {
    let Some(s) = stream() else {
        eprintln!("skipping: no Metal device");
        return;
    };
    let Some(snap) = snapshot_dir() else {
        eprintln!("skipping: Qwen3-0.6B-4bit snapshot absent");
        return;
    };
    let artifact = artifact_path();
    if !artifact.is_file() {
        eprintln!(
            "SKIP: no trained adapter at {} (gitignored bench/) — set \
             QWEN_RUNTIME_LORA_ARTIFACT to run this gate",
            artifact.display()
        );
        return;
    }

    let base_model = Qwen3::load(&snap).expect("base loads");
    let mut model = Qwen3::load(&snap).expect("model loads");
    let tokenizer = ByteLevelBpe::load(&snap)
        .or_else(|_| ByteLevelBpe::load_tokenizer_json(&snap))
        .expect("tokenizer loads");

    // (1) attach: every target validated against the real module set.
    let base_identity = model.weight_identity();
    assert!(!model.has_runtime_lora());
    let applied = model
        .attach_lora(&artifact, SCALE, s)
        .expect("the trained adapter attaches to the quantized base");
    assert_eq!(
        applied, 56,
        "the untagged artifact trained 8 layers x 7 linears = 56 pairs; any \
         other count means the loader or the validator drifted"
    );
    assert!(model.has_runtime_lora());
    assert_ne!(
        model.weight_identity(),
        base_identity,
        "a runtime adapter is a different model: the prefix cache must not \
         serve base entries under it"
    );

    // (2) the anti-silent-no-apply check: the adapter MOVES the logits on a
    // trained-shaped prompt.
    let prompt = chat_prompt(
        "Classify the text. Answer with exactly one of: no_grant, destructive_op, \
         outside_workspace, secret_path\n\nText: rm -rf ~/.ssh\nAnswer:",
    );
    let ids: Vec<i32> = tokenizer
        .encode(&prompt)
        .expect("prompt encodes")
        .into_iter()
        .map(|t| t as i32)
        .collect();
    let tokens = mlx::Array::from_data_i32(&ids, &[1, ids.len()]).expect("ids");
    let mut cache_base = KvCache::new(base_model.cfg.layers);
    let logits_base = base_model
        .forward_step(&tokens, &mut cache_base, s)
        .expect("base forward");
    let mut cache_rt = KvCache::new(model.cfg.layers);
    let logits_rt = model
        .forward_step(&tokens, &mut cache_rt, s)
        .expect("adapter forward");
    let b = logits_base
        .astype(Dtype::Float32, s)
        .expect("cast")
        .to_f32_vec(s)
        .expect("base logits");
    let r = logits_rt
        .astype(Dtype::Float32, s)
        .expect("cast")
        .to_f32_vec(s)
        .expect("adapter logits");
    assert_eq!(b.len(), r.len(), "logit shapes diverged");
    let max_delta = b
        .iter()
        .zip(r.iter())
        .map(|(x, y)| (x - y).abs())
        .fold(0.0f32, f32::max);
    assert!(
        max_delta > 1e-3,
        "the runtime adapter moved NO logit (max |delta| = {max_delta}) — the \
         silent no-apply failure mode this gate exists to catch"
    );

    // (3) the capability smoke: greedy generation with the adapter answers in
    // the legal set on a trained-shaped prompt.
    let mut eos: Vec<i32> = Vec::new();
    for c in ["<|endoftext|>", "<|im_end|>"] {
        if let Some(id) = tokenizer.added_id(c) {
            eos.push(id as i32);
        }
    }
    let out = model
        .generate_greedy(&ids, 16, Some(eos.as_slice()), s)
        .expect("greedy decode under the adapter");
    let cont: Vec<u32> = out[ids.len()..].iter().map(|&t| t as u32).collect();
    let continuation = tokenizer.decode(&cont).expect("continuation decodes");
    // A decoded added token appears as its literal text; the lane's completions
    // never contain one, so strip the stop tokens before scoring the answer.
    let stripped = continuation
        .replace("<|im_end|>", "")
        .replace("<|endoftext|>", "");
    let normalized = stripped.trim().trim_matches('.').trim().to_lowercase();
    assert!(
        [
            "no_grant",
            "destructive_op",
            "outside_workspace",
            "secret_path"
        ]
        .contains(&normalized.as_str()),
        "the adapter's greedy answer is outside the legal set: {continuation:?}"
    );

    // (4) ranking under the adapter runs through the same model; every label
    // gets a finite score and the corrected scorer never flags eos dominance
    // (the qwen_rank fix, Tier C).
    let labels = [
        "no_grant",
        "destructive_op",
        "outside_workspace",
        "secret_path",
    ];
    let outcome = rank::rank_labels_with(
        &model,
        &tokenizer,
        &prompt,
        &labels,
        rank::RankOptions {
            normalization: rank::LengthNormalization::Mean,
            boundary: rank::ContinuationBoundary::NoSpace,
        },
        s,
    )
    .expect("rank under the adapter");
    assert_eq!(outcome.scores.len(), labels.len(), "every label ranked");
    for sc in &outcome.scores {
        assert!(
            sc.sum_logprob.is_finite(),
            "non-finite score for {}",
            sc.label
        );
        assert!(
            !sc.eos_dominates,
            "eos dominance under the corrected scorer is the bug class Tier C fixed"
        );
    }
}

/// A target the model does not have REFUSES at attach — the hard-error law.
/// The refusal needs only an adapter that PARSES, so this test builds its own
/// minimal mlx-lm file targeting `model.layers.99...` (out of range) and
/// needs neither the snapshot nor the trained artifact beyond the model.
#[test]
fn an_unknown_target_refuses_at_attach() {
    let Some(s) = stream() else {
        eprintln!("skipping: no Metal device");
        return;
    };
    let Some(snap) = snapshot_dir() else {
        eprintln!("skipping: Qwen3-0.6B-4bit snapshot absent");
        return;
    };
    let dir = std::env::temp_dir().join("qwen_runtime_lora_refusal");
    std::fs::create_dir_all(&dir).expect("tmp dir");
    let fixture = dir.join("bogus_target_adapter.safetensors");
    write_mlx_lm_adapter(&fixture, "model.layers.99.mlp.down_proj", 2, 8);

    let mut model = Qwen3::load(&snap).expect("model loads");
    let err = model
        .attach_lora(&fixture, SCALE, s)
        .expect_err("an out-of-range target must refuse, never skip");
    assert!(
        err.contains("does not have"),
        "unexpected refusal message: {err}"
    );
    assert!(!model.has_runtime_lora(), "a refused attach must not half-apply");
}
