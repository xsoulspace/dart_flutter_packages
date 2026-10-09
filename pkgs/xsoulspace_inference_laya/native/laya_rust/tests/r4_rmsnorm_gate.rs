//! ADR 0054 R4 gate: the fused RMSNorm+residual MSL binding vs the
//! Add+RmsNorm composition it replaces (bfloat16). Gate shape per the
//! mission:
//!   1. correctness: both outputs (sum, normed) ≈ the composition within
//!      bf16 tolerance;
//!   2. µbench ≥1.3× vs the composition — else the table keeps mlx-c (the
//!      binding stays behind LAYA_MSL_NORM=1, opt-in only).
//! Run: cargo test --release --test r4_rmsnorm_gate -- --ignored --nocapture

use laya_native::bindings::{Backend, BindingTable, ShapeClass};
use laya_native::mlx::{self, Array, Dtype};

fn bf16_bytes(count: usize, modulus: u16) -> Vec<u8> {
    let mut v = vec![0u8; count * 2];
    for (i, chunk) in v.chunks_exact_mut(2).enumerate() {
        let bits = 0x3F00u16.wrapping_add((i % modulus as usize) as u16);
        chunk[0] = (bits & 0xFF) as u8;
        chunk[1] = (bits >> 8) as u8;
    }
    v
}

fn run(table: &BindingTable, x: &Array, r: &Array, w: &Array, s: mlx::Stream) -> (Array, Array) {
    let node = laya_native::plan::Node {
        name: "gate.rmsres".into(),
        group: "gate".into(),
        op: laya_native::plan::Op::RmsNormResidual { eps: 1e-6 },
        inputs: Vec::new(),
        dump: None,
    };
    let outs = laya_native::bindings::eval(&node, &[x, r, w], table, s).unwrap();
    let mut it = outs.into_iter();
    (it.next().unwrap(), it.next().unwrap())
}

#[test]
#[ignore]
fn rmsnorm_residual_gate() {
    let metallib = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        laya_native::mlx::set_metallib_path(&metallib);
    }
    let s = mlx::gpu().expect("Metal");

    let script = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../tool/build_msl.sh");
    let st = std::process::Command::new("zsh")
        .arg(script)
        .status()
        .expect("build_msl.sh runs");
    assert!(st.success(), "xcrun metal build gate failed");

    // Decode and prefill shapes.
    let shapes: [(usize, usize); 2] = [(1, 1024), (2047, 1024)];

    let mlxc = BindingTable::baseline();
    let mut msl = BindingTable::baseline();
    msl.install("rms_norm_residual", ShapeClass::Reduction, Dtype::BFloat16, Backend::RmsNormFusedMsl);

    for (rows, cols) in shapes {
        let x = Array::from_data_bf16(&bf16_bytes(rows * cols, 97), &[1, rows, cols]).unwrap();
        let r = Array::from_data_bf16(&bf16_bytes(rows * cols, 61), &[1, rows, cols]).unwrap();
        let w = Array::from_data_bf16(&bf16_bytes(cols, 13), &[cols]).unwrap();
        let (sum_c, norm_c) = run(&mlxc, &x, &r, &w, s);
        let (sum_m, norm_m) = run(&msl, &x, &r, &w, s);
        for (tag, a, b) in [
            ("sum", &sum_c, &sum_m),
            ("normed", &norm_c, &norm_m),
        ] {
            let va = a.astype(Dtype::Float32, s).unwrap().to_f32_vec(s).unwrap();
            let vb = b.astype(Dtype::Float32, s).unwrap().to_f32_vec(s).unwrap();
            let scale = va.iter().fold(1.0f32, |m, v| m.max(v.abs()));
            let diff = va
                .iter()
                .zip(vb.iter())
                .map(|(p, q)| (p - q).abs())
                .fold(0.0f32, f32::max);
            let tol = scale * 0.02;
            println!("correct {rows}x{cols} {tag}: max|diff|={diff:.5} (tol {tol:.2})");
            assert!(diff < tol, "rmsnorm_residual diverged at {rows}x{cols} {tag}: {diff}");
        }
    }

    let med = |v: &mut Vec<f64>| {
        v.sort_by(|a, b| a.total_cmp(b));
        v[v.len() / 2]
    };
    let mut ratios = Vec::new();
    for (rows, cols) in shapes {
        let x = Array::from_data_bf16(&bf16_bytes(rows * cols, 97), &[1, rows, cols]).unwrap();
        let r = Array::from_data_bf16(&bf16_bytes(rows * cols, 61), &[1, rows, cols]).unwrap();
        let w = Array::from_data_bf16(&bf16_bytes(cols, 13), &[cols]).unwrap();
        let mut ms_c = Vec::new();
        let mut ms_m = Vec::new();
        for _ in 0..9 {
            let t0 = std::time::Instant::now();
            {
                let (a, b) = run(&mlxc, &x, &r, &w, s);
                a.eval().unwrap();
                b.eval().unwrap();
                mlx::synchronize_stream(s).unwrap();
            }
            ms_c.push(t0.elapsed().as_secs_f64() * 1e3);
            let t0 = std::time::Instant::now();
            {
                let (a, b) = run(&msl, &x, &r, &w, s);
                a.eval().unwrap();
                b.eval().unwrap();
                mlx::synchronize_stream(s).unwrap();
            }
            ms_m.push(t0.elapsed().as_secs_f64() * 1e3);
        }
        let (c, m) = (med(&mut ms_c), med(&mut ms_m));
        let ratio = c / m;
        ratios.push(ratio);
        println!("µbench {rows}x{cols}: composition {c:.3}ms vs msl {m:.3}ms = {ratio:.2}x");
    }
    let min_ratio = ratios.iter().cloned().fold(f64::INFINITY, f64::min);
    println!(
        "rmsnorm+residual gate verdict: min ratio {min_ratio:.2}x — {}",
        if min_ratio >= 1.3 {
            "PASS (≥1.3×): the row would install"
        } else {
            "FAIL (<1.3×): the table keeps mlx-c (the binding stays LAYA_MSL_NORM opt-in)"
        }
    );
}
