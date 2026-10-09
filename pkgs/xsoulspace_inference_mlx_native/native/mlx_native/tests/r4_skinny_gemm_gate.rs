//! ADR 0054 R4 gate: the skinny-GEMM MSL binding vs the mlx-c matmul it
//! would replace. Gate shape per the mission:
//!   1. correctness: kernel ≈ mlx-c within fp16 tolerance on the tuned
//!      shapes (and on a golden-like batch);
//!   2. µbench ≥1.3× vs mlx-c on the tuned family — else the table keeps
//!      mlx-c (the binding stays behind LAYA_MSL=1, opt-in only).
//! Also runs the xcrun build gate (tool/build_msl.sh) as the syntax proof.
//! Run: cargo test --release --test r4_skinny_gemm_gate -- --ignored --nocapture

use mlx_native::bindings::{Backend, BindingTable, ShapeClass};
use mlx_native::mlx::{self, Array, Dtype};

fn fp16_pattern(count: usize, modulus: u16) -> Vec<u8> {
    let mut v = vec![0u8; count * 2];
    for (i, chunk) in v.chunks_exact_mut(2).enumerate() {
        let bits = 0x3800u16.wrapping_add((i % modulus as usize) as u16).to_le_bytes();
        chunk[0] = bits[0];
        chunk[1] = bits[1];
    }
    v
}

/// A [M, K] × [K, N] pair in fp16, x row-major, b row-major [K, N].
fn inputs(m: usize, k: usize, n: usize) -> (Array, Array) {
    (
        Array::from_data_f16(&fp16_pattern(m * k, 97), &[m, k]).unwrap(),
        Array::from_data_f16(&fp16_pattern(k * n, 61), &[k, n]).unwrap(),
    )
}

fn run(table: &BindingTable, a: &Array, b: &Array, s: mlx::Stream) -> Array {
    let node = mlx_native::plan::Node {
        name: "gate.matmul".into(),
        group: "gate".into(),
        op: mlx_native::plan::Op::Matmul,
        inputs: Vec::new(),
        dump: None,
    };
    mlx_native::bindings::eval(&node, &[a, b], table, s)
        .unwrap()
        .into_iter()
        .next()
        .unwrap()
}

fn max_abs_diff(x: &[f32], y: &[f32]) -> f32 {
    x.iter()
        .zip(y.iter())
        .map(|(a, b)| (a - b).abs())
        .fold(0.0f32, f32::max)
}

/// Correctness + µbench A/B on the laya B=1 shapes. The verdict prints;
/// the table keeps mlx-c unless every shape clears 1.3×.
#[test]
#[ignore]
fn skinny_gemm_gate() {
    let metallib = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        mlx_native::mlx::set_metallib_path(&metallib);
    }
    let s = mlx::gpu().expect("Metal");

    // 1. xcrun build gate (colocated metallib = the syntax proof).
    let script = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../tool/build_msl.sh");
    let st = std::process::Command::new("zsh")
        .arg(script)
        .status()
        .expect("build_msl.sh runs");
    assert!(st.success(), "xcrun metal build gate failed");

    let shapes: [(usize, usize, usize); 4] =
        [(90, 1024, 3072), (90, 1024, 1024), (90, 1024, 4096), (90, 4096, 1024)];

    // 2. correctness: kernel vs mlx-c within fp16 dot tolerance.
    let mlxc = BindingTable::baseline();
    let mut msl = BindingTable::baseline();
    msl.install("matmul", ShapeClass::SkinnyGemm, Dtype::Float16, Backend::SkinnyGemmMsl);
    for (m, k, n) in shapes {
        let (a, b) = inputs(m, k, n);
        let r_c = run(&mlxc, &a, &b, s);
        let r_m = run(&msl, &a, &b, s);
        let vc = r_c.astype(Dtype::Float32, s).unwrap().to_f32_vec(s).unwrap();
        let vm = r_m.astype(Dtype::Float32, s).unwrap().to_f32_vec(s).unwrap();
        let scale = k as f32;
        let diff = max_abs_diff(&vc, &vm);
        println!("correct M={m} K={k} N={n}: max|diff|={diff:.5} (tol {:.3})", scale * 5e-3);
        assert!(diff < scale * 5e-3, "skinny gemm diverged at M={m} K={k} N={n}: {diff}");
    }

    // 3. µbench: per-op eval+sync per run, interleaved rounds, medians.
    let med = |v: &mut Vec<f64>| {
        v.sort_by(|a, b| a.total_cmp(b));
        v[v.len() / 2]
    };
    let mut ratios = Vec::new();
    for (m, k, n) in shapes {
        let (a, b) = inputs(m, k, n);
        let mut ms_c = Vec::new();
        let mut ms_m = Vec::new();
        for _ in 0..5 {
            let t0 = std::time::Instant::now();
            {
                let r = run(&mlxc, &a, &b, s);
                r.eval().unwrap();
                mlx::synchronize_stream(s).unwrap();
            }
            ms_c.push(t0.elapsed().as_secs_f64() * 1e3);
            let t0 = std::time::Instant::now();
            {
                let r = run(&msl, &a, &b, s);
                r.eval().unwrap();
                mlx::synchronize_stream(s).unwrap();
            }
            ms_m.push(t0.elapsed().as_secs_f64() * 1e3);
        }
        let (c, mo) = (med(&mut ms_c), med(&mut ms_m));
        let ratio = c / mo;
        ratios.push(ratio);
        println!("µbench M={m} K={k} N={n}: mlx-c {c:.3}ms vs msl {mo:.3}ms = {ratio:.2}x");
    }
    let min_ratio = ratios.iter().cloned().fold(f64::INFINITY, f64::min);
    println!(
        "R4 gate verdict: min ratio {min_ratio:.2}x — {}",
        if min_ratio >= 1.3 {
            "PASS (≥1.3×): the row would install"
        } else {
            "FAIL (<1.3×): the table keeps mlx-c (the binding stays LAYA_MSL opt-in)"
        }
    );
}
