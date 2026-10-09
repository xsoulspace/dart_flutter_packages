//! ADR 0054 R2 gate: greedy token-for-token parity against the mlx-lm
//! reference (fixture regenerated from the cached Qwen3-0.6B-4bit snapshot
//! via tool/gen_qwen3_parity_fixture.py) plus byte-level-BPE parity probes.
//!
//! Skips (with a note) when the snapshot or fixture is absent — the model is
//! not committed. RUNG LAW: a parity failure is a gate failure; record it in
//! the ADR, never weaken the fixture.

use laya_native::bpe::ByteLevelBpe;
use laya_native::mlx;
use laya_native::qwen::Qwen3;
use serde::Deserialize;

#[derive(Deserialize)]
struct ParityFixture {
    snapshot: String,
    #[allow(dead_code)]
    prompt: String,
    prompt_ids: Vec<i32>,
    greedy_ids: Vec<i32>,
    tokenizer_probes: std::collections::HashMap<String, Vec<u32>>,
}

fn fixture() -> Option<ParityFixture> {
    let path = std::env::var_os("QWEN3_FIXTURE")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| {
            std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("testdata/qwen3_06b_parity.json")
        });
    let raw = std::fs::read_to_string(path).ok()?;
    Some(serde_json::from_str(&raw).expect("parity fixture parses"))
}

/// The cached snapshot dir (or $QWEN3_SNAPSHOT override), if present.
fn snapshot_dir(_fixture: &ParityFixture) -> Option<std::path::PathBuf> {
    if let Some(over) = std::env::var_os("QWEN3_SNAPSHOT") {
        let p = std::path::PathBuf::from(over);
        if p.is_dir() {
            return Some(p);
        }
        return None;
    }
    let home = std::env::var_os("HOME")?;
    let mut pat = std::path::PathBuf::from(home);
    pat.push(".cache/huggingface/hub");
    let hub = std::fs::read_dir(&pat).ok()?;
    for entry in hub.flatten() {
        let name = entry.file_name();
        if name.to_string_lossy().contains("Qwen3-0.6B-4bit") {
            let snaps = entry.path().join("snapshots");
            if let Ok(list) = std::fs::read_dir(&snaps) {
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

fn gpu() -> Option<mlx::Stream> {
    if let Ok(s) = mlx::gpu() {
        return Some(s);
    }
    eprintln!("skipping: no Metal device");
    None
}

/// Tokenizer probes: Rust BPE must produce the reference ids exactly.
#[test]
fn bpe_matches_reference_probes() {
    let Some(fx) = fixture() else {
        eprintln!("skipping: parity fixture absent");
        return;
    };
    let Some(snap) = snapshot_dir(&fx) else {
        eprintln!("skipping: Qwen3-0.6B-4bit snapshot absent");
        return;
    };
    let tok = ByteLevelBpe::load(&snap).expect("tokenizer loads");
    for (text, want) in &fx.tokenizer_probes {
        let got = tok.encode(text).unwrap_or_else(|e| panic!("encode {text:?}: {e}"));
        assert_eq!(
            &got, want,
            "tokenizer probe diverged for {text:?}\n got  {got:?}\n want {want:?}"
        );
    }
    // Round-trip: decode(encode(probe)) returns the NFC-normalized text.
    for text in fx.tokenizer_probes.keys() {
        let ids = tok.encode(text).unwrap();
        let back = tok.decode(&ids).unwrap();
        assert_eq!(&back, text);
    }
}

/// The R2 gate: greedy decode reproduces the reference token sequence.
#[test]
fn greedy_decode_matches_reference() {
    let Some(fx) = fixture() else {
        eprintln!("skipping: parity fixture absent");
        return;
    };
    let Some(snap) = snapshot_dir(&fx) else {
        eprintln!("skipping: Qwen3-0.6B-4bit snapshot absent");
        return;
    };
    let Some(s) = gpu() else { return };
    // Golden-laya convention: the metallib sits in the crate's build dir.
    let metallib = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        laya_native::mlx::set_metallib_path(&metallib);
    }

    let tok = ByteLevelBpe::load(&snap).expect("tokenizer loads");
    let prompt_ids = tok
        .encode(&fx.prompt)
        .expect("prompt encodes")
        .into_iter()
        .map(|i| i as i32)
        .collect::<Vec<_>>();
    assert_eq!(
        prompt_ids, fx.prompt_ids,
        "prompt tokenization diverged from the reference"
    );

    let t0 = std::time::Instant::now();
    let model = Qwen3::load(&snap).expect("model loads");
    println!("model load: {:?}", t0.elapsed());

    let t0 = std::time::Instant::now();
    let ids = model
        .generate_greedy(&fx.prompt_ids, fx.greedy_ids.len(), s)
        .expect("greedy decode runs");
    println!("greedy {} tokens: {:?}", fx.greedy_ids.len(), t0.elapsed());

    let generated = &ids[fx.prompt_ids.len()..];
    let mut first_diff = None;
    for (i, (g, w)) in generated.iter().zip(fx.greedy_ids.iter()).enumerate() {
        if g != w {
            first_diff = Some((i, *g, *w));
            break;
        }
    }
    match first_diff {
        None => {
            println!(
                "PARITY: {}/{} greedy tokens match the mlx-lm reference",
                fx.greedy_ids.len(),
                fx.greedy_ids.len()
            );
        }
        Some((i, g, w)) => panic!(
            "greedy parity FAILED at generated token {i}: got {g}, want {w} (of {} tokens)",
            fx.greedy_ids.len()
        ),
    }
    assert_eq!(generated, &fx.greedy_ids[..]);
}

/// FFI smoke: the C ABI surface (load → generate JSON → unload) end-to-end
/// with the fixture prompt.
#[test]
fn qwen_ffi_generate_smoke() {
    let Some(fx) = fixture() else {
        eprintln!("skipping: parity fixture absent");
        return;
    };
    let Some(snap) = snapshot_dir(&fx) else {
        eprintln!("skipping: Qwen3-0.6B-4bit snapshot absent");
        return;
    };
    let metallib = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        laya_native::mlx::set_metallib_path(&metallib);
    }

    extern "C" {
        fn laya_native_qwen_load(model_dir: *const std::ffi::c_char) -> i64;
        fn laya_native_qwen_generate(
            handle: i64,
            request_json: *const std::ffi::c_char,
        ) -> *mut std::ffi::c_char;
        fn laya_native_qwen_unload(handle: i64);
        fn laya_native_free(pointer: *mut std::ffi::c_char);
    }

    let dir = std::ffi::CString::new(snap.to_str().unwrap()).unwrap();
    let handle = unsafe { laya_native_qwen_load(dir.as_ptr()) };
    assert!(handle > 0, "qwen load failed: {handle}");
    let request = std::ffi::CString::new(
        serde_json::json!({ "prompt": fx.prompt, "max_tokens": 8 }).to_string(),
    )
    .unwrap();
    let out = unsafe { laya_native_qwen_generate(handle, request.as_ptr()) };
    assert!(!out.is_null(), "generate returned null");
    let payload = unsafe { std::ffi::CStr::from_ptr(out) }.to_string_lossy().to_string();
    unsafe { laya_native_free(out) };
    unsafe { laya_native_qwen_unload(handle) };

    let parsed: serde_json::Value = serde_json::from_str(&payload).expect("response JSON");
    assert!(
        parsed.get("error").is_none(),
        "generate errored: {parsed}"
    );
    let ids: Vec<i32> = parsed["ids"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.as_i64().unwrap() as i32)
        .collect();
    assert_eq!(ids.len(), fx.prompt_ids.len() + 8);
    assert_eq!(
        &ids[..fx.prompt_ids.len()],
        &fx.prompt_ids[..],
        "FFI prompt ids diverge from the tokenizer fixture"
    );
    assert_eq!(
        &ids[fx.prompt_ids.len()..],
        &fx.greedy_ids[..8],
        "FFI greedy ids diverge from the reference"
    );
}
