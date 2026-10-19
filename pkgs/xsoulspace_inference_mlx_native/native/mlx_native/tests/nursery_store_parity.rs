//! Cross-language oracle for the nursery weights-splat store: Python packs
//! (tool/nursery/pack_fixture.py → pack_at_birth.py), Rust reads. The
//! fixture under testdata/nursery/ is committed with its generator's
//! provenance in expectations.json; every pinned digest is really checked
//! here, so "mismatched: 0" cannot mean "checks skipped"
//! (SPEC-PAGED-EXPERT-STORE.md contract point 4). Pure file I/O — no GPU,
//! never power-conditioned (bit/parity law).

use mlx_native::nursery::{sha256_hex, NurseryStore};
use serde_json::Value;
use std::path::PathBuf;

fn fixture_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("testdata/nursery")
}

fn expectations() -> Value {
    let path = fixture_dir().join("expectations.json");
    serde_json::from_str(
        &std::fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("fixture expectations unreadable: {e}")),
    )
    .expect("expectations.json unparsable")
}

#[test]
fn store_opens_and_verifies_every_segment() {
    let expectations = expectations();
    let mut store =
        NurseryStore::open(&fixture_dir().join("store")).expect("store opens");
    let report = store.verify_all().expect("all digests verify");
    assert_eq!(report.checked, expectations["segments"].as_u64().unwrap() as usize,
        "every segment must be really digest-checked");
    assert_eq!(report.mismatched, 0);
    assert_eq!(report.missing, 0);
    assert!(report.bytes > 0);
}

#[test]
fn every_tensor_matches_its_pinned_digest_shape_and_role() {
    let expectations = expectations();
    let mut store =
        NurseryStore::open(&fixture_dir().join("store")).expect("store opens");
    let pinned = expectations["tensors"].as_object().expect("tensors map");
    assert!(!pinned.is_empty(), "fixture pins at least one tensor");
    let mut names: Vec<&String> = pinned.keys().collect();
    names.sort();
    for name in names {
        let want = &pinned[name];
        let tensor = store
            .read_tensor(name)
            .unwrap_or_else(|e| panic!("read {name}: {e}"));
        assert_eq!(sha256_hex(&tensor.data), want["sha256"], "{name} bytes");
        assert_eq!(
            tensor.shape,
            want["shape"]
                .as_array()
                .unwrap()
                .iter()
                .map(|v| v.as_u64().unwrap() as usize)
                .collect::<Vec<_>>(),
            "{name} shape"
        );
        assert_eq!(tensor.dtype, want["dtype"], "{name} dtype");
        assert_eq!(tensor.role, want["role"], "{name} role");
    }
}

#[test]
fn f32_conversions_match_the_pinned_samples_bit_for_bit() {
    let expectations = expectations();
    let mut store =
        NurseryStore::open(&fixture_dir().join("store")).expect("store opens");
    let samples = expectations["f32_samples"].as_object().expect("samples map");
    assert!(!samples.is_empty());
    for (name, values) in samples {
        let tensor = store
            .read_tensor(name)
            .unwrap_or_else(|e| panic!("read {name}: {e}"));
        let got = tensor
            .to_f32_vec()
            .unwrap_or_else(|e| panic!("{name}: {e}"));
        let want: Vec<f32> = values
            .as_array()
            .unwrap()
            .iter()
            .map(|v| v.as_f64().unwrap() as f32)
            .collect();
        assert_eq!(got.len(), tensor.elements());
        assert!(
            got.len() >= want.len(),
            "{name}: fixture pinned more samples than elements"
        );
        for (i, (g, w)) in got.iter().zip(want.iter()).enumerate() {
            assert_eq!(g, w, "{name}[{i}]: {g} != {w} (bit-for-bit conversion)");
        }
    }
}

#[test]
fn corrupted_segment_is_a_hard_error_never_a_silent_zero() {
    let src = fixture_dir().join("store");
    let tmp = std::env::temp_dir().join(format!(
        "nursery_corrupt_test_{}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&tmp);
    std::fs::create_dir_all(&tmp).expect("temp store dir");

    // Copy every segment file named by the manifest, then corrupt byte 0 of
    // the first one, remembering a tensor that lives in THAT segment.
    let manifest: Value = serde_json::from_str(
        &std::fs::read_to_string(src.join("manifest.json")).unwrap(),
    )
    .unwrap();
    std::fs::copy(src.join("manifest.json"), tmp.join("manifest.json")).unwrap();
    let mut first_file = None;
    let mut first_tensor = None;
    for (_, seg) in manifest["segments"].as_object().unwrap() {
        let from = src.join(seg["file"].as_str().unwrap());
        let to = tmp.join(seg["file"].as_str().unwrap());
        std::fs::copy(&from, &to).unwrap();
        if first_file.is_none() {
            first_file = Some(to.clone());
            first_tensor = seg["tensors"]
                .as_object()
                .unwrap()
                .keys()
                .next()
                .cloned();
        }
    }
    let victim = first_file.expect("fixture has segments");
    let mut bytes = std::fs::read(&victim).unwrap();
    bytes[0] ^= 0xff;
    std::fs::write(&victim, &bytes).unwrap();

    // verify_all must fail naming a digest mismatch...
    let mut store = NurseryStore::open(&tmp).expect("corrupt store still opens");
    let err = store.verify_all().unwrap_err();
    assert!(
        err.contains("digest mismatch") || err.contains("corrupt"),
        "unexpected error: {err}"
    );
    // ...and a point read from the corrupted segment must refuse too.
    let name = first_tensor.expect("first segment has a tensor");
    assert!(store.read_tensor(&name).is_err(), "corrupt store yielded bytes");

    let _ = std::fs::remove_dir_all(&tmp);
}

#[test]
fn unknown_tensor_and_bad_contract_are_honest_errors() {
    let mut store =
        NurseryStore::open(&fixture_dir().join("store")).expect("store opens");
    assert!(store.read_tensor("no.such.tensor").is_err());
    assert!(store.tensor_meta("no.such.tensor").is_none());
}
