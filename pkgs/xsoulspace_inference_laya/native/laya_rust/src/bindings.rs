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
    /// [`BindingTable::install`].
    pub fn baseline() -> BindingTable {
        BindingTable {
            chip: ChipFamily::detect(),
            rows: HashMap::new(),
            fallback: Backend::MlxC,
        }
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
    }
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
        Op::Sdp { scale } => {
            match ins {
                [q, k, v, mask] => {
                    return Ok(vec![Array::sdp_attention(q, k, v, *scale, mask, s)?])
                }
                _ => return Err(MlxError(-978)),
            }
        }
    }
}
