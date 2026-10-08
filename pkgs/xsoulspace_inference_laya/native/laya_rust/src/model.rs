//! Faithful Rust/mlx-c port of laya_mlx/model.py (ModernBERT-large encoder +
//! Laya decision head). Since ADR 0054 the forward pass is a DECLARED PLAN:
//! [`LayaModel::build_plan`] composes typed op nodes with the identical op
//! sequence, operand order, and dtype chains as the historical imperative
//! port, and `plan::execute` walks the plan through the binding table. The
//! golden fixture (63/63 argmax, prob error ≤ 0.005) guards that the plan
//! walk is numerics-identical to what the fixture recorded.

use crate::bindings::BindingTable;
use crate::mlx::{load_safetensors, Array, Dtype, MlxError, MlxResult, Stream};
use crate::plan::{self, BinKind, ExecPool, ExecOptions, Op, Plan, Slot, UnaryKind};

/// The laya activation dtype (fp16 checkpoint; the fixture is fp16).
const ACT_DTYPE: Dtype = Dtype::Float16;

fn at(id: plan::NodeId) -> Slot {
    (id, 0)
}

/// The plan composer: builds nodes and the execution-context pool together.
/// The pool holds borrowed arrays: the five batch inputs (registered first,
/// in wire order), then weights on first use.
struct Composer<'a> {
    b: plan::PlanBuilder,
    pool: Vec<&'a Array>,
    /// Per-node output dtype, tracked with mlx's binary-promotion rules for
    /// our op set. Load-bearing for numerics: the reference runtime's relu
    /// (`max(x, f32 scalar)`) promotes f16 streams to f32, and layer_norm /
    /// gelu cast back to the INPUT's dtype — the promotion state decides
    /// whether the decision-head tail computes in f16 or f32 (the fixture
    /// was recorded with the promoted f32 tail).
    dtypes: Vec<Dtype>,
}

impl<'a> Composer<'a> {
    fn new(inputs: [&'a Array; 5]) -> Composer<'a> {
        let mut c = Composer { b: plan::PlanBuilder::default(), pool: Vec::new(), dtypes: Vec::new() };
        // Dump tags keep the historical LAYA_DEBUG_DUMP stage names.
        for (arr, (name, dump)) in inputs.into_iter().zip([
            ("in_ids", Some("in_ids")),
            ("attn_mask", Some("in_mask")),
            ("marker_pos", Some("in_marker_pos")),
            ("marker_mask", Some("in_marker_mask")),
            ("qtype", Some("in_qtype")),
        ]) {
            c.pool.push(arr);
            c.dtypes.push(arr.dtype());
            c.b.input(name, dump.map(str::to_string));
        }
        c
    }

    fn weight(&mut self, name: &str, w: &'a Array) -> plan::NodeId {
        self.pool.push(w);
        self.dtypes.push(w.dtype());
        self.b.input(name, None)
    }

    fn dtype_of(&self, slot: Slot) -> Dtype {
        self.dtypes[slot.0]
    }

    /// Declaration-only node (ADR 0054 §4): registers a placeholder dtype so
    /// the tracking vec stays aligned with node ids.
    fn external(&mut self, name: &str, program: &str, note: &str) -> plan::NodeId {
        let id = self.b.external(name, program, note);
        self.dtypes.push(Dtype::Float32);
        id
    }

    fn push(&mut self, group: &str, op: Op, name: &str, inputs: &[Slot]) -> plan::NodeId {
        let out_dtype = op.output_dtype(inputs, &|s| self.dtypes[s.0]);
        let id = self.b.push(group, op, name, inputs, None);
        self.dtypes.push(out_dtype);
        id
    }

    // ---- composite builders: op-for-op the imperative forward's helpers ----

    /// `Linear::apply`: w^T matmul, optional bias add.
    fn linear(
        &mut self,
        group: &str,
        name: &str,
        weight: &'a Linear,
        x: Slot,
    ) -> MlxResult<plan::NodeId> {
        if let Some(q) = &weight.quantized {
            // R3 calibration path: the packed triple rides the
            // quantized_matmul binding (same key R3's fused dequant-GEMV
            // will land on). Output dtype follows x (fp16), so the
            // promotion chain and the f32 tail are unchanged in structure.
            let wq = self.weight(&format!("{name}.q8"), &q.w);
            let ws = self.weight(&format!("{name}.q8_scales"), &q.scales);
            let wb = self.weight(&format!("{name}.q8_biases"), &q.biases);
            let mm = self.push(
                group,
                Op::QuantizedMatmul { group_size: 64, bits: 8, transpose: true },
                &format!("{name}.q8_matmul"),
                &[x, at(wq), at(ws), at(wb)],
            );
            return match weight.bias.as_ref() {
                Some(b) => {
                    let bn = self.weight(&format!("{name}.bias"), b);
                    Ok(self.push(group, Bin(BinKind::Add), &format!("{name}.bias_add"), &[at(mm), at(bn)]))
                }
                None => Ok(mm),
            };
        }
        let w = self.weight(&format!("{name}.weight"), &weight.weight);
        let w_t = self.push(group, Op::Transpose { axes: vec![1, 0] }, &format!("{name}.w_t"), &[at(w)]);
        let mm = self.push(group, Op::Matmul, &format!("{name}.matmul"), &[x, at(w_t)]);
        match weight.bias.as_ref() {
            Some(b) => {
                let bn = self.weight(&format!("{name}.bias"), b);
                Ok(self.push(group, Bin(BinKind::Add), &format!("{name}.bias_add"), &[at(mm), at(bn)]))
            }
            None => Ok(mm),
        }
    }

    /// fp32-accumulating LayerNorm (mlx's own fast LayerNorm does the same):
    /// in float16 the squared deviations overflow to inf at the deep
    /// layers' magnitudes and the output collapses to 0.
    #[allow(clippy::too_many_arguments)]
    fn layer_norm(
        &mut self,
        group: &str,
        name: &str,
        x: Slot,
        weight: &'a Array,
        bias: Option<&'a Array>,
        eps: f32,
    ) -> MlxResult<plan::NodeId> {
        // The reference casts back to the INPUT's (possibly promoted) dtype.
        let x_dtype = self.dtype_of(x);
        let xf = self.push(group, Cast(Dtype::Float32), &format!("{name}.x_f32"), &[x]);
        let mu = self.push(group, Op::MeanAxes { axes: vec![-1], keepdims: true }, &format!("{name}.mean"), &[at(xf)]);
        let centered = self.push(group, Bin(BinKind::Sub), &format!("{name}.center"), &[at(xf), at(mu)]);
        let sq = self.push(group, Bin(BinKind::Mul), &format!("{name}.sq"), &[at(centered), at(centered)]);
        let v = self.push(group, Op::MeanAxes { axes: vec![-1], keepdims: true }, &format!("{name}.var"), &[at(sq)]);
        let eps_n = self.push(group, Op::ConstF32 { value: eps }, &format!("{name}.eps"), &[]);
        let v_eps = self.push(group, Bin(BinKind::Add), &format!("{name}.var_eps"), &[at(v), at(eps_n)]);
        let denom = self.push(group, Op::Unary { kind: UnaryKind::Sqrt }, &format!("{name}.denom"), &[at(v_eps)]);
        let normed = self.push(group, Bin(BinKind::Div), &format!("{name}.norm"), &[at(centered), at(denom)]);
        let w = self.weight(&format!("{name}.weight"), weight);
        let wf = self.push(group, Cast(Dtype::Float32), &format!("{name}.w_f32"), &[at(w)]);
        let scaled = self.push(group, Bin(BinKind::Mul), &format!("{name}.scale"), &[at(normed), at(wf)]);
        let out = match bias {
            Some(b) => {
                let bn = self.weight(&format!("{name}.bias"), b);
                let bf = self.push(group, Cast(Dtype::Float32), &format!("{name}.b_f32"), &[at(bn)]);
                self.push(group, Bin(BinKind::Add), &format!("{name}.bias_add"), &[at(scaled), at(bf)])
            }
            None => scaled,
        };
        Ok(self.push(group, Cast(x_dtype), &format!("{name}.out"), &[at(out)]))
    }

    /// The reference MLXNN.gelu op-chain, op-for-op in the array's own
    /// dtype: `x * (1 + erf(x / sqrt(2))) / 2`.
    fn gelu(&mut self, group: &str, name: &str, x: Slot) -> plan::NodeId {
        let dtype = self.dtype_of(x);
        let konst = |c: &mut Self, v: f32, tag: &str| -> Slot {
            let raw = c.push(group, Op::ConstF32 { value: v }, &format!("{name}.c_{tag}"), &[]);
            at(c.push(group, Cast(dtype), &format!("{name}.{tag}"), &[at(raw)]))
        };
        let sqrt2 = konst(self, 1.4142135623730951, "sqrt2");
        let one = konst(self, 1.0, "one");
        let two = konst(self, 2.0, "two");
        let d = self.push(group, Bin(BinKind::Div), &format!("{name}.div2"), &[x, sqrt2]);
        let e = self.push(group, Op::Unary { kind: UnaryKind::Erf }, &format!("{name}.erf"), &[at(d)]);
        let a = self.push(group, Bin(BinKind::Add), &format!("{name}.plus1"), &[at(e), one]);
        let m = self.push(group, Bin(BinKind::Mul), &format!("{name}.mulx"), &[at(a), x]);
        self.push(group, Bin(BinKind::Div), name, &[at(m), two])
    }

    /// Row gather from a [rows, cols] table through the flat take:
    /// flatten to 1-D, indices = row_id*cols + col, take. (take_along_axis
    /// preserves the INDICES' shape, so it cannot express a row gather with
    /// narrow indices — paid for in the golden bisection.)
    #[allow(clippy::too_many_arguments)]
    fn gather_rows(
        &mut self,
        group: &str,
        name: &str,
        table: plan::NodeId,
        table_rows: usize,
        row_ids: Slot,
        ids_count: usize,
        cols: usize,
    ) -> plan::NodeId {
        let flat = self.push(group, Op::Reshape { shape: vec![table_rows * cols] }, &format!("{name}.flat"), &[at(table)]);
        let cols_n = self.push(group, Op::ConstI32 { value: cols as i32 }, &format!("{name}.c_cols"), &[]);
        let ids_col = self.push(group, Op::Reshape { shape: vec![ids_count, 1] }, &format!("{name}.ids_col"), &[row_ids]);
        let scaled = self.push(group, Bin(BinKind::Mul), &format!("{name}.ids_scaled"), &[at(ids_col), at(cols_n)]);
        let col_index = self.push(group, Op::ArangeI32 { start: 0, stop: cols as i32 }, &format!("{name}.cols_idx"), &[]);
        let flat_index = self.push(group, Bin(BinKind::Add), &format!("{name}.flat_idx"), &[at(scaled), at(col_index)]);
        self.push(group, Op::Take, &format!("{name}.take"), &[at(flat), at(flat_index)])
    }

    /// qkv [B,L,3*H*D] → per-head [B,H,L,D] triple (identity + squeeze +
    /// transpose per part, exactly as the imperative port).
    #[allow(clippy::too_many_arguments)]
    fn split_heads(
        &mut self,
        group: &str,
        name: &str,
        qkv: Slot,
        b: usize,
        l: usize,
        heads: usize,
        head_dim: usize,
    ) -> MlxResult<[Slot; 3]> {
        let r = self.push(group, Op::Reshape { shape: vec![b, l, 3, heads, head_dim] }, &format!("{name}.heads"), &[qkv]);
        let parts = self.push(group, Op::Split { num: 3, axis: 2 }, &format!("{name}.split"), &[at(r)]);
        let head = |c: &mut Self, part: u8, tag: &str| -> Slot {
            let id = c.push(group, Op::Identity, &format!("{name}.{tag}_view"), &[(parts, part)]);
            let sq = c.push(group, Op::Squeeze { axes: vec![2] }, &format!("{name}.{tag}_squeeze"), &[at(id)]);
            at(c.push(group, Op::Transpose { axes: vec![0, 2, 1, 3] }, &format!("{name}.{tag}"), &[at(sq)]))
        };
        Ok([head(self, 0, "q"), head(self, 1, "k"), head(self, 2, "v")])
    }
}

/// Shorthand constructors for readable builder code.
#[allow(non_snake_case)]
fn Bin(kind: BinKind) -> Op {
    Op::Binary { kind }
}
#[allow(non_snake_case)]
fn Cast(dtype: Dtype) -> Op {
    Op::Cast { dtype }
}

/// Boolean key masks mirroring laya_mlx.model.attention_masks:
/// full = key validity; local additionally bounds |i-j| <= window/2, and
/// padded query rows may see valid keys (they are never used as keys or
/// pooled, so valid-token results are unchanged).
fn attention_masks(
    c: &mut Composer,
    attention_mask: plan::NodeId,
    length: usize,
    window: usize,
) -> (plan::NodeId, plan::NodeId) {
    let g = "masks";
    let valid = c.push(g, Cast(Dtype::Bool), "masks.valid", &[at(attention_mask)]);
    let full = c.push(g, Op::ExpandDims { axes: vec![1, 2] }, "masks.full", &[at(valid)]);
    let positions = c.push(g, Op::ArangeI32 { start: 0, stop: length as i32 }, "masks.positions", &[]);
    let pos_i = c.push(g, Op::ExpandDims { axes: vec![1] }, "masks.pos_i", &[at(positions)]);
    let pos_j = c.push(g, Op::ExpandDims { axes: vec![0] }, "masks.pos_j", &[at(positions)]);
    let dist = c.push(g, Bin(BinKind::Sub), "masks.dist", &[at(pos_i), at(pos_j)]);
    let dist = c.push(g, Op::Unary { kind: UnaryKind::Abs }, "masks.abs", &[at(dist)]);
    let half = c.push(g, Op::ConstI32 { value: (window / 2) as i32 }, "masks.half", &[]);
    let local = c.push(g, Bin(BinKind::LessEqual), "masks.le", &[at(dist), at(half)]);
    let local = c.push(g, Op::ExpandDims { axes: vec![0, 1] }, "masks.local4", &[at(local)]);
    let row_valid = c.push(g, Op::ExpandDims { axes: vec![1, 3] }, "masks.row_valid", &[at(valid)]);
    let true_n = c.push(g, Op::ConstBool { value: true }, "masks.c_true", &[]);
    let or_invalid = c.push(g, Op::Where, "masks.or_invalid", &[at(row_valid), at(local), at(true_n)]);
    let false_n = c.push(g, Op::ConstBool { value: false }, "masks.c_false", &[]);
    let local = c.push(g, Op::Where, "masks.local", &[at(or_invalid), at(full), at(false_n)]);
    (full, local)
}

fn encoder_attention<'a>(
    c: &mut Composer<'a>,
    group: &str,
    attn: &'a EncoderAttention,
    normed: Slot,
    mask: plan::NodeId,
    b: usize,
    l: usize,
) -> MlxResult<plan::NodeId> {
    let qkv = c.linear(group, &format!("{group}.wqkv"), &attn.wqkv, normed)?;
    let [q, k, v] = c.split_heads(group, &format!("{group}.attn"), at(qkv), b, l, attn.num_heads, attn.head_dim)?;
    let qr = c.push(group, Op::Rope { dims: attn.head_dim as i32, base: attn.rope_base, offset: 0 }, &format!("{group}.rope_q"), &[q]);
    let kr = c.push(group, Op::Rope { dims: attn.head_dim as i32, base: attn.rope_base, offset: 0 }, &format!("{group}.rope_k"), &[k]);
    let scale = (attn.head_dim as f32).powf(-0.5);
    let att = c.push(group, Op::Sdp { scale, causal: false }, &format!("{group}.sdp"), &[at(qr), at(kr), v, at(mask)]);
    let merged_t = c.push(group, Op::Transpose { axes: vec![0, 2, 1, 3] }, &format!("{group}.merge_t"), &[at(att)]);
    let merged = c.push(group, Op::Reshape { shape: vec![b, l, attn.num_heads * attn.head_dim] }, &format!("{group}.merge"), &[at(merged_t)]);
    c.linear(group, &format!("{group}.wo"), &attn.wo, at(merged))
}

fn encoder_layer<'a>(
    c: &mut Composer<'a>,
    index: usize,
    layer: &'a EncoderLayer,
    h: plan::NodeId,
    mask: plan::NodeId,
    b: usize,
    l: usize,
) -> MlxResult<plan::NodeId> {
    let g = format!("enc.l{index:02}");
    let normed_in = match &layer.attn_norm {
        Some(n) => c.layer_norm(&g, &format!("{g}.attn_norm"), at(h), n, None, layer.eps)?,
        None => c.push(&g, Op::Identity, &format!("{g}.attn_norm_identity"), &[at(h)]),
    };
    let attn_out = encoder_attention(c, &g, &layer.attn, at(normed_in), mask, b, l)?;
    c.b.nodes[attn_out].dump = Some(format!("attn_out_{index:02}"));
    let h1 = c.push(&g, Bin(BinKind::Add), &format!("{g}.attn_residual"), &[at(h), at(attn_out)]);
    let normed_mlp = c.layer_norm(&g, &format!("{g}.mlp_norm"), at(h1), &layer.mlp_norm, None, layer.eps)?;
    let mlp_out = {
        let wi = c.linear(&g, &format!("{g}.wi"), &layer.mlp.wi, at(normed_mlp))?;
        c.b.nodes[wi].dump = Some(format!("mlp_wi_{index:02}"));
        let parts = c.push(&g, Op::Split { num: 2, axis: -1 }, &format!("{g}.wi_split"), &[at(wi)]);
        let activated = c.gelu(&g, &format!("{g}.gelu"), (parts, 0));
        c.b.nodes[activated].dump = Some(format!("mlp_gelu_{index:02}"));
        let gated = c.push(&g, Bin(BinKind::Mul), &format!("{g}.gate_mul"), &[at(activated), (parts, 1)]);
        c.linear(&g, &format!("{g}.wo"), &layer.mlp.wo, at(gated))?
    };
    c.b.nodes[mlp_out].dump = Some(format!("mlp_out_{index:02}"));
    let out = c.push(&g, Bin(BinKind::Add), &format!("{g}.mlp_residual"), &[at(h1), at(mlp_out)]);
    c.b.nodes[out].dump = Some(format!("h_after_layer_{index:02}"));
    Ok(out)
}

fn head_layer<'a>(
    c: &mut Composer<'a>,
    index: usize,
    layer: &'a HeadLayer,
    h: plan::NodeId,
    head_mask: plan::NodeId,
    b: usize,
    l: usize,
    hidden: usize,
) -> MlxResult<plan::NodeId> {
    let g = format!("head.{index}");
    let normed = c.layer_norm(&g, &format!("{g}.norm1"), at(h), &layer.norm1, Some(&layer.norm1_bias), layer.eps)?;
    let attn_out = {
        let sa = &layer.self_attn;
        let qkv = c.linear(&g, &format!("{g}.in_proj"), &sa.in_proj, at(normed))?;
        let [q, k, v] = c.split_heads(&g, &format!("{g}.attn"), at(qkv), b, l, sa.num_heads, sa.head_dim)?;
        let scale = (sa.head_dim as f32).powf(-0.5);
        let att = c.push(&g, Op::Sdp { scale, causal: false }, &format!("{g}.sdp"), &[q, k, v, at(head_mask)]);
        let merged_t = c.push(&g, Op::Transpose { axes: vec![0, 2, 1, 3] }, &format!("{g}.merge_t"), &[at(att)]);
        let merged = c.push(&g, Op::Reshape { shape: vec![b, l, hidden] }, &format!("{g}.merge"), &[at(merged_t)]);
        c.linear(&g, &format!("{g}.out_proj"), &sa.out_proj, at(merged))?
    };
    let h1 = c.push(&g, Bin(BinKind::Add), &format!("{g}.attn_residual"), &[at(h), at(attn_out)]);
    let normed2 = c.layer_norm(&g, &format!("{g}.norm2"), at(h1), &layer.norm2, Some(&layer.norm2_bias), layer.eps)?;
    let ff = c.linear(&g, &format!("{g}.linear1"), &layer.linear1, at(normed2))?;
    let rel = c.push(&g, Op::Unary { kind: UnaryKind::Relu }, &format!("{g}.relu"), &[at(ff)]);
    let ff2 = c.linear(&g, &format!("{g}.linear2"), &layer.linear2, at(rel))?;
    Ok(c.push(&g, Bin(BinKind::Add), &format!("{g}.ff_residual"), &[at(h1), at(ff2)]))
}

pub struct Linear {
    /// [out, in] — transposed per apply exactly like the Swift port (a lazy
    /// view in mlx; no numeric or measurable perf difference).
    pub weight: Array,
    pub bias: Option<Array>,
    /// Affine-quantized replacement (R3 calibration, q8): packed U32 weight
    /// + scales + biases. The plan dispatches `quantized_matmul` when set.
    pub quantized: Option<QuantTriple>,
}

/// One affine-quantized weight triple on the GPU (mlx `quantize` output).
pub struct QuantTriple {
    pub w: Array,
    pub scales: Array,
    pub biases: Array,
}

struct EncoderAttention {
    wqkv: Linear,
    wo: Linear,
    rope_base: f32,
    num_heads: usize,
    head_dim: usize,
}

struct EncoderMlp {
    wi: Linear,
    wo: Linear,
}

struct EncoderLayer {
    full_attention: bool,
    attn_norm: Option<Array>, // None at layer 0 (identity)
    attn: EncoderAttention,
    mlp_norm: Array,
    mlp: EncoderMlp,
    eps: f32,
}

struct ModernBert {
    tok_embeddings: Array,
    embeddings_norm: Array,
    layers: Vec<EncoderLayer>,
    final_norm: Array,
    local_attention: usize,
}

struct HeadAttention {
    in_proj: Linear,
    out_proj: Linear,
    num_heads: usize,
    head_dim: usize,
}

struct HeadLayer {
    self_attn: HeadAttention,
    norm1: Array,
    norm1_bias: Array,
    norm2: Array,
    norm2_bias: Array,
    linear1: Linear,
    linear2: Linear,
    eps: f32,
}

pub struct LayaModel {
    eps: f32,
    encoder: ModernBert,
    head_layers: Vec<HeadLayer>,
    type_emb: Array,
    scorer_norm: Array,
    scorer_norm_bias: Array,
    scorer_linear1: Linear,
    scorer_linear2: Linear,
    act_linear1: Linear,
    act_linear2: Linear,
    hidden_size: usize,
}

pub struct Batch {
    /// [B, L] Int32 token ids (padded by the caller).
    pub input_ids: Array,
    /// [B, L] Int32: 1 = real token, 0 = pad.
    pub attention_mask: Array,
    /// [B, Kmax] Int32 marker positions.
    pub marker_pos: Array,
    /// [B, Kmax] Bool: 1 = real marker.
    pub marker_mask: Array,
    /// [B] Int32 question type index.
    pub qtype: Array,
}

pub struct ForwardOutput {
    /// [B, Kmax] float32 decision logits.
    pub logits: Vec<Vec<f32>>,
    /// [B, 2] float32 action logits.
    pub act: Vec<Vec<f32>>,
}

fn take_linear(w: &crate::safetensors::SafetensorsFile, name: &str, bias: Option<&str>, s: Stream) -> MlxResult<Linear> {
    Ok(Linear {
        weight: w.take(name, s)?,
        bias: match bias {
            Some(b) => Some(w.take(b, s)?),
            None => None,
        },
        quantized: None,
    })
}

impl LayaModel {
    pub fn load(model_dir: &std::path::Path, s: Stream) -> MlxResult<LayaModel> {
        let enc_cfg: serde_json::Value = serde_json::from_str(
            &std::fs::read_to_string(model_dir.join("encoder/config.json"))
                .map_err(|_| MlxError(-10))?,
        )
        .map_err(|_| MlxError(-10))?;
        let hidden_size = enc_cfg["hidden_size"].as_u64().ok_or(MlxError(-10))? as usize;
        let num_layers = enc_cfg["num_hidden_layers"].as_u64().ok_or(MlxError(-10))? as usize;
        let num_heads = enc_cfg["num_attention_heads"].as_u64().ok_or(MlxError(-10))? as usize;
        let layer_types: Vec<String> = enc_cfg["layer_types"]
            .as_array()
            .ok_or(MlxError(-10))?
            .iter()
            .map(|v| v.as_str().unwrap_or_default().to_string())
            .collect();
        let local_attention = enc_cfg["local_attention"].as_u64().ok_or(MlxError(-10))? as usize;
        let norm_eps = enc_cfg["layer_norm_eps"]
            .as_f64()
            .map(|v| v as f32)
            .unwrap_or(1e-5);
        let head_dim = hidden_size / num_heads;
        let rope_parameters = enc_cfg.get("rope_parameters").cloned().unwrap_or(serde_json::Value::Null);

        let rope_base = |kind: &str| -> f32 {
            rope_parameters
                .get(kind)
                .and_then(|p| p.get("rope_theta"))
                .and_then(|t| t.as_f64())
                .map(|t| t as f32)
                .unwrap_or(if kind == "full_attention" { 160_000.0 } else { 10_000.0 })
        };

        let agent_cfg: serde_json::Value = serde_json::from_str(
            &std::fs::read_to_string(model_dir.join("rl_agent_config.json"))
                .map_err(|_| MlxError(-11))?,
        )
        .map_err(|_| MlxError(-11))?;
        let head_count = agent_cfg["head_layers"].as_u64().unwrap_or(2) as usize;

        let weights = load_safetensors(&model_dir.join("model.safetensors"), s)?;
        let t = |name: &str| weights.take(name, s);

        let mut layers = Vec::with_capacity(num_layers);
        for i in 0..num_layers {
            layers.push(EncoderLayer {
                full_attention: layer_types[i] == "full_attention",
                eps: norm_eps,
                attn_norm: if i == 0 {
                    None
                } else {
                    Some(t(&format!("encoder.layers.{i}.attn_norm.weight"))?)
                },
                attn: EncoderAttention {
                    wqkv: take_linear(&weights, &format!("encoder.layers.{i}.attn.Wqkv.weight"), None, s)?,
                    wo: take_linear(&weights, &format!("encoder.layers.{i}.attn.Wo.weight"), None, s)?,
                    rope_base: rope_base(&layer_types[i]),
                    num_heads,
                    head_dim,
                },
                mlp_norm: t(&format!("encoder.layers.{i}.mlp_norm.weight"))?,
                mlp: EncoderMlp {
                    wi: take_linear(&weights, &format!("encoder.layers.{i}.mlp.Wi.weight"), None, s)?,
                    wo: take_linear(&weights, &format!("encoder.layers.{i}.mlp.Wo.weight"), None, s)?,
                },
            });
        }

        let head_num_heads = (hidden_size / 64).max(1);
        let head_head_dim = hidden_size / head_num_heads;
        let mut head = Vec::with_capacity(head_count);
        for i in 0..head_count {
            head.push(HeadLayer {
                eps: norm_eps,
                self_attn: HeadAttention {
                    in_proj: take_linear(
                        &weights,
                        &format!("head.layers.{i}.self_attn.in_proj.weight"),
                        Some(&format!("head.layers.{i}.self_attn.in_proj.bias")),
                        s,
                    )?,
                    out_proj: take_linear(
                        &weights,
                        &format!("head.layers.{i}.self_attn.out_proj.weight"),
                        Some(&format!("head.layers.{i}.self_attn.out_proj.bias")),
                        s,
                    )?,
                    num_heads: head_num_heads,
                    head_dim: head_head_dim,
                },
                norm1: t(&format!("head.layers.{i}.norm1.weight"))?,
                norm1_bias: t(&format!("head.layers.{i}.norm1.bias"))?,
                norm2: t(&format!("head.layers.{i}.norm2.weight"))?,
                norm2_bias: t(&format!("head.layers.{i}.norm2.bias"))?,
                linear1: take_linear(
                    &weights,
                    &format!("head.layers.{i}.linear1.weight"),
                    Some(&format!("head.layers.{i}.linear1.bias")),
                    s,
                )?,
                linear2: take_linear(
                    &weights,
                    &format!("head.layers.{i}.linear2.weight"),
                    Some(&format!("head.layers.{i}.linear2.bias")),
                    s,
                )?,
            });
        }

        Ok(LayaModel {
            eps: norm_eps,
            encoder: ModernBert {
                tok_embeddings: t("encoder.embeddings.tok_embeddings.weight")?,
                embeddings_norm: t("encoder.embeddings.norm.weight")?,
                layers,
                final_norm: t("encoder.final_norm.weight")?,
                local_attention,
            },
            head_layers: head,
            type_emb: t("type_emb.weight")?,
            scorer_norm: t("scorer.layers.0.weight")?,
            scorer_norm_bias: t("scorer.layers.0.bias")?,
            scorer_linear1: take_linear(&weights, "scorer.layers.1.weight", Some("scorer.layers.1.bias"), s)?,
            scorer_linear2: take_linear(&weights, "scorer.layers.3.weight", Some("scorer.layers.3.bias"), s)?,
            act_linear1: take_linear(&weights, "act_head.layers.0.weight", Some("act_head.layers.0.bias"), s)?,
            act_linear2: take_linear(&weights, "act_head.layers.2.weight", Some("act_head.layers.2.bias"), s)?,
            hidden_size,
        })
    }

    /// Declares the forward pass as a plan over `inputs` = [input_ids,
    /// attention_mask, marker_pos, marker_mask, qtype]. Every node's contract
    /// is concrete: a plan is built per request shape.
    /// R3 calibration: affine-quantize every linear weight to 8-bit
    /// (group 64). Consumes the model and returns the q8 variant; the fp16
    /// weights stay resident but unused by the plan. The CALIBRATION gate
    /// (63/63 argmax, choice-prob and score/noul drift ≤ 0.02) decides
    /// whether this path ships — a failed gate is recorded, never shipped.
    pub fn into_q8(mut self, s: Stream) -> MlxResult<LayaModel> {
        fn q8(l: &mut Linear, s: Stream) -> MlxResult<()> {
            // mlx affine quantization requires the input dim divisible by
            // the group size; the head's in_proj [_, 1028] (hidden + 4
            // concatenated features) is not — that linear stays fp16 and
            // the calibration gate validates the mixed-precision forward.
            // Standard affine q8 group 64. The CALIBRATION gate (63/63,
            // drift ≤ 0.02) currently FAILS on two marginal score/noul
            // scalars (~0.026/0.039, stable across g64/g32 and
            // encoder-only/full scopes — a systematic shift, not weight
            // noise). LAYA_Q8 stays opt-in until that analysis lands;
            // ADR 0054 R3 records the red gate.
            if l.weight.dim(1) % 64 != 0 {
                return Ok(());
            }
            let outs = Array::quantize(&l.weight, 64, 8, s)?;
            l.quantized = Some(QuantTriple {
                w: outs[0].identity(s)?,
                scales: outs[1].identity(s)?,
                biases: outs[2].identity(s)?,
            });
            Ok(())
        }
        // The encoder holds nearly all the weight mass (the bandwidth win);
        // the decision-head and scalar-regression linears are tiny and sit
        // exactly where the calibration gate measures (score/noul drift
        // 0.026/0.039 at gate 0.02 when quantized) — they stay fp16.
        for layer in &mut self.encoder.layers {
            q8(&mut layer.attn.wqkv, s)?;
            q8(&mut layer.attn.wo, s)?;
            q8(&mut layer.mlp.wi, s)?;
            q8(&mut layer.mlp.wo, s)?;
        }
        Ok(self)
    }

    pub fn build_plan<'a>(&'a self, inputs: [&'a Array; 5]) -> (Plan, ExecPool<'a>) {
        let mut c = Composer::new(inputs);

        // The plan is the whole reviewable story of the decision path
        // (ADR 0054 §4): its oracle and bench programs are declared nodes.
        c.external(
            "ext.reference_runtime",
            "laya-mlx (pinned python runtime)",
            "source of the golden fixture oracle; regenerated from this engine 2026-10-08 (ADR 0051 L1/L2)",
        );
        c.external(
            "ext.laya_serve",
            "LayaDecisionServer (loopback /v1/systemone)",
            "serves these decisions to the harness over the System One wire",
        );
        c.external(
            "ext.napbench",
            "xsoulspace_inference_mlx tool/napbench_text_lane.dart",
            "text-lane TTFT/decode µbench (ADR 0051 L3)",
        );

        let b = inputs[0].dim(0);
        let l = inputs[0].dim(1);
        let kmax = inputs[3].dim(1);
        let hidden = self.hidden_size;

        // Input nodes: Composer::new registered them as plan nodes 0..5 in
        // wire order: ids=0, mask=1, marker_pos=2, marker_mask=3, qtype=4.
        let (ids_n, mask_n, pos_n, mmask_n, qtype_n) = (0, 1, 2, 3, 4);
        let _ = (pos_n, mmask_n, qtype_n);

        // ---- encoder (ModernBERT) ----
        let vocab_rows = self.encoder.tok_embeddings.dim(0);
        let emb_table = c.weight("encoder.tok_embeddings", &self.encoder.tok_embeddings);
        let emb_gather = {
            let taken = c.gather_rows("emb", "emb.gather", emb_table, vocab_rows, at(ids_n), b * l, hidden);
            c.push("emb", Op::Reshape { shape: vec![b, l, hidden] }, "emb.reshape", &[at(taken)])
        };
        let x = c
            .layer_norm("emb", "emb.norm", at(emb_gather), &self.encoder.embeddings_norm, None, self.eps)
            .expect("layer_norm nodes");
        c.b.nodes[x].dump = Some("x0_emb".into());
        let (mask_full, mask_local) = attention_masks(&mut c, mask_n, l, self.encoder.local_attention);
        c.b.nodes[mask_full].dump = Some("mask_full".into());
        c.b.nodes[mask_local].dump = Some("mask_local".into());

        let mut h = x;
        for (i, layer) in self.encoder.layers.iter().enumerate() {
            let mask = if layer.full_attention { mask_full } else { mask_local };
            h = encoder_layer(&mut c, i, layer, h, mask, b, l).expect("encoder layer nodes");
        }
        let enc = c
            .layer_norm("enc.final", "enc.final_norm", at(h), &self.encoder.final_norm, None, self.eps)
            .expect("final norm nodes");
        c.b.nodes[enc].dump = Some("enc_final".into());

        // ---- type embedding + decision head ----
        let type_cols = self.type_emb.dim(1);
        let type_table = c.weight("type_emb", &self.type_emb);
        let type_rows = c.gather_rows("head", "head.type_emb", type_table, self.type_emb.dim(0), at(qtype_n), b, type_cols);
        let type_add = c.push("head", Op::ExpandDims { axes: vec![1] }, "head.type_add", &[at(type_rows)]);
        let h = c.push("head", Bin(BinKind::Add), "head.type_add_apply", &[at(enc), at(type_add)]);
        let head_mask = {
            let e = c.push("head", Op::ExpandDims { axes: vec![1, 2] }, "head.mask_expand", &[at(mask_n)]);
            c.push("head", Cast(Dtype::Bool), "head.mask", &[at(e)])
        };
        let mut hh = h;
        for (i, layer) in self.head_layers.iter().enumerate() {
            hh = head_layer(&mut c, i, layer, hh, head_mask, b, l, hidden).expect("head layer nodes");
        }

        // ---- marker gather + scorer ----
        let flat = c.push("scorer", Op::Reshape { shape: vec![b * l, hidden] }, "scorer.flat", &[at(hh)]);
        let rows = {
            let ar = c.push("scorer", Op::ArangeI32 { start: 0, stop: b as i32 }, "scorer.rows", &[]);
            let len = c.push("scorer", Op::ConstI32 { value: l as i32 }, "scorer.row_len", &[]);
            c.push("scorer", Bin(BinKind::Mul), "scorer.rows_scaled", &[at(ar), at(len)])
        };
        let pos_clamped = {
            let z = c.push("scorer", Op::ConstI32 { value: 0 }, "scorer.zero", &[]);
            c.push("scorer", Bin(BinKind::Max), "scorer.pos_clamp", &[at(pos_n), at(z)])
        };
        let rows_e = c.push("scorer", Op::ExpandDims { axes: vec![1] }, "scorer.rows_e", &[at(rows)]);
        let flat_index = c.push("scorer", Bin(BinKind::Add), "scorer.flat_index", &[at(pos_clamped), at(rows_e)]);
        let markers = {
            let taken = c.gather_rows("scorer", "scorer.gather", flat, b * l, at(flat_index), b * kmax, hidden);
            let m = c.push("scorer", Op::Reshape { shape: vec![b, kmax, hidden] }, "scorer.markers", &[at(taken)]);
            m
        };
        let normed = c
            .layer_norm("scorer", "scorer.norm", at(markers), &self.scorer_norm, Some(&self.scorer_norm_bias), self.eps)
            .expect("scorer norm nodes");
        let sc1 = c
            .linear("scorer", "scorer.fc1", &self.scorer_linear1, at(normed))
            .expect("scorer fc1 nodes");
        let scg = c.gelu("scorer", "scorer.gelu", at(sc1));
        let sc2 = c
            .linear("scorer", "scorer.fc2", &self.scorer_linear2, at(scg))
            .expect("scorer fc2 nodes");
        let logits32 = {
            let resh = c.push("scorer", Op::Reshape { shape: vec![b, kmax] }, "scorer.reshape", &[at(sc2)]);
            let cast = c.push("scorer", Cast(Dtype::Float32), "scorer.cast_f32", &[at(resh)]);
            cast
        };
        let logits = {
            let neg_cap = c.push("scorer", Op::Full { value: -1e4, dtype: Dtype::Float32, shape: vec![b, kmax] }, "scorer.neg_cap", &[]);
            c.push("scorer", Op::Where, "logits", &[at(mmask_n), at(logits32), at(neg_cap)])
        };
        c.b.nodes[logits].dump = Some("logits".into());

        // ---- action head: pooled sequence + detached answer-distribution
        // summary (the checkpoint's J1-M "escalate" feature set) ----
        let p = c.push("act", Op::Unary { kind: UnaryKind::Softmax }, "act.probs", &[at(logits)]);
        let counts = {
            let m = c.push("act", Cast(Dtype::Float32), "act.mask_f32", &[at(mmask_n)]);
            let sum = c.push("act", Op::SumAxes { axes: vec![-1], keepdims: false }, "act.counts_sum", &[at(m)]);
            let two = c.push("act", Op::ConstF32 { value: 2.0 }, "act.c_two", &[]);
            c.push("act", Bin(BinKind::Max), "act.counts", &[at(sum), at(two)])
        };
        let log_p = {
            let eps = c.push("act", Op::ConstF32 { value: 1e-9 }, "act.c_eps", &[]);
            let clamped = c.push("act", Bin(BinKind::Max), "act.clamp_p", &[at(p), at(eps)]);
            c.push("act", Op::Unary { kind: UnaryKind::Log }, "act.log_p", &[at(clamped)])
        };
        // entropy = -(Σ p·log p) / log(counts)
        let entropy = {
            let pl = c.push("act", Bin(BinKind::Mul), "act.p_logp", &[at(p), at(log_p)]);
            let sum = c.push("act", Op::SumAxes { axes: vec![-1], keepdims: false }, "act.ent_sum", &[at(pl)]);
            let neg1 = c.push("act", Op::ConstF32 { value: -1.0 }, "act.c_neg1", &[]);
            let neg = c.push("act", Bin(BinKind::Mul), "act.ent_neg", &[at(sum), at(neg1)]);
            let log_counts = c.push("act", Op::Unary { kind: UnaryKind::Log }, "act.log_counts", &[at(counts)]);
            c.push("act", Bin(BinKind::Div), "act.entropy", &[at(neg), at(log_counts)])
        };
        let (top1, top2) = {
            let sorted = c.push("act", Op::Sort { axis: -1 }, "act.sort_p", &[at(p)]);
            let idx1 = c.push("act", Op::Full { value: (kmax - 1) as f64, dtype: Dtype::Int32, shape: vec![b, 1] }, "act.top1_idx", &[]);
            let take1 = c.push("act", Op::TakeAlongAxis { axis: 1 }, "act.top1_take", &[at(sorted), at(idx1)]);
            let top1 = c.push("act", Op::Squeeze { axes: vec![1] }, "act.top1", &[at(take1)]);
            let idx2 = c.push("act", Op::Full { value: (kmax - 2) as f64, dtype: Dtype::Int32, shape: vec![b, 1] }, "act.top2_idx", &[]);
            let take2 = c.push("act", Op::TakeAlongAxis { axis: 1 }, "act.top2_take", &[at(sorted), at(idx2)]);
            let top2 = c.push("act", Op::Squeeze { axes: vec![1] }, "act.top2", &[at(take2)]);
            (top1, top2)
        };
        let gap = c.push("act", Bin(BinKind::Sub), "act.gap", &[at(top1), at(top2)]);
        let counts_scaled = {
            let c255 = c.push("act", Op::ConstF32 { value: 255.0 }, "act.c_255", &[]);
            c.push("act", Bin(BinKind::Div), "act.counts_scaled", &[at(counts), at(c255)])
        };
        let features = c.push(
            "act",
            Op::Stack { axis: -1 },
            "act.features",
            &[at(top1), at(gap), at(entropy), at(counts_scaled)],
        );
        let action = {
            let first = {
                let idx = c.push("act", Op::Full { value: 0.0, dtype: Dtype::Int32, shape: vec![b, 1, 1] }, "act.first_idx", &[]);
                let t = c.push("act", Op::TakeAlongAxis { axis: 1 }, "act.first_take", &[at(hh), at(idx)]);
                let sq = c.push("act", Op::Squeeze { axes: vec![1] }, "act.first_sq", &[at(t)]);
                c.push("act", Cast(Dtype::Float32), "act.first_f32", &[at(sq)])
            };
            let pooled = c.push("act", Op::Concatenate { axis: -1 }, "act.pooled", &[at(first), at(features)]);
            let pooled16 = c.push("act", Cast(ACT_DTYPE), "act.pooled_f16", &[at(pooled)]);
            let a1 = c
                .linear("act", "act.fc1", &self.act_linear1, at(pooled16))
                .expect("act fc1 nodes");
            let ag = c.gelu("act", "act.gelu", at(a1));
            let a2 = c
                .linear("act", "act.fc2", &self.act_linear2, at(ag))
                .expect("act fc2 nodes");
            c.push("act", Cast(Dtype::Float32), "action", &[at(a2)])
        };
        c.b.nodes[action].dump = Some("act".into());

        let plan = Plan {
            nodes: c.b.nodes,
            logits,
            act: action,
            ctx: c.b.ctx,
        };
        (plan, ExecPool { arrays: c.pool })
    }

    pub fn forward(&self, batch: &Batch, s: Stream) -> MlxResult<ForwardOutput> {
        crate::DebugDump::begin_forward();
        let (plan, pool) = self.build_plan([
            &batch.input_ids,
            &batch.attention_mask,
            &batch.marker_pos,
            &batch.marker_mask,
            &batch.qtype,
        ]);
        let b = batch.qtype.dim(0);
        let kmax = batch.marker_mask.dim(1);
        maybe_dump_plan(&plan, b, batch.input_ids.dim(1), kmax);
        let (logits, act) = plan::execute(&plan, &pool, &BindingTable::baseline(), s, ExecOptions::runtime())?;
        // Materialize as float32 host-side (double conversion happens in the
        // JSON layer; float64 astype is unsupported on the GPU).
        Ok(ForwardOutput {
            logits: read_rows(&logits, b, kmax, s)?,
            act: read_rows(&act, b, 2, s)?,
        })
    }
}

/// The compiled forward (ADR 0054 R1): the whole plan traced by mlx.compile
/// per input-shape signature, fused, replayed. Owns a model Arc so the
/// closure's weights outlive any registry entry.
pub struct CompiledForward {
    _model: std::sync::Arc<LayaModel>,
    closure: crate::mlx::CompiledClosure,
}

impl CompiledForward {
    pub fn new(model: std::sync::Arc<LayaModel>) -> MlxResult<CompiledForward> {
        let m = std::sync::Arc::clone(&model);
        let closure = crate::mlx::CompiledClosure::compile(move |ins: &[&Array]| {
            // Streams are per-thread; obtain this call's (inputs carry it).
            let s = crate::mlx::gpu()?;
            let (plan, pool) = m.build_plan([ins[0], ins[1], ins[2], ins[3], ins[4]]);
            let (logits, act) =
                plan::execute(&plan, &pool, &BindingTable::baseline(), s, ExecOptions::tracing())?;
            Ok(vec![logits, act])
        })?;
        Ok(CompiledForward { _model: model, closure })
    }

    pub fn forward(&self, batch: &Batch, s: Stream) -> MlxResult<ForwardOutput> {
        let outs = self.closure.apply(&[
            &batch.input_ids,
            &batch.attention_mask,
            &batch.marker_pos,
            &batch.marker_mask,
            &batch.qtype,
        ])?;
        let mut it = outs.into_iter();
        let logits = it.next().ok_or(MlxError(-975))?;
        let act = it.next().ok_or(MlxError(-975))?;
        let b = batch.qtype.dim(0);
        let kmax = batch.marker_mask.dim(1);
        Ok(ForwardOutput {
            logits: read_rows(&logits, b, kmax, s)?,
            act: read_rows(&act, b, 2, s)?,
        })
    }
}

/// LAYA_PLAN_DUMP: write the reviewable plan JSON, one file per shape
/// signature (later requests of the same shape overwrite — one artifact per
/// shape class).
fn maybe_dump_plan(plan: &Plan, b: usize, l: usize, kmax: usize) {
    let Some(dir) = std::env::var_os("LAYA_PLAN_DUMP").filter(|v| !v.is_empty()) else {
        return;
    };
    let _ = std::fs::create_dir_all(&dir);
    let path = std::path::PathBuf::from(dir).join(format!("plan_B{b}_L{l}_K{kmax}.json"));
    let _ = std::fs::write(path, plan.to_json());
}

/// The reference MLXNN.gelu op-chain on raw arrays — kept for the L0 spike
/// probe (`op_profiles`) which benches the chain by hand.
#[cfg(test)]
pub fn gelu_pub(x: &Array, s: Stream) -> MlxResult<Array> {
    let dtype = x.dtype();
    let sqrt2 = Array::scalar_f32(1.4142135623730951_f32).astype(dtype, s)?;
    let one = Array::scalar_f32(1.0).astype(dtype, s)?;
    let two = Array::scalar_f32(2.0).astype(dtype, s)?;
    Ok(x.div(&sqrt2, s)?.erf(s)?.add(&one, s)?.mul(x, s)?.div(&two, s)?)
}

fn read_rows(arr: &Array, rows: usize, cols: usize, s: Stream) -> MlxResult<Vec<Vec<f32>>> {
    let flat = arr.to_f32_vec(s)?;
    Ok((0..rows)
        .map(|r| ((r * cols)..((r + 1) * cols)).map(|i| flat[i]).collect())
        .collect())
}
