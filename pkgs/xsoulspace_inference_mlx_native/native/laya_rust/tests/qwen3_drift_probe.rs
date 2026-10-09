//! Drift probe (ignored): compare full last-position logits against the
//! python reference dump at /tmp/qwen_ref_logits.json (written by
//! /tmp/qwen_ref_dump.py, mlx-lm on the same snapshot). Run:
//!   cargo test --release --test qwen3_drift_probe -- --nocapture

use laya_native::mlx::{self, Array, Dtype};
use laya_native::qwen::Qwen3;
use serde::Deserialize;

#[derive(Deserialize)]
struct RefDump {
    prefill_last: Vec<f32>,
    prefill_top2_ids: Vec<u32>,
    prefill_top2_vals: Vec<f32>,
    decode0_last: Vec<f32>,
    decode0_top2_ids: Vec<u32>,
    decode0_top2_vals: Vec<f32>,
    #[allow(dead_code)]
    decode1_last: Vec<f32>,
    decode1_top2_ids: Vec<u32>,
    decode1_top2_vals: Vec<f32>,
    decode2_top2_ids: Vec<u32>,
    decode2_top2_vals: Vec<f32>,
    #[allow(dead_code)]
    decode2_top2_ids_x: Option<Vec<u32>>,
}

fn snapshot() -> std::path::PathBuf {
    let home = std::env::var("HOME").unwrap();
    let hub = std::path::Path::new(&home).join(".cache/huggingface/hub");
    for e in std::fs::read_dir(hub).unwrap().flatten() {
        if e.file_name().to_string_lossy().contains("Qwen3-0.6B-4bit") {
            for s in std::fs::read_dir(e.path().join("snapshots")).unwrap().flatten() {
                if s.path().join("config.json").is_file() {
                    return s.path();
                }
            }
        }
    }
    panic!("snapshot missing");
}

fn last_logits(model: &Qwen3, logits: &Array, s: mlx::Stream) -> Vec<f32> {
    let l = logits.dim(1);
    let idx = Array::from_data_i32(&[(l - 1) as i32], &[1, 1, 1]).unwrap();
    let last = logits.take_along_axis(&idx, 1, s).unwrap();
    last.astype(Dtype::Float32, s).unwrap().to_f32_vec(s).unwrap()
}

fn top2(v: &[f32]) -> (Vec<u32>, Vec<f32>) {
    let mut idx: Vec<u32> = (0..v.len() as u32).collect();
    idx.sort_by(|&a, &b| v[b as usize].total_cmp(&v[a as usize]));
    (
        idx[..2].to_vec(),
        idx[..2].iter().map(|&i| v[i as usize]).collect(),
    )
}

fn report(tag: &str, got: &[f32], want: &[f32]) {
    let (gids, gvals) = top2(got);
    let maxd = got
        .iter()
        .zip(want.iter())
        .map(|(a, b)| (a - b).abs())
        .fold(0.0f32, f32::max);
    let mean_abs: f32 =
        got.iter().zip(want.iter()).map(|(a, b)| (a - b).abs()).sum::<f32>() / got.len() as f32;
    println!("{tag}: max|diff|={maxd:.6} mean|diff|={mean_abs:.6} top2_ids={gids:?} top2_vals={gvals:?}");
}

#[test]
fn logit_drift_probe() {
    let Ok(raw) = std::fs::read_to_string("/tmp/qwen_ref_logits.json") else {
        eprintln!("skipping: /tmp/qwen_ref_logits.json absent");
        return;
    };
    let _ref: RefDump = serde_json::from_str(&raw).unwrap();
    let _ = &_ref.prefill_top2_ids;
    // Test binaries don't sit beside a metallib; pin the cmake-built one
    // BEFORE the first gpu() call (see lib.rs l0_ops).
    let metallib = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        laya_native::mlx::set_metallib_path(&metallib);
    }
    let s = mlx::gpu().expect("Metal");
    let fx: serde_json::Value = serde_json::from_str(
        &std::fs::read_to_string(
            std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("testdata/qwen3_06b_parity.json"),
        )
        .unwrap(),
    )
    .unwrap();
    let prompt_ids: Vec<i32> = fx["prompt_ids"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.as_i64().unwrap() as i32)
        .collect();

    let model = Qwen3::load(&snapshot()).unwrap();
    let mut cache = laya_native::qwen::KvCache::new(model.cfg.layers);

    let tokens = Array::from_data_i32(&prompt_ids, &[1, prompt_ids.len()]).unwrap();
    let logits = model.forward_step(&tokens, &mut cache, s).unwrap();
    let got = last_logits(&model, &logits, s);
    report("prefill", &got, &_ref.prefill_last);

    let mut tok = top2(&got).0[0] as i32;
    for step in 0..3 {
        let t = Array::from_data_i32(&[tok], &[1, 1]).unwrap();
        let logits = model.forward_step(&t, &mut cache, s).unwrap();
        let got = last_logits(&model, &logits, s);
        let want = match step {
            0 => &_ref.decode0_last,
            _ => &Vec::new(),
        };
        if !want.is_empty() {
            report(&format!("decode{step}"), &got, want);
        }
        let (ids, vals) = top2(&got);
        println!("decode{step} tok={tok} top2_ids={ids:?} top2_vals={vals:?}");
        tok = ids[0] as i32;
    }
}
