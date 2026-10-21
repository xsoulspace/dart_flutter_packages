//! ADR 0057 / MTP-GATES J-G4 parity: the native Rust MTP draft head
//! reproduces the Python reference (`tool/nursery/mtp_retarget.py`,
//! `head_forward`) op for op.
//!
//! THE ORACLE is a PINNED fixture recorded from the Python reference before
//! the Rust port ran: `testdata/qwen_mtp_parity.json` (the head's output
//! hidden, the tied-projection logits and the argmax, per chain depth) plus
//! `testdata/qwen_mtp_head_synth.safetensors` (the head's five weights under
//! the EXPORTER's tensor names `model.mtp.d{j}.{proj,norm,gate,up,down}.weight`
//! and the tied embedding `model.embed_tokens.weight`).
//!
//! NO CHECKPOINT IS NEEDED: the head is a pure function of its weights and
//! two input vectors, so the fixture is synthetic and the test runs on any
//! Metal host. The provenance (generator path + sha256, command, mlx version,
//! tolerances) is inside the fixture.
//!
//! RUNG LAW: a parity failure is a gate failure — record it, never weaken
//! the fixture. The tolerances are the ones the generator states BEFORE the
//! Rust run (python-mlx and the vendored mlx-c are different builds of the
//! same kernels, so this is a tolerance comparison, not bit-identity — the
//! same stance as the nursery model parity fixture).

use mlx_native::mlx::{self, Array, Dtype};
use mlx_native::qwen_mtp::{MtpChain, MtpHead, TiedEmbedding};
use serde_json::Value;
use std::path::{Path, PathBuf};

fn fixture_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("testdata")
}

fn fixture() -> Value {
    let path = fixture_dir().join("qwen_mtp_parity.json");
    serde_json::from_str(
        &std::fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("parity fixture unreadable: {e}")),
    )
    .expect("parity fixture unparsable")
}

fn f32_vec(value: &Value) -> Vec<f32> {
    value
        .as_array()
        .expect("expected a list")
        .iter()
        .map(|v| v.as_f64().expect("expected numbers") as f32)
        .collect()
}

fn max_diff(a: &[f32], b: &[f32]) -> f32 {
    assert_eq!(a.len(), b.len(), "vector length");
    a.iter()
        .zip(b)
        .map(|(x, y)| (x - y).abs())
        .fold(0.0_f32, f32::max)
}

/// Test binaries don't sit beside a metallib; pin the cmake-built one before
/// the first gpu() call (the qwen3_parity / nursery_model_parity pattern).
fn metallib() {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("build/mlx-install/lib/mlx.metallib");
    if path.is_file() {
        let _ = mlx::set_metallib_path(&path);
    }
}

fn gpu() -> Option<mlx::Stream> {
    match mlx::gpu() {
        Ok(s) => Some(s),
        Err(_) => {
            eprintln!("skipping: no Metal device");
            None
        }
    }
}

#[test]
fn mtp_head_reproduces_the_python_reference() {
    metallib();
    let Some(s) = gpu() else { return };
    let fx = fixture();
    let cfg = &fx["config"];
    let h = cfg["hidden_size"].as_u64().unwrap() as usize;
    let count = cfg["count"].as_u64().unwrap() as usize;

    let head_file = fixture_dir().join(cfg["safetensors"].as_str().unwrap());
    assert!(head_file.is_file(), "head file missing: {head_file:?}");

    // The loader's digest is the file's sha256 — the cache key the
    // adapter-digest law needs. Pin it against the fixture.
    let chain = MtpChain::load(&head_file, 1.0, s).expect("mtp chain loads");
    assert_eq!(
        chain.len(),
        count,
        "the chain's MTP count must match the fixture"
    );
    assert_eq!(
        chain.digest,
        cfg["safetensors_sha256"].as_str().unwrap(),
        "the head file's digest must match the fixture"
    );
    assert_eq!(chain.heads[0].hidden_size(), h, "hidden width");
    assert_eq!(
        chain.heads[0].mlp_width(),
        cfg["mlp_width"].as_u64().unwrap() as usize,
        "mlp width"
    );

    // The tied embedding (the head's token rows AND its vocab projection).
    let embed = TiedEmbedding::load_file(&head_file, 0, 0, s).expect("tied embedding loads");
    assert_eq!(embed.vocab, cfg["vocab"].as_u64().unwrap() as usize);
    assert_eq!(embed.hidden, h);

    let tols = &fx["tolerances"];
    let hidden_tol = tols["hidden_abs_tol"].as_f64().unwrap() as f32;
    let logits_tol = tols["logits_abs_tol"].as_f64().unwrap() as f32;
    let emb_tol = tols["embedding_abs_tol"].as_f64().unwrap() as f32;

    // ---- the embedding rows (the head's token_emb input) ----
    for (token, want) in fx["inputs"]["embedding_rows"].as_object().unwrap() {
        let id: i32 = token.parse().unwrap();
        let rows = embed.embedding_rows(&[id], s).expect("embedding rows");
        let got = rows.to_f32_vec(s).expect("embedding readback");
        let d = max_diff(&got, &f32_vec(want));
        assert!(
            d <= emb_tol,
            "embedding row {id} differs by {d} > {emb_tol}"
        );
    }

    // ---- the head chain ----
    let prev_hidden = f32_vec(&fx["inputs"]["prev_hidden"]);
    let mut prev = Array::from_data_f32(&prev_hidden, &[1, 1, h]).expect("prev hidden");
    let mut token: i32 = fx["inputs"]["token_ids"][0].as_i64().unwrap() as i32;
    let mut worst_hidden = 0.0f32;
    let mut worst_logits = 0.0f32;

    for exp in fx["expectations"].as_array().unwrap() {
        let depth = exp["depth"].as_u64().unwrap() as usize;
        assert_eq!(
            exp["input_token"].as_i64().unwrap() as i32,
            token,
            "depth {depth}: the chain must feed this depth the token the \
             reference fed it (depth 0: the trunk's token; depth j>0: depth \
             j-1's proposed token)"
        );
        let head = &chain.heads[depth];

        // The head's input token embedding.
        let emb_rows = embed.embedding_rows(&[token], s).expect("embedding rows");
        let emb = emb_rows.reshape(&[1, 1, h], s).expect("reshape");

        // The head forward.
        let out = head.forward(&prev, &emb, s).expect("head forward");
        let got = out.to_f32_vec(s).expect("hidden readback");
        let want = f32_vec(&exp["hidden"]);
        let d = max_diff(&got, &want);
        worst_hidden = worst_hidden.max(d);
        assert!(
            d <= hidden_tol,
            "depth {depth}: head hidden differs by {d} > {hidden_tol}"
        );

        // The tied vocab projection + the argmax (the proposed token).
        let logits = embed.as_linear(&out, s).expect("tied projection");
        let lg = logits.astype(Dtype::Float32, s).expect("cast");
        let got_logits = lg.to_f32_vec(s).expect("logits readback");
        let want_logits = f32_vec(&exp["logits"]);
        let dl = max_diff(&got_logits, &want_logits);
        worst_logits = worst_logits.max(dl);
        assert!(
            dl <= logits_tol,
            "depth {depth}: projected logits differ by {dl} > {logits_tol}"
        );
        let am = logits.argmax_axis(-1, false, s).expect("argmax");
        let amf = am.astype(Dtype::Float32, s).expect("cast");
        let amv = amf.to_f32_vec(s).expect("argmax readback");
        let got_token = amv.first().copied().unwrap_or(f32::NAN) as i32;
        assert_eq!(
            got_token,
            exp["argmax"].as_i64().unwrap() as i32,
            "depth {depth}: the proposed token must match the reference"
        );

        // The chain: the next depth reads THIS depth's hidden and the
        // embedding of THIS depth's proposed token.
        prev = out;
        token = got_token;
    }
    println!(
        "PARITY: the MTP head reproduces the python reference — worst hidden \
         diff {worst_hidden:e} (tol {hidden_tol:e}), worst logits diff \
         {worst_logits:e} (tol {logits_tol:e}), {count} chained depth(s)"
    );
}

#[test]
fn mtp_head_loader_rejects_a_file_without_head_tensors() {
    // A file with no `model.mtp.d{j}.*` tensors is a hard error, never a
    // silent empty chain (an empty chain would decode as plain greedy and
    // look like "MTP works").
    let dir = fixture_dir();
    let path = dir.join("qwen_mtp_parity.json"); // not a safetensors file at all
    metallib();
    let Ok(s) = mlx::gpu() else {
        eprintln!("skipping: no Metal device");
        return;
    };
    let err = match MtpChain::load(&path, 1.0, s) {
        Ok(_) => panic!("a non-safetensors file must not load as a head chain"),
        Err(e) => e,
    };
    assert!(
        err.contains("open mtp head") || err.contains("no model.mtp.d"),
        "unexpected error: {err}"
    );
}

#[test]
fn mtp_head_scale_of_one_is_the_reference() {
    // The reference has no scale; the port's scale multiplies the residual
    // delta. scale = 1.0 must therefore reproduce the reference exactly, and
    // a different scale must change the output (the scale is never silent).
    metallib();
    let Some(s) = gpu() else { return };
    let fx = fixture();
    let h = fx["config"]["hidden_size"].as_u64().unwrap() as usize;
    let head_file = fixture_dir().join(fx["config"]["safetensors"].as_str().unwrap());
    let one = MtpHead::load(&head_file, 1.0, s).expect("head loads");
    let two = MtpHead::load(&head_file, 2.0, s).expect("head loads");
    let prev = Array::from_data_f32(&f32_vec(&fx["inputs"]["prev_hidden"]), &[1, 1, h])
        .expect("prev hidden");
    let emb = Array::from_data_f32(&f32_vec(&fx["inputs"]["embedding_rows"]["3"]), &[1, 1, h])
        .expect("emb");
    let a = one.forward(&prev, &emb, s).expect("forward");
    let b = two.forward(&prev, &emb, s).expect("forward");
    let av = a.to_f32_vec(s).expect("readback");
    let bv = b.to_f32_vec(s).expect("readback");
    assert_ne!(av, bv, "the scale must change the head's output");
}
