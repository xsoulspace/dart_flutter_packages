//! Binding tables (ADR 0054 §2): every plan node resolves its implementation
//! through a table keyed (op × chip family × shape class × dtype). mlx-c is
//! the first binding — exactly the op calls the imperative forward made — and
//! quantized variants (R3) and MSL kernels (R4) land as new rows. A binding
//! that fails its gate is not installed; the table keeps mlx-c.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use crate::mlx::{Array, Dtype, MlxError, MlxResult, Stream};
use crate::plan::{BinKind, Node, Op, UnaryKind};

/// Chip families differ in bandwidth, tile shapes, and scheduler behavior.
/// Only rows measured on the detected family may carry claims (ADR 0054 §3:
/// other families are declarations, never performance statements).
#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ChipFamily {
    M1,
    M2,
    M3,
    M4,
}

impl ChipFamily {
    /// Detects this machine's family from `sysctl machdep.cpu.brand_string`
    /// ("Apple M1 Pro" → M1). Unrecognized SoCs resolve to None — callers
    /// fall back to the mlx-c binding (which is chip-agnostic).
    pub fn detect() -> Option<ChipFamily> {
        let out = std::process::Command::new("sysctl")
            .args(["-n", "machdep.cpu.brand_string"])
            .output()
            .ok()?;
        let brand = String::from_utf8_lossy(&out.stdout).to_lowercase();
        if !brand.contains("apple m") {
            return None;
        }
        let rest = brand.split("apple m").nth(1)?.trim_start();
        let digit = rest.chars().next()?;
        Some(match digit {
            '1' => ChipFamily::M1,
            '2' => ChipFamily::M2,
            '3' => ChipFamily::M3,
            '4' => ChipFamily::M4,
            _ => return None,
        })
    }
}

/// The granularity kernels are tuned at (ADR 0054 §2).
#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ShapeClass {
    Constant,
    /// Batched matmul whose effective M (product of batch dims) is small —
    /// the weight-stationary regime R4's skinny GEMM targets (M ≤ 128).
    SkinnyGemm,
    /// Effective M == 1 — pure GEMV (decode): the fused dequant-GEMV
    /// binding's regime (R3/R4).
    Gemv,
    WideGemm,
    Attention,
    Elementwise,
    Reduction,
    Shape,
    Gather,
    Generic,
}

impl ShapeClass {
    pub fn classify(op: &Op, ins: &[&Array]) -> ShapeClass {
        match op {
            Op::ConstF32 { .. }
            | Op::ConstI32 { .. }
            | Op::ConstBool { .. }
            | Op::ArangeI32 { .. }
            | Op::Full { .. } => ShapeClass::Constant,
            Op::Matmul => {
                // Effective M = product of all leading dims of the left operand.
                let a = &ins[0];
                let m: usize = (0..a.ndim().saturating_sub(1)).map(|d| a.dim(d as i32)).product();
                if m > 0 && m <= 128 {
                    ShapeClass::SkinnyGemm
                } else {
                    ShapeClass::WideGemm
                }
            }
            // M == 1 is the pure-GEMV decode regime (R3/R4's fused
            // dequant-GEMV); 2..=128 stays the skinny-GEMM class.
            Op::QuantizedMatmul { .. } => {
                let a = &ins[0];
                let m: usize = (0..a.ndim().saturating_sub(1)).map(|d| a.dim(d as i32)).product();
                match m {
                    1 => ShapeClass::Gemv,
                    2..=128 => ShapeClass::SkinnyGemm,
                    _ => ShapeClass::WideGemm,
                }
            }
            Op::Dequantize { .. } => ShapeClass::Elementwise,
            Op::RmsNorm { .. } | Op::RmsNormResidual { .. } => ShapeClass::Reduction,
            Op::Slice { .. } | Op::SliceUpdate { .. } | Op::Conv1d { .. } => ShapeClass::Shape,
            Op::Rope { .. } | Op::Sdp { .. } => ShapeClass::Attention,
            Op::Identity => ShapeClass::Shape,
            Op::MeanAxes { .. } | Op::SumAxes { .. } => ShapeClass::Reduction,
            Op::Transpose { .. }
            | Op::Reshape { .. }
            | Op::ExpandDims { .. }
            | Op::Squeeze { .. }
            | Op::Split { .. }
            | Op::Concatenate { .. }
            | Op::Stack { .. } => ShapeClass::Shape,
            Op::Take | Op::TakeAlongAxis { .. } => ShapeClass::Gather,
            Op::Binary { .. }
            | Op::Unary { .. }
            | Op::Sort { .. }
            | Op::Cast { .. }
            | Op::Where => ShapeClass::Elementwise,
            Op::Input { .. } | Op::External { .. } => ShapeClass::Generic,
        }
    }
}

/// The implementation behind one binding key.
#[derive(Copy, Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Backend {
    /// The vendored mlx 0.32.2 op set — the baseline binding.
    MlxC,
    /// R4's custom MSL kernel: weight-stationary skinny GEMM (M ≤ 128,
    /// fp16, f32 accumulate), source in `kernels/skinny_gemm.metal`,
    /// xcrun-compiled as a build gate, dispatched on the graph's stream
    /// through `mlx_fast_metal_kernel`.
    SkinnyGemmMsl,
    /// R3/R4's fused dequant-GEMV (M == 1, 4-bit affine, group 64): the
    /// packed weights stream once and dequantize in-register — the
    /// bandwidth-floor move. Source in `kernels/dequant_gemv.metal`.
    DequantGemmMsl,
    /// R4's fused RMSNorm+residual epilogue (one pass over the hidden
    /// tensor instead of Add-then-RmsNorm's two). Source in
    /// `kernels/rmsnorm_residual.metal`.
    RmsNormFusedMsl,
}

#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash)]
pub struct BindingKey {
    pub op: &'static str,
    pub chip: Option<ChipFamily>,
    pub shape: ShapeClass,
    pub dtype: Dtype,
}

/// The dispatch table. Unknown keys resolve to the fallback (mlx-c) — a new
/// binding earns rows; nothing else changes.
pub struct BindingTable {
    chip: Option<ChipFamily>,
    rows: HashMap<(&'static str, ShapeClass, Dtype), Backend>,
    fallback: Backend,
}

impl BindingTable {
    /// The baseline: every key resolves to mlx-c. Rungs add rows via
    /// [`BindingTable::install`]. LAYA_MSL=1 (the R4 gate's opt-in)
    /// installs the skinny-GEMM MSL row so the parity leg exercises it;
    /// the default table keeps mlx-c until the ≥1.3× µbench gate passes.
    pub fn baseline() -> BindingTable {
        let mut table = BindingTable {
            chip: ChipFamily::detect(),
            rows: HashMap::new(),
            fallback: Backend::MlxC,
        };
        if std::env::var_os("LAYA_MSL").is_some_and(|v| !v.is_empty()) {
            table.install(
                "matmul",
                ShapeClass::SkinnyGemm,
                Dtype::Float16,
                Backend::SkinnyGemmMsl,
            );
        }
        // R4's fused RMSNorm+residual PASSED its gate (≥1.3× µbench on the
        // tuned family + 64/64 greedy parity with the kernel live — the
        // round-to-nearest store matches mlx's conversion exactly), so per
        // the gate design this row installs by default; LAYA_MSL_NORM=0
        // keeps the mlx-c composition for A/B.
        if std::env::var_os("LAYA_MSL_NORM").map(|v| v != "0").unwrap_or(true) {
            table.install(
                "rms_norm_residual",
                ShapeClass::Reduction,
                Dtype::BFloat16,
                Backend::RmsNormFusedMsl,
            );
        }
        if std::env::var_os("LAYA_MSL_GEMV").is_some_and(|v| !v.is_empty()) {
            table.install(
                "quantized_matmul",
                ShapeClass::Gemv,
                Dtype::BFloat16,
                Backend::DequantGemmMsl,
            );
        }
        table
    }

    pub fn chip(&self) -> Option<ChipFamily> {
        self.chip
    }

    /// Installs a tuned binding for one key (the R3/R4 entry point). Rows are
    /// keyed without the chip dimension because the table serves ONE machine;
    /// the detected family is recorded alongside for the plan JSON.
    pub fn install(&mut self, op: &'static str, shape: ShapeClass, dtype: Dtype, backend: Backend) {
        self.rows.insert((op, shape, dtype), backend);
    }

    pub fn resolve(&self, op: &'static str, shape: ShapeClass, dtype: Dtype) -> Backend {
        self.rows
            .get(&(op, shape, dtype))
            .copied()
            .unwrap_or(self.fallback)
    }

    /// Non-fallback rows, for the plan JSON's binding section.
    pub fn overrides(&self) -> Vec<serde_json::Value> {
        let mut rows: Vec<_> = self
            .rows
            .iter()
            .map(|((op, shape, dtype), backend)| {
                serde_json::json!({
                    "op": op,
                    "shape_class": shape,
                    "dtype": crate::plan::dtype_json(*dtype),
                    "backend": backend,
                })
            })
            .collect();
        rows.sort_by_key(|r| r["op"].as_str().map(str::to_string));
        rows
    }
}

/// Executes one node through the binding table. This is THE dispatch point:
/// resolve (op × chip × shape class × dtype) → backend → op call.
pub fn eval(node: &Node, ins: &[&Array], table: &BindingTable, s: Stream) -> MlxResult<Vec<Array>> {
    let shape = ShapeClass::classify(&node.op, ins);
    let dtype = ins.first().map(|a| a.dtype()).unwrap_or(Dtype::Float32);
    let backend = table.resolve(node.op.kind(), shape, dtype);
    match backend {
        Backend::MlxC => mlxc_eval(&node.op, ins, s),
        Backend::SkinnyGemmMsl => skinny_gemm_eval(&node.op, ins, s),
        Backend::DequantGemmMsl => dequant_gemv_eval(&node.op, ins, s),
        Backend::RmsNormFusedMsl => rmsnorm_residual_eval(&node.op, ins, s),
    }
}

/// The dequant-GEMV kernel's MSL source (body-only; see build_msl.sh).
const DEQUANT_GEMV_MSL: &str = include_str!("kernels/dequant_gemv.metal");

/// The R3/R4 fused dequant-GEMV binding for (quantized_matmul × Gemv ×
/// bf16): out[1, N] = x[1, K] × dequant(W). The packed U32 weights stream
/// once, coalesced along K per warp; nibbles dequantize in-register —
/// no fp16/bf16 weight materialization ever exists.
fn dequant_gemv_eval(op: &Op, ins: &[&Array], s: Stream) -> MlxResult<Vec<Array>> {
    use std::sync::OnceLock;
    static KERNEL: OnceLock<Option<crate::mlx::MetalKernel>> = OnceLock::new();
    let Op::QuantizedMatmul { group_size, bits, transpose: true } = op else {
        return Err(MlxError(-975));
    };
    if *group_size != 64 || *bits != 4 {
        // The kernel's nibble/group math is fixed at affine 4-bit / 64.
        return Err(MlxError(-975));
    }
    let [x, w, scales, biases] = ins else {
        return Err(MlxError(-978));
    };

    let m: usize = (0..x.ndim().saturating_sub(1)).map(|d| x.dim(d as i32)).product();
    if m != 1 {
        return Err(MlxError(-975)); // Gemv class only
    }
    let k = x.dim(x.ndim() as i32 - 1) as usize;
    let n = w.dim(0) as usize;

    let kernel = KERNEL.get_or_init(|| {
        crate::mlx::MetalKernel::new(
            "laya_dequant_gemv",
            &["x", "w", "scales", "biases", "nk"],
            &["out"],
            DEQUANT_GEMV_MSL,
        )
        .map(Some)
        .unwrap_or_else(|e| {
            eprintln!("dequant_gemv kernel init failed: {e:?}");
            None
        })
    });
    let Some(kernel) = kernel else { return Err(MlxError(-974)) };

    let nk = Array::from_data_i32(&[n as i32, k as i32], &[2])?;
    let ins_all: Vec<&Array> = vec![x, w, scales, biases, &nk];
    // One warp per output row n; threadgroups pack 8 warps.
    let warps = n as i32;
    let total_threads = warps * 32;
    let outs = kernel.apply(
        &ins_all,
        &[&[1, n]],
        crate::mlx::Dtype::BFloat16,
        (total_threads, 1, 1),
        (256, 1, 1),
        s,
    )?;
    Ok(vec![outs
        .into_iter()
        .next()
        .ok_or(MlxError(-978))?
        .reshape(&[1, 1, n], s)?])
}

/// The fused RMSNorm+residual kernel's MSL source (body-only).
const RMSNORM_RESIDUAL_MSL: &str = include_str!("kernels/rmsnorm_residual.metal");

/// The R4 fused epilogue binding for (rms_norm_residual × Reduction ×
/// bf16): out = rms_norm(x + residual, w) in one pass — one read of each
/// input and one write, instead of the composition's two round trips.
fn rmsnorm_residual_eval(op: &Op, ins: &[&Array], s: Stream) -> MlxResult<Vec<Array>> {
    use std::sync::OnceLock;
    static KERNEL: OnceLock<Option<crate::mlx::MetalKernel>> = OnceLock::new();
    let Op::RmsNormResidual { eps } = op else {
        return Err(MlxError(-975));
    };
    let [x, residual, weight] = ins else {
        return Err(MlxError(-978));
    };
    let rows: usize = (0..x.ndim().saturating_sub(1)).map(|d| x.dim(d as i32)).product();
    let cols = x.dim(x.ndim() as i32 - 1) as usize;

    let kernel = KERNEL.get_or_init(|| {
        crate::mlx::MetalKernel::new(
            "laya_rmsnorm_residual",
            &["x", "r", "w", "eps", "shape"],
            &["sum", "out"],
            RMSNORM_RESIDUAL_MSL,
        )
        .map(Some)
        .unwrap_or_else(|e| {
            eprintln!("rmsnorm_residual kernel init failed: {e:?}");
            None
        })
    });
    let Some(kernel) = kernel else { return Err(MlxError(-974)) };

    let eps_arr = Array::from_data_f32(&[*eps], &[1])?;
    let shape_arr = Array::from_data_i32(
        &[rows as i32, cols as i32],
        &[2],
    )?;
    let ins_all: Vec<&Array> = vec![x, residual, weight, &eps_arr, &shape_arr];
    // One 256-wide threadgroup per row; cols are strided across threads.
    // Grid = total threads (256 per row).
    let total_threads = rows as i32 * 256;
    // Outputs [sum, normed].
    let outs = kernel.apply(
        &ins_all,
        &[&[rows, cols], &[rows, cols]],
        crate::mlx::Dtype::BFloat16,
        (total_threads, 1, 1),
        (256, 1, 1),
        s,
    )?;
    let mut shape: Vec<usize> =
        (0..x.ndim().saturating_sub(1)).map(|d| x.dim(d as i32) as usize).collect();
    shape.push(cols);
    let mut arrays = outs.into_iter();
    let sum = arrays.next().ok_or(MlxError(-978))?.reshape(&shape, s)?;
    let normed = arrays.next().ok_or(MlxError(-978))?.reshape(&shape, s)?;
    Ok(vec![sum, normed])
}

/// The skinny-GEMM MSL kernel's MSL source (xcrun-compiles clean; see
/// tool/build_msl.sh for the build gate).
const SKINNY_GEMM_MSL: &str = include_str!("kernels/skinny_gemm.metal");

/// The R4 kernel binding for (matmul × SkinnyGemm × f16). C = A × B with
/// B already the plan's post-transpose [K, N] view — no materialized
/// transpose, weight-stationary streaming along K.
fn skinny_gemm_eval(op: &Op, ins: &[&Array], s: Stream) -> MlxResult<Vec<Array>> {
    use std::sync::OnceLock;
    static KERNEL: OnceLock<Option<crate::mlx::MetalKernel>> = OnceLock::new();
    if !matches!(op, Op::Matmul) {
        return Err(MlxError(-975));
    }
    let [a, b] = ins else { return Err(MlxError(-978)) };

    let m: usize = (0..a.ndim().saturating_sub(1)).map(|d| a.dim(d as i32)).product();
    let k = a.dim(a.ndim() as i32 - 1) as usize;
    let n = b.dim(1) as usize;

    let kernel = KERNEL.get_or_init(|| {
        crate::mlx::MetalKernel::new(
            "laya_skinny_gemm",
            &["a", "b", "mnk"],
            &["out"],
            SKINNY_GEMM_MSL,
        )
        .map(Some)
        .unwrap_or_else(|e| {
            eprintln!("skinny_gemm kernel init failed: {e:?}");
            None
        })
    });
    let Some(kernel) = kernel else { return Err(MlxError(-974)) };

    let mnk = Array::from_data_i32(&[m as i32, n as i32, k as i32], &[3])?;
    let ins_all: Vec<&Array> = vec![a, b, &mnk];
    // Grid = total threads (flat 1-D), one 256-wide threadgroup per
    // (m, n-tile); the kernel body derives (m, n) from the flat group id.
    let n_tiles = n.div_ceil(256);
    let total_threads = m * n_tiles * 256;
    let outs = kernel.apply(
        &ins_all,
        &[&[m, n]],
        crate::mlx::Dtype::Float16,
        (total_threads as i32, 1, 1),
        (256, 1, 1),
        s,
    )?;
    // Restore the batch dims the plan's matmul contract promises (A's
    // leading dims + N): flatten to [M, N] ran through the kernel; the
    // plan expects [B, L, N] — reshape from the row-major [M, N] buffer.
    let mut shape: Vec<usize> =
        (0..a.ndim().saturating_sub(1)).map(|d| a.dim(d as i32) as usize).collect();
    shape.push(n);
    Ok(vec![outs.into_iter().next().ok_or(MlxError(-978))?.reshape(&shape, s)?])
}

/// The mlx-c binding: the exact op calls the imperative forward made
/// (operand order, dtype chains, and stream handling preserved).
fn mlxc_eval(op: &Op, ins: &[&Array], s: Stream) -> MlxResult<Vec<Array>> {
    fn two<'a>(ins: &[&'a Array]) -> MlxResult<(&'a Array, &'a Array)> {
        match ins {
            [a, b] => Ok((a, b)),
            _ => Err(MlxError(-978)),
        }
    }
    fn one<'a>(ins: &[&'a Array]) -> MlxResult<&'a Array> {
        match ins {
            [a] => Ok(a),
            _ => Err(MlxError(-978)),
        }
    }
    match op {
        // Declaration-only (ADR 0054 §4): never wired into the dataflow, so
        // the executor never dispatches it; this guards misuse.
        Op::External { program, .. } => {
            eprintln!("plan: external program node is not GPU-executable: {program}");
            return Err(MlxError(-977));
        }
        Op::Input { .. } => return Err(MlxError(-976)), // resolved from the pool by the executor
        Op::Identity => return Ok(vec![one(ins)?.identity(s)?]),
        Op::ConstF32 { value } => return Ok(vec![Array::scalar_f32(*value)]),
        Op::ConstI32 { value } => return Ok(vec![Array::scalar_i32(*value)]),
        Op::ConstBool { value } => return Ok(vec![Array::scalar_bool(*value)]),
        Op::ArangeI32 { start, stop } => return Ok(vec![Array::arange_i32(*start, *stop, s)?]),
        Op::Full { value, dtype, shape } => return Ok(vec![Array::full(*value, shape, *dtype, s)?]),
        Op::Binary { kind } => {
            let (a, b) = two(ins)?;
            return Ok(vec![match kind {
                BinKind::Add => a.add(b, s)?,
                BinKind::Sub => a.sub(b, s)?,
                BinKind::Mul => a.mul(b, s)?,
                BinKind::Div => a.div(b, s)?,
                BinKind::Max => a.max_elemwise(b, s)?,
                BinKind::Min => a.min_elemwise(b, s)?,
                BinKind::LessEqual => a.less_equal(b, s)?,
            }]);
        }
        Op::Unary { kind } => {
            let a = one(ins)?;
            return Ok(vec![match kind {
                UnaryKind::Abs => a.abs(s)?,
                UnaryKind::Erf => a.erf(s)?,
                UnaryKind::Exp => a.exp(s)?,
                UnaryKind::Log => a.log(s)?,
                UnaryKind::Sqrt => a.sqrt(s)?,
                UnaryKind::Softmax => a.softmax(s)?,
                // MLXNN.relu == maximum(x, 0).
                UnaryKind::Relu => a.max_elemwise(&Array::scalar_f32(0.0), s)?,
                // MLXNN.silu == x * sigmoid(x) — kept as the same two ops.
                UnaryKind::Sigmoid => a.sigmoid(s)?,
            }]);
        }
        Op::Sort { axis } => {
            return Ok(vec![one(ins)?.sort_axis(*axis, s)?]);
        }
        Op::Cast { dtype } => {
            return Ok(vec![one(ins)?.astype(*dtype, s)?]);
        }
        Op::MeanAxes { axes, keepdims } => {
            return Ok(vec![one(ins)?.mean_axes(axes, *keepdims, s)?]);
        }
        Op::SumAxes { axes, keepdims } => {
            return Ok(vec![one(ins)?.sum_axes(axes, *keepdims, s)?]);
        }
        Op::Matmul => {
            let (a, b) = two(ins)?;
            return Ok(vec![a.matmul(b, s)?]);
        }
        Op::Take => {
            let (a, idx) = two(ins)?;
            return Ok(vec![a.take(idx, s)?]);
        }
        Op::TakeAlongAxis { axis } => {
            let (a, idx) = two(ins)?;
            return Ok(vec![a.take_along_axis(idx, *axis, s)?]);
        }
        Op::Transpose { axes } => {
            return Ok(vec![one(ins)?.transpose_axes(axes, s)?]);
        }
        Op::Reshape { shape } => {
            return Ok(vec![one(ins)?.reshape(shape, s)?]);
        }
        Op::ExpandDims { axes } => {
            return Ok(vec![one(ins)?.expand_dims(axes, s)?]);
        }
        Op::Squeeze { axes } => {
            return Ok(vec![one(ins)?.squeeze_axes(axes, s)?]);
        }
        Op::Split { num, axis } => {
            return Ok(one(ins)?.split_n(*num as i32, *axis, s)?);
        }
        Op::Concatenate { axis } => {
            return Ok(vec![Array::concatenate_axis(ins, *axis, s)?]);
        }
        Op::Stack { axis } => {
            return Ok(vec![Array::stack_axis(ins, *axis, s)?]);
        }
        Op::Where => {
            match ins {
                [cond, x, y] => return Ok(vec![Array::where_(cond, x, y, s)?]),
                _ => return Err(MlxError(-978)),
            }
        }
        Op::Rope { dims, base, offset } => {
            return Ok(vec![one(ins)?.rope(*dims, *base, *offset, s)?]);
        }
        Op::Sdp { scale, causal } => match (ins, *causal) {
            // keep-mask path (laya), no-mask decode (qwen), native causal
            // prefill (qwen).
            ([q, k, v, mask], false) => {
                return Ok(vec![Array::sdp_attention(q, k, v, *scale, mask, s)?])
            }
            ([q, k, v], false) => {
                return Ok(vec![Array::sdp_attention_mode(q, k, v, *scale, "", None, s)?])
            }
            ([q, k, v], true) => {
                return Ok(vec![Array::sdp_attention_mode(q, k, v, *scale, "causal", None, s)?])
            }
            _ => return Err(MlxError(-978)),
        },
        Op::QuantizedMatmul { group_size, bits, transpose } => match ins {
            [x, w, scales, biases] => Ok(vec![Array::quantized_matmul(
                x,
                w,
                scales,
                biases,
                *transpose,
                *group_size,
                *bits,
                s,
            )?]),
            _ => Err(MlxError(-978)),
        },
        Op::Dequantize { group_size, bits } => match ins {
            [w, scales, biases] => {
                return Ok(vec![Array::dequantize(w, scales, biases, *group_size, *bits, s)?])
            }
            _ => return Err(MlxError(-978)),
        },
        Op::RmsNorm { eps } => match ins {
            [x, weight] => return Ok(vec![Array::rms_norm(x, weight, *eps, s)?]),
            _ => return Err(MlxError(-978)),
        },
        Op::RmsNormResidual { eps } => match ins {
            // The mlx-c binding: exactly the composition it replaces,
            // outputs [sum, normed].
            [x, residual, weight] => {
                let sum = x.add(residual, s)?;
                let normed = Array::rms_norm(&sum, weight, *eps, s)?;
                return Ok(vec![sum, normed]);
            }
            _ => return Err(MlxError(-978)),
        },
        Op::Slice { start, stop, strides } => {
            return Ok(vec![one(ins)?.slice(start, stop, strides, s)?]);
        }
        Op::Conv1d { stride, padding, dilation, groups } => match ins {
            [input, weight] => {
                return Ok(vec![crate::mlx::conv1d(
                    input,
                    weight,
                    *stride,
                    *padding,
                    *dilation,
                    *groups,
                    s,
                )?])
            }
            _ => return Err(MlxError(-978)),
        },
        Op::SliceUpdate { start, stop, strides } => match ins {
            [src, update] => {
                return Ok(vec![Array::slice_update(src, update, start, stop, strides, s)?])
            }
            _ => return Err(MlxError(-978)),
        },
    }
}
