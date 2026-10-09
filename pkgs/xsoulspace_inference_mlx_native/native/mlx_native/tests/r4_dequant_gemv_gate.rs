//! ADR 0054 R3/R4 gate: the fused dequant-GEMV MSL binding vs mlx-c's
//! quantized_matmul it would replace (M == 1 decode GEMV, 4-bit affine,
//! group 64, bf16). Gate shape per the mission:
//!   1. correctness: kernel ≈ mlx-c within bf16/accumulate tolerance;
//!   2. µbench ≥1.3× vs mlx-c — else the table keeps mlx-c (the binding
//!      stays behind LAYA_MSL_GEMV=1, opt-in only).
//! Run: cargo test --release --test r4_dequant_gemv_gate -- --ignored --nocapture

use mlx_native::bindings::{Backend, BindingTable, ShapeClass};
use mlx_native::mlx::{self, Array, Dtype};

fn bf16_bytes(count: usize, modulus: u16) -> Vec<u8> {
    // bf16 pattern ~0.5..1.x (exponent of 0.5, varying mantissa).
    let mut v = vec![0u8; count * 2];
    for (i, chunk) in v.chunks_exact_mut(2).enumerate() {
        let bits = 0x3F00u16.wrapping_add(((i % 251) % (modulus as usize)) as u16);
        chunk[0] = (bits & 0xFF) as u8;
        chunk[1] = (bits >> 8) as u8;
    }
    v
}

struct QWeights {
    w: Array,
    scales: Array,
    biases: Array,
}

fn quantized_inputs(n: usize, k: usize) -> (Array, QWeights) {
    // Real 4-bit weights: quantize random bf16 with mlx itself, so the
    // gate compares two implementations over the SAME packed values.
    let w_fp = Array::from_data_bf16(&bf16_bytes(n * k, 61), &[n, k]).unwrap();
    let outs = Array::quantize(&w_fp, 64, 4, mlx::gpu().unwrap()).unwrap();
    let x = Array::from_data_bf16(&bf16_bytes(k, 97), &[1, 1, k]).unwrap();
    (
        x,
        QWeights { w: outs[0].identity(mlx::gpu().unwrap()).unwrap(), scales: outs[1].identity(mlx::gpu().unwrap()).unwrap(), biases: outs[2].identity(mlx::gpu().unwrap()).unwrap() },
    )
}

fn run(table: &BindingTable, x: &Array, q: &QWeights, s: mlx::Stream) -> Array {
    let node = mlx_native::plan::Node {
        name: "gate.qmat".into(),
        group: "gate".into(),
        op: mlx_native::plan::Op::QuantizedMatmul {
            group_size: 64,
            bits: 4,
            transpose: true,
        },
        inputs: Vec::new(),
        dump: None,
    };
    mlx_native::bindings::eval(&node, &[x, &q.w, &q.scales, &q.biases], table, s)
        .unwrap()
        .into_iter()
        .next()
        .unwrap()
}

#[test]
#[ignore]
fn dequant_gemv_gate() {
    let metallib = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        mlx_native::mlx::set_metallib_path(&metallib);
    }
    let s = mlx::gpu().expect("Metal");

    let script = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../tool/build_msl.sh");
    let st = std::process::Command::new("zsh")
        .arg(script)
        .status()
        .expect("build_msl.sh runs");
    assert!(st.success(), "xcrun metal build gate failed");

    // Qwen decode shapes: per-layer q/k/v/o + mlp + the tied lm_head.
    let shapes: [(usize, usize); 5] = [
        (1024, 1024),
        (2048, 1024),
        (1024, 3072),
        (3072, 1024),
        (151936, 1024),
    ];

    let mlxc = BindingTable::baseline();
    let mut msl = BindingTable::baseline();
    msl.install("quantized_matmul", ShapeClass::Gemv, Dtype::BFloat16, Backend::DequantGemmMsl);

    for (n, k) in shapes {
        let (x, q) = quantized_inputs(n, k);
        let r_c = run(&mlxc, &x, &q, s);
        let r_m = run(&msl, &x, &q, s);
        let vc = r_c.astype(Dtype::Float32, s).unwrap().to_f32_vec(s).unwrap();
        let vm = r_m.astype(Dtype::Float32, s).unwrap().to_f32_vec(s).unwrap();
        // bf16 outputs at magnitude ~|mean|: tolerance = 2 bf16 ulps
        // relative to the output scale (the accumulate order differs).
        let diff = vc
            .iter()
            .zip(vm.iter())
            .map(|(a, b)| (a - b).abs())
            .fold(0.0f32, f32::max);
        let scale = vc.iter().fold(1.0f32, |m, v| m.max(v.abs()));
        let tol = scale * 0.02;
        println!("correct N={n} K={k}: max|diff|={diff:.4} (tol {tol:.2}, scale {scale:.1})");
        assert!(diff < tol, "dequant gemv diverged at N={n} K={k}: {diff}");
    }

    let med = |v: &mut Vec<f64>| {
        v.sort_by(|a, b| a.total_cmp(b));
        v[v.len() / 2]
    };
    let mut ratios = Vec::new();
    for (n, k) in shapes {
        let (x, q) = quantized_inputs(n, k);
        let mut ms_c = Vec::new();
        let mut ms_m = Vec::new();
        for _ in 0..7 {
            let t0 = std::time::Instant::now();
            {
                let r = run(&mlxc, &x, &q, s);
                r.eval().unwrap();
                mlx::synchronize_stream(s).unwrap();
            }
            ms_c.push(t0.elapsed().as_secs_f64() * 1e3);
            let t0 = std::time::Instant::now();
            {
                let r = run(&msl, &x, &q, s);
                r.eval().unwrap();
                mlx::synchronize_stream(s).unwrap();
            }
            ms_m.push(t0.elapsed().as_secs_f64() * 1e3);
        }
        let (c, m) = (med(&mut ms_c), med(&mut ms_m));
        let ratio = c / m;
        ratios.push(ratio);
        println!("µbench N={n} K={k}: mlx-c {c:.3}ms vs msl {m:.3}ms = {ratio:.2}x");
    }
    let min_ratio = ratios.iter().cloned().fold(f64::INFINITY, f64::min);
    println!(
        "dequant-GEMV gate verdict: min ratio {min_ratio:.2}x — {}",
        if min_ratio >= 1.3 {
            "PASS (≥1.3×): the row would install"
        } else {
            "FAIL (<1.3×): the table keeps mlx-c (the binding stays LAYA_MSL_GEMV opt-in)"
        }
    );
}
