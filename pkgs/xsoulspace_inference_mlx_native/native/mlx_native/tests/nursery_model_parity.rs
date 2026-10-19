//! Cross-language parity for the RUNG-0 model runtime: Python defines and
//! runs the model (tool/nursery/model_fixture.py over model_def.py), packs
//! the checkpoint at birth, and pins decisions; Rust loads ONLY the packed
//! store and must reproduce them. Routes and emitted bytes are compared
//! EXACTLY (the PORTING-MOE.md point — parity fixtures pin routes, not
//! just logits; the fixture's margins sit ≥ 20x above cross-build float
//! noise, pinned in expectations.margins). Logits are compared under the
//! tolerances the generator states (python mlx and mlx-c are different
//! builds of the same kernels). This is a correctness gate: never
//! power-conditioned; it measures no time.

use mlx_native::nursery_model::NurseryModel;
use serde_json::Value;
use std::collections::BTreeMap;
use std::path::PathBuf;

fn fixture_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("testdata/nursery_model")
}

fn expectations() -> Value {
    let path = fixture_dir().join("expectations.json");
    serde_json::from_str(
        &std::fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("fixture expectations unreadable: {e}")),
    )
    .expect("expectations.json unparsable")
}

fn u8_vec(value: &Value) -> Vec<u8> {
    value
        .as_array()
        .expect("expected a list")
        .iter()
        .map(|v| v.as_u64().expect("expected ints") as u8)
        .collect()
}

fn f32_vec(value: &Value) -> Vec<f32> {
    value
        .as_array()
        .expect("expected a list")
        .iter()
        .map(|v| v.as_f64().expect("expected numbers") as f32)
        .collect()
}

#[test]
fn runtime_reproduces_the_pinned_routing_generation_and_logits() {
    // Test binaries don't sit beside a metallib; pin the cmake-built one
    // (the l0/gpu_tests pattern — without it mlx loads a foreign build's
    // kernels and aborts in stream setup).
    let metallib = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        mlx_native::mlx::set_metallib_path(&metallib)
            .expect("metallib pin");
    }
    let exp = expectations();
    let model =
        NurseryModel::load(&fixture_dir().join("store")).expect("model loads from the packed store");
    assert_eq!(model.config().hidden_size,
               exp["config"]["hidden_size"].as_u64().unwrap() as usize,
               "config round-trips through the store manifest");
    let stream = mlx_native::mlx::gpu().expect("gpu stream");
    let prompt = u8_vec(&exp["prompt"]);
    let max_new = exp["max_new"].as_u64().unwrap() as usize;
    let outcome = model.generate(&prompt, max_new, stream).expect("generate runs");

    // Routing decisions: EXACT, grouped per position then layer.
    let expected_routes = exp["routes_by_pos"].as_array().expect("routes list");
    let mut by_pos: BTreeMap<usize, BTreeMap<usize, Vec<usize>>> = BTreeMap::new();
    for row in &outcome.routes {
        by_pos
            .entry(row.pos)
            .or_default()
            .insert(row.layer, row.experts.clone());
    }
    assert_eq!(
        by_pos.len(),
        expected_routes.len(),
        "one route row-set per pinned position"
    );
    for (pos, layers) in expected_routes.iter().enumerate() {
        let got = &by_pos[&pos];
        let want = layers.as_array().expect("per-position layer list");
        assert_eq!(got.len(), want.len(), "position {pos}: every layer routed");
        for (layer, experts) in want.iter().enumerate() {
            let want_experts: Vec<usize> = experts
                .as_array()
                .expect("expert id list")
                .iter()
                .map(|v| v.as_u64().unwrap() as usize)
                .collect();
            assert_eq!(
                got[&layer], want_experts,
                "position {pos} layer {layer}: routes must match the python forward exactly"
            );
        }
    }

    // Greedy bytes and stop reason: EXACT.
    assert_eq!(outcome.emitted, u8_vec(&exp["emitted"]), "emitted bytes");
    assert_eq!(outcome.stop_reason, exp["stop_reason"].as_str().unwrap());

    // Head logits: under the generator's stated cross-build tolerances.
    let max_diff = |a: &[f32], b: &[f32]| -> f32 {
        assert_eq!(a.len(), b.len(), "logit vector length");
        a.iter()
            .zip(b)
            .map(|(x, y)| (x - y).abs())
            .fold(0.0_f32, f32::max)
    };
    let label_tol = exp["tolerances"]["label_abs_tol"].as_f64().unwrap() as f32;
    let label_diff = max_diff(&outcome.label_logits, &f32_vec(&exp["label_logits"]));
    assert!(
        label_diff <= label_tol,
        "label_logits differ by {label_diff} > {label_tol}"
    );
    let logits_tol = exp["tolerances"]["logits_abs_tol"].as_f64().unwrap() as f32;
    let logits_diff = max_diff(&outcome.last_logits, &f32_vec(&exp["final_logits"]));
    assert!(
        logits_diff <= logits_tol,
        "final logits differ by {logits_diff} > {logits_tol}"
    );
}
