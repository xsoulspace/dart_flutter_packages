//! Declared forward plans (ADR 0054): a forward pass is a tree of typed op
//! nodes with shape/dtype contracts, composed by builders into layers and
//! models, serialized to JSON for review, and executed through the binding
//! table. Execution submits the same op sequence — same calls, same dtype
//! chains — as the imperative forward it replaces; the golden gate guards
//! that identity.

use crate::mlx::{Array, Dtype, MlxResult, Stream};
use serde::{Deserialize, Deserializer, Serialize, Serializer};

pub type NodeId = usize;

/// Node inputs reference (node, output slot) — most ops have one output;
/// splits have `num`.
pub type Slot = (NodeId, u8);

fn dtype_tag(d: Dtype) -> &'static str {
    match d {
        Dtype::Bool => "bool",
        Dtype::UInt8 => "u8",
        Dtype::UInt16 => "u16",
        Dtype::UInt32 => "u32",
        Dtype::UInt64 => "u64",
        Dtype::Int8 => "i8",
        Dtype::Int16 => "i16",
        Dtype::Int32 => "i32",
        Dtype::Int64 => "i64",
        Dtype::Float16 => "f16",
        Dtype::Float32 => "f32",
        Dtype::Float64 => "f64",
        Dtype::BFloat16 => "bf16",
        Dtype::Complex64 => "c64",
    }
}

fn dtype_from_tag(tag: &str) -> Option<Dtype> {
    Some(match tag {
        "bool" => Dtype::Bool,
        "u8" => Dtype::UInt8,
        "u16" => Dtype::UInt16,
        "u32" => Dtype::UInt32,
        "u64" => Dtype::UInt64,
        "i8" => Dtype::Int8,
        "i16" => Dtype::Int16,
        "i32" => Dtype::Int32,
        "i64" => Dtype::Int64,
        "f16" => Dtype::Float16,
        "f32" => Dtype::Float32,
        "f64" => Dtype::Float64,
        "bf16" => Dtype::BFloat16,
        "c64" => Dtype::Complex64,
        _ => return None,
    })
}

fn serialize_dtype<S: Serializer>(d: &Dtype, s: S) -> Result<S::Ok, S::Error> {
    s.serialize_str(dtype_tag(*d))
}

fn deserialize_dtype<'de, D: Deserializer<'de>>(d: D) -> Result<Dtype, D::Error> {
    let tag = String::deserialize(d)?;
    dtype_from_tag(&tag).ok_or_else(|| serde::de::Error::custom(format!("unknown dtype {tag}")))
}

/// Serializes a dtype for the binding-table JSON (pub for bindings.rs).
pub fn dtype_json(d: Dtype) -> String {
    dtype_tag(d).to_string()
}

#[derive(Copy, Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BinKind {
    Add,
    Sub,
    Mul,
    Div,
    Max,
    Min,
    LessEqual,
}

#[derive(Copy, Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum UnaryKind {
    Abs,
    Erf,
    Exp,
    Log,
    Sqrt,
    Softmax,
    Relu,
    Sigmoid,
}

/// A typed op. Parameter values are concrete: a plan is built per request
/// shape, so every node's contract is fully determined at build time.
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub enum Op {
    /// One of the execution context's arrays (batch inputs, then weights).
    Input { index: usize },
    /// Declaration-only node for programs outside the GPU walk (the python
    /// reference runtime, laya-serve, napbench) — the plan is the whole
    /// reviewable story of the decision path (ADR 0054 §4). Never executed.
    External { program: String, note: String },
    ConstF32 { value: f32 },
    ConstI32 { value: i32 },
    ConstBool { value: bool },
    ArangeI32 { start: i32, stop: i32 },
    Full {
        value: f64,
        #[serde(serialize_with = "serialize_dtype", deserialize_with = "deserialize_dtype")]
        dtype: Dtype,
        shape: Vec<usize>,
    },
    Identity,
    Binary { kind: BinKind },
    Unary { kind: UnaryKind },
    Sort { axis: i32 },
    Cast {
        #[serde(serialize_with = "serialize_dtype", deserialize_with = "deserialize_dtype")]
        dtype: Dtype,
    },
    MeanAxes { axes: Vec<i32>, keepdims: bool },
    SumAxes { axes: Vec<i32>, keepdims: bool },
    Matmul,
    Take,
    TakeAlongAxis { axis: i32 },
    Transpose { axes: Vec<i32> },
    Reshape { shape: Vec<usize> },
    ExpandDims { axes: Vec<i32> },
    Squeeze { axes: Vec<i32> },
    Split { num: usize, axis: i32 },
    Concatenate { axis: i32 },
    Stack { axis: i32 },
    Where,
    Rope { dims: i32, base: f32, offset: i32 },
    Sdp {
        scale: f32,
        /// false: a bool keep-mask array rides the inputs (laya). true: the
        /// kernel's native causal path (python mlx-lm's prefill mask).
        #[serde(default)]
        causal: bool,
    },
    /// Affine quantized matmul (R2): inputs [x, w, scales, biases]; `w` is
    /// [out, in] packed U32 when `transpose`. The R3 fused dequant-GEMV lands
    /// as a new binding on this key.
    QuantizedMatmul { group_size: i32, bits: i32, transpose: bool },
    /// Affine dequantize (R2): inputs [w, scales, biases] — the quantized
    /// embedding's row gather tail.
    Dequantize { group_size: i32, bits: i32 },
    /// `mx.fast.rms_norm` over the last axis: inputs [x, weight].
    RmsNorm { eps: f32 },
    /// `mx.slice` — strided view (cache reads are views, python-parity).
    Slice {
        start: Vec<i32>,
        stop: Vec<i32>,
        strides: Vec<i32>,
    },
    /// `mx.slice_update` — python's `buf[..., a:b, :] = update`: inputs
    /// [src, update].
    SliceUpdate {
        start: Vec<i32>,
        stop: Vec<i32>,
        strides: Vec<i32>,
    },
}

/// mlx float promotion for our graph: f32 wins over f16, else unchanged.
pub(crate) fn promote(a: Dtype, b: Dtype) -> Dtype {
    if a == Dtype::Float32 || b == Dtype::Float32 {
        Dtype::Float32
    } else {
        a
    }
}

impl Op {
    /// Output dtype under mlx's promotion rules for our op set. The composer
    /// tracks this per node so casts can mirror the reference runtime's
    /// `x.dtype()` behavior exactly (see model.rs — the relu f32 promotion
    /// decides the decision-head tail's precision).
    pub fn output_dtype(&self, inputs: &[Slot], dtype_of: &dyn Fn(Slot) -> Dtype) -> Dtype {
        let first = |inputs: &[Slot]| dtype_of(inputs[0]);
        match self {
            // Inputs/weights register their real dtype at pool registration
            // (Composer), never through here.
            Op::Input { .. } | Op::External { .. } => Dtype::Float32,
            Op::ConstF32 { .. } => Dtype::Float32,
            Op::ConstI32 { .. } => Dtype::Int32,
            Op::ConstBool { .. } => Dtype::Bool,
            Op::ArangeI32 { .. } => Dtype::Int32,
            Op::Full { dtype, .. } | Op::Cast { dtype } => *dtype,
            Op::Identity
            | Op::Sort { .. }
            | Op::MeanAxes { .. }
            | Op::SumAxes { .. }
            | Op::Take
            | Op::TakeAlongAxis { .. }
            | Op::Transpose { .. }
            | Op::Reshape { .. }
            | Op::ExpandDims { .. }
            | Op::Squeeze { .. }
            | Op::Split { .. }
            | Op::Concatenate { .. }
            | Op::Stack { .. }
            | Op::Rope { .. }
            | Op::Sdp { .. } => first(inputs),
            Op::Binary { .. } => promote(dtype_of(inputs[0]), dtype_of(inputs[1])),
            Op::Unary { kind } => match kind {
                // maximum(x, f32 scalar) promotes — the reference's relu.
                UnaryKind::Relu => promote(first(inputs), Dtype::Float32),
                _ => first(inputs),
            },
            Op::Matmul => promote(dtype_of(inputs[0]), dtype_of(inputs[1])),
            Op::Slice { .. } | Op::SliceUpdate { .. } => first(inputs),
            Op::QuantizedMatmul { .. } => {
                // Output follows x's dtype (scales share it in our models).
                first(inputs)
            }
            // Dequantize's output takes the scales' dtype, not the packed
            // U32 weight's.
            Op::Dequantize { .. } => dtype_of(inputs[1]),
            Op::RmsNorm { .. } => first(inputs),
            Op::Where => promote(dtype_of(inputs[1]), dtype_of(inputs[2])),
        }
    }

    /// The binding-table key's op dimension (ADR 0054 §2).
    pub fn kind(&self) -> &'static str {
        match self {
            Op::Input { .. } => "input",
            Op::External { .. } => "external",
            Op::ConstF32 { .. } => "const_f32",
            Op::ConstI32 { .. } => "const_i32",
            Op::ConstBool { .. } => "const_bool",
            Op::ArangeI32 { .. } => "arange_i32",
            Op::Full { .. } => "full",
            Op::Identity => "identity",
            Op::Binary { kind } => match kind {
                BinKind::Add => "add",
                BinKind::Sub => "sub",
                BinKind::Mul => "mul",
                BinKind::Div => "div",
                BinKind::Max => "max",
                BinKind::Min => "min",
                BinKind::LessEqual => "less_equal",
            },
            Op::Unary { kind } => match kind {
                UnaryKind::Abs => "abs",
                UnaryKind::Erf => "erf",
                UnaryKind::Exp => "exp",
                UnaryKind::Log => "log",
                UnaryKind::Sqrt => "sqrt",
                UnaryKind::Softmax => "softmax",
                UnaryKind::Relu => "relu",
                UnaryKind::Sigmoid => "sigmoid",
            },
            Op::Sort { .. } => "sort",
            Op::Cast { .. } => "cast",
            Op::MeanAxes { .. } => "mean",
            Op::SumAxes { .. } => "sum",
            Op::Matmul => "matmul",
            Op::Take => "take",
            Op::TakeAlongAxis { .. } => "take_along_axis",
            Op::Transpose { .. } => "transpose",
            Op::Reshape { .. } => "reshape",
            Op::ExpandDims { .. } => "expand_dims",
            Op::Squeeze { .. } => "squeeze",
            Op::Split { .. } => "split",
            Op::Concatenate { .. } => "concatenate",
            Op::Stack { .. } => "stack",
            Op::Where => "where",
            Op::Rope { .. } => "rope",
            Op::Sdp { .. } => "sdp",
            Op::QuantizedMatmul { .. } => "quantized_matmul",
            Op::Dequantize { .. } => "dequantize",
            Op::RmsNorm { .. } => "rms_norm",
            Op::Slice { .. } => "slice",
            Op::SliceUpdate { .. } => "slice_update",
        }
    }

    pub fn fanout(&self) -> u8 {
        match self {
            Op::Split { num, .. } => *num as u8,
            _ => 1,
        }
    }
}

/// A plan node: one op, its dataflow inputs, and its review metadata.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Node {
    /// Stable slot name (e.g. `enc.l07.mlp.wo`) — the µbench and profile key.
    pub name: String,
    /// Review/profiling group (e.g. `enc.l07`, `head.1`, `scorer`, `io`).
    pub group: String,
    pub op: Op,
    pub inputs: Vec<Slot>,
    /// LAYA_DEBUG_DUMP stage name — dumps land under the exact names the
    /// imperative forward used, so cross-engine diffs keep working.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub dump: Option<String>,
}

/// A declared forward pass. Construction order is execution order (builders
/// only ever reference earlier nodes, so the vector is topological).
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Plan {
    pub nodes: Vec<Node>,
    /// Decision logits output.
    pub logits: NodeId,
    /// Action-head output.
    pub act: NodeId,
    /// Execution-context manifest: name per pool entry (batch arrays first,
    /// then weights in registration order).
    pub ctx: Vec<String>,
}

impl Plan {
    pub fn to_json(&self) -> String {
        serde_json::to_string_pretty(self).unwrap_or_default()
    }
}

/// Builds a plan and the execution-context manifest together. The pool holds
/// borrowed arrays: batch inputs first (registered by the composer), then
/// weights on first use.
#[derive(Default)]
pub struct PlanBuilder {
    pub nodes: Vec<Node>,
    pub ctx: Vec<String>,
}

impl PlanBuilder {
    /// Registers the next pool slot under `name` and returns its input node.
    pub fn input(&mut self, name: &str, dump: Option<String>) -> NodeId {
        let index = self.ctx.len();
        self.ctx.push(name.to_string());
        self.push("io", Op::Input { index }, name, &[], dump)
    }

    /// Declaration-only node (ADR 0054 §4).
    pub fn external(&mut self, name: &str, program: &str, note: &str) -> NodeId {
        self.push(
            "external",
            Op::External {
                program: program.to_string(),
                note: note.to_string(),
            },
            name,
            &[],
            None,
        )
    }

    pub fn push(
        &mut self,
        group: &str,
        op: Op,
        name: &str,
        inputs: &[Slot],
        dump: Option<String>,
    ) -> NodeId {
        let id = self.nodes.len();
        self.nodes.push(Node {
            name: name.to_string(),
            group: group.to_string(),
            op,
            inputs: inputs.to_vec(),
            dump,
        });
        id
    }
}

/// The arrays a plan executes over, in [`Plan::ctx`] order.
pub struct ExecPool<'a> {
    pub arrays: Vec<&'a Array>,
}

/// Diagnostics a walk may run. Never enabled while mlx traces a compiled
/// closure (readback on symbolic arrays would poison the trace).
#[derive(Copy, Clone)]
pub struct ExecOptions {
    pub dump: bool,
    pub profile: bool,
}

impl ExecOptions {
    /// The golden path: diagnostics from the environment.
    pub fn runtime() -> ExecOptions {
        let set = |k: &str| std::env::var_os(k).is_some_and(|v| !v.is_empty());
        ExecOptions { dump: set("LAYA_DEBUG_DUMP"), profile: set("LAYA_PROFILE") }
    }

    /// Under compile tracing: materializing anything is forbidden.
    pub fn tracing() -> ExecOptions {
        ExecOptions { dump: false, profile: false }
    }
}

/// Executes the plan eagerly through the binding table. Returns the final
/// outputs (logits, act), unmaterialized like the imperative forward's.
pub fn execute(
    plan: &Plan,
    pool: &ExecPool,
    table: &crate::bindings::BindingTable,
    s: Stream,
    opts: ExecOptions,
) -> MlxResult<(Array, Array)> {
    let debug_dump = if opts.dump { crate::DebugDump::from_env() } else { crate::DebugDump::disabled() };

    let mut consumers = node_consumer_counts(plan);
    let mut values: Vec<Option<Vec<Array>>> = (0..plan.nodes.len()).map(|_| None).collect();
    let mut durations: Vec<(std::time::Duration, &'static str, String)> = Vec::new();

    for id in 0..plan.nodes.len() {
        let node = &plan.nodes[id];
        // Pool inputs resolve in the gather step below; external nodes are
        // declaration-only (ADR 0054 §4).
        if matches!(node.op, Op::Input { .. } | Op::External { .. }) {
            continue;
        }
        let outs = {
            let mut refs: Vec<&Array> = Vec::with_capacity(node.inputs.len());
            for &(src, slot) in &node.inputs {
                if let Op::Input { index } = plan.nodes[src].op {
                    refs.push(pool.arrays[index]);
                } else {
                    let stored = values[src].as_ref().ok_or(crate::mlx::MlxError(-981))?;
                    refs.push(stored.get(slot as usize).ok_or(crate::mlx::MlxError(-982))?);
                }
            }
            let start = if opts.profile { Some(std::time::Instant::now()) } else { None };
            let outs = crate::bindings::eval(node, &refs, table, s)?;
            if let Some(t0) = start {
                for o in &outs {
                    o.eval()?;
                }
                durations.push((t0.elapsed(), node.op.kind(), node.group.clone()));
            }
            if let (true, Some(stage)) = (debug_dump.active(), node.dump.as_deref()) {
                if let Some(first) = outs.first() {
                    debug_dump.stage(stage, first, s);
                }
            }
            outs
        };
        values[id] = Some(outs);
        // Release inputs whose last consumer just ran.
        for &(src, _) in &node.inputs {
            consumers[src] -= 1;
            if consumers[src] == 0 && src != plan.logits && src != plan.act {
                values[src] = None;
            }
        }
    }

    if opts.profile {
        // Aggregate per (group, op-kind), largest total first.
        let mut agg: std::collections::HashMap<String, (std::time::Duration, usize)> =
            std::collections::HashMap::new();
        for (d, kind, group) in &durations {
            let key = format!("{group}:{kind}");
            let e = agg.entry(key).or_insert((std::time::Duration::ZERO, 0));
            e.0 += *d;
            e.1 += 1;
        }
        let mut rows: Vec<_> = agg.into_iter().collect();
        rows.sort_by(|a, b| b.1 .0.cmp(&a.1 .0));
        for (key, (d, n)) in rows {
            eprintln!("profile {key}: {d:?} over {n} nodes");
        }
    }

    let logits = alias_output(&mut values, plan.logits, s)?;
    let act = alias_output(&mut values, plan.act, s)?;
    Ok((logits, act))
}

/// Aliases an output array for readback (a lazy identity view — no new GPU
/// op enters the tensor math; the C ABI layer materializes both outputs).
fn alias_output(
    values: &mut [Option<Vec<Array>>],
    id: NodeId,
    s: Stream,
) -> MlxResult<Array> {
    values[id]
        .as_ref()
        .and_then(|v| v.first())
        .ok_or(crate::mlx::MlxError(-983))?
        .identity(s)
}

fn node_consumer_counts(plan: &Plan) -> Vec<usize> {
    let mut counts = vec![0usize; plan.nodes.len()];
    for node in &plan.nodes {
        for &(src, _) in &node.inputs {
            counts[src] += 1;
        }
    }
    counts
}

/// One node's observed contract, recorded by a profiling walk — the slot a
/// µbench auto-derives from (ADR 0054 R0).
#[derive(Clone, Debug)]
pub struct NodeContract {
    pub name: String,
    pub group: String,
    pub op: Op,
    pub input_shapes: Vec<Vec<usize>>,
    pub input_dtypes: Vec<Dtype>,
}

/// Walks the plan once (evaluating every node) and records each node's
/// input contracts. Diagnostic-only; the golden path never runs this.
pub fn record_contracts(
    plan: &Plan,
    pool: &ExecPool,
    table: &crate::bindings::BindingTable,
    s: Stream,
) -> MlxResult<Vec<NodeContract>> {
    let mut values: Vec<Option<Vec<Array>>> = (0..plan.nodes.len()).map(|_| None).collect();
    let mut contracts = Vec::new();
    for id in 0..plan.nodes.len() {
        let node = &plan.nodes[id];
        if matches!(node.op, Op::Input { .. } | Op::External { .. }) {
            continue;
        }
        let mut refs: Vec<&Array> = Vec::with_capacity(node.inputs.len());
        for &(src, slot) in &node.inputs {
            if let Op::Input { index } = plan.nodes[src].op {
                refs.push(pool.arrays[index]);
            } else {
                let stored = values[src].as_ref().ok_or(crate::mlx::MlxError(-981))?;
                refs.push(stored.get(slot as usize).ok_or(crate::mlx::MlxError(-982))?);
            }
        }
        contracts.push(NodeContract {
            name: node.name.clone(),
            group: node.group.clone(),
            op: node.op.clone(),
            input_shapes: refs
                .iter()
                .map(|a| (0..a.ndim()).map(|d| a.dim(d as i32)).collect())
                .collect(),
            input_dtypes: refs.iter().map(|a| a.dtype()).collect(),
        });
        let outs = crate::bindings::eval(node, &refs, table, s)?;
        values[id] = Some(outs);
    }
    Ok(contracts)
}

/// fp16-pattern fill for µbench inputs (same scheme as the L0 spike test).
pub fn pattern_bytes(len: usize, modulus: u16) -> Vec<u8> {
    let mut v = vec![0u8; len];
    for (i, chunk) in v.chunks_exact_mut(2).enumerate() {
        let bits = (0x3800u16.wrapping_add((i % modulus as usize) as u16)).to_le_bytes();
        chunk[0] = bits[0];
        chunk[1] = bits[1];
    }
    v
}

/// Derives a µbench for one plan slot from its recorded contract: rebuilds
/// inputs of the recorded shapes, times `iters` eval'd runs.
pub fn bench_node(
    contract: &NodeContract,
    iters: usize,
    table: &crate::bindings::BindingTable,
    s: Stream,
) -> MlxResult<std::time::Duration> {
    use crate::mlx::MlxError;
    let arrays: Vec<Array> = contract
        .input_shapes
        .iter()
        .zip(&contract.input_dtypes)
        .map(|(shape, dtype)| {
            let count: usize = shape.iter().product();
            match dtype {
                Dtype::Float16 => Array::from_data_f16(&pattern_bytes(count * 2, 97), shape),
                Dtype::Int32 => {
                    let v: Vec<i32> = (0..count).map(|i| (i % 501) as i32).collect();
                    Array::from_data_i32(&v, shape)
                }
                Dtype::Bool => {
                    let v: Vec<u8> = (0..count).map(|i| (i % 7 != 0) as u8).collect();
                    Array::from_data_bool(&v, shape)
                }
                Dtype::Float32 => {
                    let v: Vec<f32> = (0..count).map(|i| (i % 251) as f32 / 16.0).collect();
                    Array::from_data_f32(&v, shape)
                }
                _ => return Err(MlxError(-980)),
            }
        })
        .collect::<MlxResult<_>>()?;
    let refs: Vec<&Array> = arrays.iter().collect();
    let node = Node {
        name: contract.name.clone(),
        group: contract.group.clone(),
        op: contract.op.clone(),
        inputs: Vec::new(),
        dump: None,
    };
    // Warmup, then a timed eval-per-run loop: per-op cost including sync.
    let warm = crate::bindings::eval(&node, &refs, table, s)?;
    for a in &warm {
        a.eval()?;
    }
    let start = std::time::Instant::now();
    for _ in 0..iters {
        let outs = crate::bindings::eval(&node, &refs, table, s)?;
        for a in &outs {
            a.eval()?;
        }
    }
    Ok(start.elapsed() / iters as u32)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The plan is data: it serializes to reviewable, diffable JSON.
    #[test]
    fn plan_round_trips_through_json() {
        let mut b = PlanBuilder::default();
        let x = b.input("x", None);
        let wt = b.push("g", Op::Transpose { axes: vec![1, 0] }, "w.t", &[(x, 0)], None);
        let mm = b.push("g", Op::Matmul, "xw", &[(x, 0), (wt, 0)], None);
        let _ = b.push("g", Op::Unary { kind: UnaryKind::Relu }, "out", &[(mm, 0)], None);
        let plan = Plan { nodes: b.nodes, logits: 3, act: 3, ctx: b.ctx };
        let json = plan.to_json();
        let back: Plan = serde_json::from_str(&json).unwrap();
        assert_eq!(back.nodes.len(), plan.nodes.len());
        assert_eq!(back.nodes[1].op.kind(), "transpose");
        assert!(json.contains("\"op\": \"matmul\""));
        assert_eq!(back.ctx, vec!["x".to_string()]);
    }
}

/// Test-only GPU smoke: a two-node plan executes through the binding table.
#[cfg(test)]
mod gpu_tests {
    use super::*;
    use crate::bindings::BindingTable;

    #[test]
    fn tiny_plan_executes() {
        let metallib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("build/mlx-install/lib/mlx.metallib");
        if metallib.is_file() {
            crate::set_metallib_path_pub(&metallib);
        }
        let Ok(s) = crate::mlx::gpu() else { return }; // no Metal in CI
        let mut b = PlanBuilder::default();
        let x = b.input("x", None);
        let relu = b.push("g", Op::Unary { kind: UnaryKind::Relu }, "out", &[(x, 0)], None);
        let plan = Plan { nodes: b.nodes, logits: relu, act: relu, ctx: b.ctx };
        // f16 [-2.0, 1.0] little-endian.
        let a = Array::from_data_f16(&[0x00, 0xC0, 0x00, 0x3C], &[2]).unwrap();
        let pool = ExecPool { arrays: vec![&a] };
        let (lo, act) =
            execute(&plan, &pool, &BindingTable::baseline(), s, ExecOptions::tracing()).unwrap();
        let v = lo.to_f32_vec(s).unwrap();
        assert_eq!(v, vec![0.0, 1.0]);
        assert_eq!(act.to_f32_vec(s).unwrap(), vec![0.0, 1.0]);
    }
}
