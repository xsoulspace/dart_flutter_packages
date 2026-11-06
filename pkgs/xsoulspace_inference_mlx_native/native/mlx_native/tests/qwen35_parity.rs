//! Qwen3.5-0.8B parity gate — the RUST half against the durable python-first
//! fixture (testdata/qwen35_parity_digests.json; provenance inside: mlx
//! 0.32.4 / mlx-lm 0.32.2 / py 3.12.13, GPU, prefill_step_size 2048,
//! greedy argmax(logits - logsumexp), EOS stop off).
//!
//! The fixture is IN-REPO — its absence is a hard failure, never a skip.
//! The CHECKPOINT is env-gated: this test skips with the NAMED reason
//! QWEN35_CHECKPOINT_ABSENT when no Qwen3.5-0.8B snapshot is reachable
//! (QWEN35_SNAPSHOT or the default HF hub path).
//!
//! Asserts, per fixture prompt:
//!   1. the Rust tokenizer reproduces the reference prompt_token_ids;
//!   2. 24 greedy tokens equal first_32_token_ids;
//!   3. every per_step_sha256 matches (bisects a divergence to one step);
//!   4. the combined logits digest matches;
//!   5. a 16-token greedy generation is deterministic across two runs
//!      (the task's determinism law, on the REAL base checkpoint).

use mlx_native::bpe::ByteLevelBpe;
use mlx_native::mlx;
use mlx_native::qwen3_5::{self, Qwen35};
use serde::Deserialize;

#[derive(Deserialize)]
struct Fixture {
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
    per_step_sha256: Vec<String>,
    logits_digest_sha256_of_first_8_steps_fp32_rounded_6dp: String,
}

fn fixture() -> Fixture {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../testdata/qwen35_parity_digests.json");
    let raw = std::fs::read_to_string(&path).unwrap_or_else(|e| {
        panic!(
            "QWEN35_FIXTURE_UNREADABLE: the durable in-repo parity contract at {} must exist: {e}",
            path.display()
        )
    });
    serde_json::from_str(&raw).expect("fixture parses")
}

#[test]
fn qwen35_greedy_matches_python_digests_and_is_deterministic() {
    let fx = fixture();
    assert!(
        fx.provenance.get("model_type").and_then(|v| v.as_str()) == Some("qwen3_5"),
        "fixture is the qwen3_5 contract"
    );

    let Some(dir) = qwen3_5::default_snapshot_dir() else {
        eprintln!(
            "skipping: QWEN35_CHECKPOINT_ABSENT — no Qwen3.5-0.8B snapshot \
             (set QWEN35_SNAPSHOT or place it at \
             ~/.cache/huggingface/hub/models--Qwen--Qwen3.5-0.8B/snapshots/main)"
        );
        return;
    };

    // Test binaries don't sit beside a metallib; pin the cmake-built one
    // BEFORE the first gpu() call (the lfm2_parity idiom).
    let metallib = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        mlx::set_metallib_path(&metallib);
    }
    let Ok(s) = mlx::gpu() else {
        eprintln!("skipping: NO_METAL_DEVICE");
        return;
    };

    let model = Qwen35::load(&dir).expect("qwen3_5 loads (sharded store, HF plus-one norms)");
    let tok = ByteLevelBpe::load(&dir).expect("tokenizer loads");

    for r in &fx.results {
        // 1. tokenizer parity with the reference prompt encoding.
        let ids: Vec<i32> = tok
            .encode(&r.prompt)
            .expect("encode")
            .into_iter()
            .map(|x| x as i32)
            .collect();
        assert_eq!(
            ids, r.prompt_token_ids,
            "prompt {} tokenization diverges from the reference",
            r.prompt_id
        );

        // 2-4. tokens + per-step digests + combined digest.
        let mut per_step: Vec<String> = Vec::new();
        let mut step_texts: Vec<String> = Vec::new();
        let mut generated: Vec<i32> = Vec::new();
        model
            .generate_greedy(
                &ids,
                r.generated_steps,
                r.per_step_sha256.len(),
                s,
                &mut |_step, token, logits| {
                    generated.push(token);
                    if let Some(row) = logits {
                        let f32s = qwen3_5::logits_row_f32(row, s).expect("logits readback");
                        let text = qwen3_5::format_logits_row(&f32s);
                        per_step.push(qwen3_5::per_step_sha256(&text));
                        step_texts.push(text);
                    }
                },
            )
            .expect("greedy decode runs");

        let take = r.first_32_token_ids.len().min(generated.len());
        assert_eq!(
            &generated[..take],
            &r.first_32_token_ids[..take],
            "prompt {} generated tokens diverge from the python reference",
            r.prompt_id
        );
        for (i, (mine, theirs)) in per_step.iter().zip(r.per_step_sha256.iter()).enumerate() {
            assert_eq!(
                mine, theirs,
                "prompt {} step {i} logits digest diverges (first mismatch bisects the \
                 pipeline: earlier steps matched, so prefill+sampler+preceding recurrences \
                 are bitwise-clean up to this step)",
                r.prompt_id
            );
        }
        assert_eq!(per_step.len(), r.per_step_sha256.len(), "digest step count");
        let combined = qwen3_5::steps_sha256(&step_texts);
        assert_eq!(
            combined, r.logits_digest_sha256_of_first_8_steps_fp32_rounded_6dp,
            "prompt {} combined logits digest diverges",
            r.prompt_id
        );
    }

    // 5. determinism on the real checkpoint: two 16-token greedy runs from
    // the first fixture prompt must agree token-for-token.
    let r0 = &fx.results[0];
    let ids0: Vec<i32> = r0.prompt_token_ids.clone();
    let a = model
        .generate_greedy_tokens(&ids0, 16, s)
        .expect("run a");
    let b = model
        .generate_greedy_tokens(&ids0, 16, s)
        .expect("run b");
    assert_eq!(a, b, "greedy generation is not deterministic across runs");
}
