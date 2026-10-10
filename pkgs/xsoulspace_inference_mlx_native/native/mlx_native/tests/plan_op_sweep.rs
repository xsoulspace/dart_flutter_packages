//! ADR 0054 parity-of-composition sweep: every op kind the three drivers
//! (laya, qwen3, lfm2) submit is checked bit-for-bit between the two ways a
//! forward can reach the binding table — the direct imperative dispatch
//! (`bindings::eval` on a bare node) and the declared-plan executor
//! (`plan::execute_outputs` over a one-op plan with Input nodes). The
//! per-model gates prove whole-forward identity on pinned fixtures; this
//! sweep proves the EXECUTOR itself is transparent per op cell, so the
//! next model (or the next Op variant) is mechanically covered when it
//! adds a cell here.
//!
//! Skips (with a note) without a Metal device. Review law: a new Op
//! variant must add its cell below — keep the list total over the enum.

use mlx_native::bindings::{eval, BindingTable};
use mlx_native::mlx::{self, Array, Dtype};
use mlx_native::plan::{ExecOptions, ExecPool, Node, Op, Plan, PlanBuilder, Slot};

const D: usize = 64; // head_dim
const H: usize = 2048; // hidden
const L: usize = 8; // sequence

struct Cell {
    name: &'static str,
    op: Op,
    /// Input builders (called once per leg so the two legs never share
    /// arrays — catches aliasing mistakes, not just math).
    inputs: fn() -> Vec<Array>,
}

fn cells() -> Vec<Cell> {
    let mut v: Vec<Cell> = Vec::new();
    let mut push =
        |name: &'static str, op: Op, inputs: fn() -> Vec<Array>| v.push(Cell { name, op, inputs });

    // ---- elementwise (the f16 activation dtype every driver rides) ----
    push("binary.add.f16", Op::Binary { kind: mlx_native::plan::BinKind::Add }, || {
        vec![f16(L, H, 97), f16(L, H, 61)]
    });
    push("binary.mul.f16", Op::Binary { kind: mlx_native::plan::BinKind::Mul }, || {
        vec![f16(L, H, 97), f16(L, H, 61)]
    });
    push("unary.sigmoid.f16", Op::Unary { kind: mlx_native::plan::UnaryKind::Sigmoid }, || {
        vec![f16(L, H, 97)]
    });
    // The reference relu promotes to f32 (the model.rs lesson) — the
    // executor must reproduce the promotion identically.
    push("unary.relu.f32-promotion", Op::Unary { kind: mlx_native::plan::UnaryKind::Relu }, || {
        vec![f16(L, H, 97)]
    });
    // ---- norms (the R4 fused row is default-on: both it and its
    // Add+RmsNorm composition must be executor-transparent) ----
    push("rms_norm.f16", Op::RmsNorm { eps: 1e-5 }, || vec![f16(L, H, 97), f16_shaped(&[H], 251)]);
    push("rms_norm_residual.f16", Op::RmsNormResidual { eps: 1e-5 }, || {
        vec![f16(L, H, 97), f16(L, H, 61), f16_shaped(&[H], 251)]
    });
    // ---- quantized affine (q4 group 64 — the 4-bit checkpoint cell) ----
    push(
        "quantized_matmul.q4.g64",
        Op::QuantizedMatmul { group_size: 64, bits: 4, transpose: true },
        || {
            let (out, group, bits) = (256usize, 64usize, 4usize);
            let packed_cols = H * bits / 32; // u32 words per output row
            let per_row = H / group; // scales/biases per output row
            vec![
                f16(L, H, 97),
                u32(out, packed_cols),
                f16(out, per_row, 251),
                f16(out, per_row, 61),
            ]
        },
    );
    push("dequantize.q4.g64", Op::Dequantize { group_size: 64, bits: 4 }, || {
        let (rows, group, bits) = (64usize, 64usize, 4usize);
        let packed_cols = H * bits / 32;
        let per_row = H / group;
        vec![u32(rows, packed_cols), f16(rows, per_row, 251), f16(rows, per_row, 61)]
    });
    // ---- attention primitives ----
    push(
        "rope.offset0",
        Op::Rope { dims: D as i32, base: 1_000_000.0, offset: 0 },
        || vec![f16_4d(1, 8, L, D, 97)],
    );
    push(
        "rope.offset100",
        Op::Rope { dims: D as i32, base: 1_000_000.0, offset: 100 },
        || vec![f16_4d(1, 8, L, D, 97)],
    );
    push("sdp.causal", Op::Sdp { scale: (D as f32).powf(-0.5), causal: true }, || {
        vec![f16_4d(1, 4, L, D, 97), f16_4d(1, 4, L, D, 61), f16_4d(1, 4, L, D, 13)]
    });
    push("sdp.no_mask", Op::Sdp { scale: (D as f32).powf(-0.5), causal: false }, || {
        vec![f16_4d(1, 4, L, D, 97), f16_4d(1, 4, L, D, 61), f16_4d(1, 4, L, D, 13)]
    });
    // ---- cache ops (bf16 buffers — the KV/conv state policy) ----
    push(
        "slice_update.bf16",
        Op::SliceUpdate { start: vec![0, 0, 4, 0], stop: vec![1, 8, 8, 64], strides: vec![1, 1, 1, 1] },
        || vec![bf16_4d(1, 8, 16, D), f16_4d(1, 8, 4, D, 97)],
    );
    push(
        "slice.view.bf16",
        Op::Slice { start: vec![0, 0, 0, 0], stop: vec![1, 8, 12, 64], strides: vec![1, 1, 1, 1] },
        || vec![bf16_4d(1, 8, 16, D)],
    );
    // ---- lfm2 short conv (the R6 op): input [1, state+L, hidden] bf16,
    // depthwise weight [hidden, kernel, 1] bf16 ----
    push(
        "conv1d.depthwise",
        Op::Conv1d { stride: 1, padding: 0, dilation: 1, groups: H as i32 },
        || vec![bf16_3d(1, 2 + L, H), bf16_3d(H, 3, 1)],
    );
    push("split.3", Op::Split { num: 3, axis: -1 }, || vec![f16_3d(1, L, 3 * H, 97)]);
    // ---- gather / shape ----
    push("take.flat_gather", Op::Take, || vec![f16(64, H, 97), idx(L, 64)]);
    push("arange_i32", Op::ArangeI32 { start: 0, stop: 128 }, || vec![]);
    push("reshape.3d", Op::Reshape { shape: vec![2, 4, H] }, || vec![f16(L, H, 97)]);
    push(
        "transpose.bhld-to-blhd",
        Op::Transpose { axes: vec![0, 2, 1, 3] },
        || vec![f16_4d(1, 4, L, D, 97)],
    );
    push("concatenate.axis1", Op::Concatenate { axis: 1 }, || {
        vec![f16_3d(1, 2, H, 97), f16_3d(1, L, H, 61)]
    });
    push("const_i32", Op::ConstI32 { value: H as i32 }, || vec![]);
    push("full.f32", Op::Full { value: 0.0, dtype: Dtype::Float32, shape: vec![2, 8] }, || vec![]);
    v
}

/// [r, c] f16 pattern.
fn f16(r: usize, c: usize, modulus: u16) -> Array {
    let mut v = vec![0u8; r * c * 2];
    for (i, chunk) in v.chunks_exact_mut(2).enumerate() {
        let bits = (0x3800u16.wrapping_add((i % modulus as usize) as u16)).to_le_bytes();
        chunk[0] = bits[0];
        chunk[1] = bits[1];
    }
    Array::from_data_f16(&v, &[r, c]).unwrap()
}

/// [1, a, b, c, d] f16 pattern.
fn f16_4d(a: usize, b: usize, c: usize, d: usize, modulus: u16) -> Array {
    f16_shaped(&[a, b, c, d], modulus)
}

/// [1, a, b, c] f16 pattern.
fn f16_3d(a: usize, b: usize, c: usize, modulus: u16) -> Array {
    f16_shaped(&[a, b, c], modulus)
}

fn f16_shaped(shape: &[usize], modulus: u16) -> Array {
    let len: usize = shape.iter().product();
    let mut v = vec![0u8; len * 2];
    for (i, chunk) in v.chunks_exact_mut(2).enumerate() {
        let bits = (0x3800u16.wrapping_add((i % modulus as usize) as u16)).to_le_bytes();
        chunk[0] = bits[0];
        chunk[1] = bits[1];
    }
    Array::from_data_f16(&v, shape).unwrap()
}

fn bf16_4d(a: usize, b: usize, c: usize, d: usize) -> Array {
    bf16_bits(a * b * c * d, &[a, b, c, d])
}
fn bf16_3d(a: usize, b: usize, c: usize) -> Array {
    bf16_bits(a * b * c, &[a, b, c])
}
/// bf16 with a deterministic payload (f32 pattern truncated to bf16).
fn bf16_bits(len: usize, shape: &[usize]) -> Array {
    let mut bytes = Vec::with_capacity(len * 2);
    for i in 0..len {
        let x = ((i % 251) as f32) / 16.0 - 8.0;
        bytes.extend_from_slice(&((x.to_bits() >> 16) as u16).to_le_bytes());
    }
    Array::from_data_bf16(&bytes, shape).unwrap()
}

fn u32(r: usize, c: usize) -> Array {
    let v: Vec<u32> = (0..r * c).map(|i| (i as u32).wrapping_mul(0x9E3779B9)).collect();
    Array::from_data_u32(&v, &[r, c]).unwrap()
}

fn idx(len: usize, modulus: usize) -> Array {
    let v: Vec<i32> = (0..len).map(|i| (i % modulus) as i32).collect();
    Array::from_data_i32(&v, &[len]).unwrap()
}

#[test]
fn plan_executor_is_bit_transparent_per_op() {
    let metallib = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        mlx_native::mlx::set_metallib_path(&metallib);
    }
    let Ok(s) = mlx::gpu() else {
        eprintln!("skipping: no Metal device");
        return;
    };
    let table = BindingTable::baseline();

    let mut checked = 0usize;
    for cell in cells() {
        // Leg A: the direct imperative dispatch.
        let ins_a = (cell.inputs)();
        let refs_a: Vec<&Array> = ins_a.iter().collect();
        let node_a = Node {
            name: cell.name.to_string(),
            group: "sweep".into(),
            op: cell.op.clone(),
            inputs: Vec::new(),
            dump: None,
        };
        let direct = eval(&node_a, &refs_a, &table, s).expect("direct eval");

        // Leg B: the same op as a declared plan (Input nodes per arg). The
        // executor aliases slot 0 of each declared node, so fanout slots
        // past 0 (the fused rms_norm_residual's sum) ride Identity
        // pass-through nodes — bit-transparent by construction.
        let ins_b = (cell.inputs)();
        let mut b = PlanBuilder::default();
        let slots: Vec<Slot> =
            (0..ins_b.len()).map(|i| (b.input(&format!("in{i}"), None), 0)).collect();
        let out = b.push("sweep", cell.op.clone(), "out", &slots, None);
        let fanout = cell.op.fanout() as usize;
        let mut outputs = vec![out];
        for slot in 1..fanout {
            let id = b.push("sweep", Op::Identity, &format!("out.slot{slot}"), &[(out, slot as u8)], None);
            outputs.push(id);
        }
        let plan = Plan { nodes: b.nodes, logits: out, act: out, ctx: b.ctx, outputs };
        let refs_b: Vec<&Array> = ins_b.iter().collect();
        let planned = mlx_native::plan::execute_outputs(
            &plan,
            &ExecPool { arrays: refs_b },
            &table,
            s,
            ExecOptions::tracing(),
        )
        .expect("plan eval");

        assert_eq!(direct.len(), planned.len(), "{}: output count diverges", cell.name);
        for (o, (a, p)) in direct.iter().zip(planned.iter()).enumerate() {
            let ab = raw_bits(a, s);
            let pb = raw_bits(p, s);
            assert_eq!(
                ab, pb,
                "{} output {o}: plan executor is not bit-identical to the direct binding dispatch",
                cell.name
            );
        }
        checked += 1;
    }
    println!("plan-op sweep: {checked} cells bit-identical (plan executor vs direct dispatch)");
}

/// Full raw-bits readback: everything the sweep produces is exactly
/// representable in f32 (f16/bf16 widen losslessly; the i32 cells hold
/// values far below 2^24), so an exact f32-bit comparison is an exact
/// storage-bit comparison with no float math in the checker.
fn raw_bits(a: &Array, s: mlx::Stream) -> Vec<u64> {
    debug_assert!(!matches!(a.dtype(), Dtype::Float64 | Dtype::Complex64));
    a.astype(Dtype::Float32, s)
        .unwrap()
        .to_f32_vec(s)
        .unwrap()
        .into_iter()
        .map(|x| x.to_bits() as u64)
        .collect()
}
