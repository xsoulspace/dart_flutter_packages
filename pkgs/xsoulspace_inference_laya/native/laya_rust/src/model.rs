//! Faithful Rust/mlx-c port of laya_mlx/model.py (ModernBERT-large encoder +
//! Laya decision head), mirroring the validated Swift port in
//! `native/laya_native/Sources/LayaNative/LayaModel.swift` op for op: dtype
//! chain, fp32 LayerNorm accumulation, layer-0 identity attention norm, the
//! gated MLP (gelu on the value chunk), mask semantics (boolean keep-masks
//! straight into SDPA), the pre-norm decision head with ReLU feed-forward,
//! and the float32 cast at the scorer output.

use crate::mlx::{load_safetensors, Array, Dtype, MlxError, MlxResult, Stream};

static FORWARD_IDX: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
thread_local! {
    static CURRENT_FW: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
}

/// ADR 0051 debugging: when LAYA_DEBUG_DUMP is set, raw stage dumps
/// (f32 host copies) land here for diffing against the reference runtime.
fn dump_stage(name: &str, arr: &Array, s: Stream) {
    // Diagnostic activations may contain actor-private evidence. Never
    // materialize or persist them without an explicit diagnostic destination.
    let Some(dir) = std::env::var_os("LAYA_DEBUG_DUMP").filter(|value| !value.is_empty()) else {
        return;
    };
    let dir = std::path::PathBuf::from(dir);
    let _ = std::fs::create_dir_all(&dir);
    let name = format!("fw{:02}_{name}", CURRENT_FW.with(|c| c.get()));
    let dumped = arr.astype(Dtype::Float32, s).and_then(|a| a.to_f32_vec(s));
    let vals = match dumped {
        Ok(v) => v,
        Err(e) => {
            let _ = std::fs::write(dir.join(format!("DUMP_ERROR_{name}.txt")), format!("{e:?}"));
            return;
        }
    };
    let shape: Vec<usize> = (0..arr.ndim()).map(|d| arr.dim(d as i32)).collect();
    let _ = std::fs::write(
        dir.join(format!("{name}.json")),
        serde_json::json!({ "shape": shape, "file": format!("{name}.bin") }).to_string(),
    );
    let bytes: Vec<u8> = vals.iter().flat_map(|v| v.to_le_bytes()).collect();
    let _ = std::fs::write(dir.join(format!("{name}.bin")), bytes);
}

pub struct Linear {
    /// [out, in] — transposed per apply exactly like the Swift port (a lazy
    /// view in mlx; no numeric or measurable perf difference).
    pub weight: Array,
    pub bias: Option<Array>,
}

impl Linear {
    fn apply(&self, x: &Array, s: Stream) -> MlxResult<Array> {
        let w_t = self.weight.transpose_axes(&[1, 0], s)?;
        let out = x.matmul(&w_t, s)?;
        match &self.bias {
            Some(b) => out.add(b, s),
            None => Ok(out),
        }
    }
}

/// Mean/variance accumulate in float32 (mlx's own fast LayerNorm does the
/// same): in float16 the squared deviations overflow to inf at the deep
/// layers' magnitudes and the output collapses to 0.
fn layer_norm(
    x: &Array,
    weight: &Array,
    bias: Option<&Array>,
    eps: f32,
    s: Stream,
) -> MlxResult<Array> {
    let xf = x.astype(Dtype::Float32, s)?;
    let mu = xf.mean_axes(&[-1], true, s)?;
    let centered = xf.sub(&mu, s)?;
    let sq = centered.mul(&centered, s)?;
    let v = sq.mean_axes(&[-1], true, s)?;
    let denom = v.add(&Array::scalar_f32(eps), s)?.sqrt(s)?;
    let normed = centered.div(&denom, s)?;
    let scaled = normed.mul(&weight.astype(Dtype::Float32, s)?, s)?;
    let out = match bias {
        Some(b) => scaled.add(&b.astype(Dtype::Float32, s)?, s)?,
        None => scaled,
    };
    out.astype(x.dtype(), s)
}

/// The reference MLXNN.gelu op-chain, op-for-op in the array's own dtype:
/// `x * (1 + erf(x / sqrt(2))) / 2` — the compiledGelu the Swift port used
/// (mlx.compile preserves per-op fp16 rounding, which the golden margins
/// are sensitive to on long batches).
pub fn gelu_pub(x: &Array, s: Stream) -> MlxResult<Array> {
    gelu(x, s)
}

fn gelu(x: &Array, s: Stream) -> MlxResult<Array> {
    let dtype = x.dtype();
    let sqrt2 = Array::scalar_f32(1.4142135623730951_f32).astype(dtype, s)?;
    let one = Array::scalar_f32(1.0).astype(dtype, s)?;
    let two = Array::scalar_f32(2.0).astype(dtype, s)?;
    x.div(&sqrt2, s)?
        .erf(s)?
        .add(&one, s)?
        .mul(x, s)?
        .div(&two, s)
}

/// MLXNN.relu == maximum(x, 0).
fn relu(x: &Array, s: Stream) -> MlxResult<Array> {
    x.max_elemwise(&Array::scalar_f32(0.0), s)
}

struct EncoderAttention {
    wqkv: Linear,
    wo: Linear,
    rope_base: f32,
    num_heads: usize,
    head_dim: usize,
}

fn split_heads_qkv(
    qkv: &Array,
    b: usize,
    length: usize,
    num_heads: usize,
    head_dim: usize,
    s: Stream,
) -> MlxResult<(Array, Array, Array)> {
    let qkv = qkv.reshape(&[b, length, 3, num_heads, head_dim], s)?;
    // take_along_axis needs matching ndim, so the qkv split uses mlx_split
    // along the parts axis; each part [B,L,1,H,D] squeezes to [B,L,H,D].
    let parts = qkv.split_n(3, 2, s)?;
    let head = |a: Array| -> MlxResult<Array> {
        a.squeeze_axes(&[2], s)?.transpose_axes(&[0, 2, 1, 3], s)
    };
    Ok((head(parts[0].identity(s)?)?, head(parts[1].identity(s)?)?, head(parts[2].identity(s)?)?))
}

impl EncoderAttention {
    fn apply(&self, x: &Array, mask: &Array, s: Stream) -> MlxResult<Array> {
        let b = x.dim(0);
        let length = x.dim(1);
        let (q, k, v) = split_heads_qkv(&self.wqkv.apply(x, s)?, b, length, self.num_heads, self.head_dim, s)?;
        let qr = q.rope(self.head_dim as i32, self.rope_base, 0, s)?;
        let kr = k.rope(self.head_dim as i32, self.rope_base, 0, s)?;
        let out = Array::sdp_attention(&qr, &kr, &v, (self.head_dim as f32).powf(-0.5), mask, s)?;
        let merged = out
            .transpose_axes(&[0, 2, 1, 3], s)?
            .reshape(&[b, length, self.num_heads * self.head_dim], s)?;
        self.wo.apply(&merged, s)
    }
}

struct EncoderMlp {
    wi: Linear,
    wo: Linear,
}

impl EncoderMlp {
    fn apply(&self, index: usize, x: &Array, s: Stream) -> MlxResult<Array> {
        let wi = self.wi.apply(x, s)?;
        let (value, gate) = wi.split2(-1, s)?;
        dump_stage(&format!("mlp_wi_{index:02}"), &wi, s);
        let activated = gelu(&value, s)?;
        dump_stage(&format!("mlp_gelu_{index:02}"), &activated, s);
        self.wo.apply(&activated.mul(&gate, s)?, s)
    }
}

struct EncoderLayer {
    full_attention: bool,
    attn_norm: Option<Array>, // None at layer 0 (identity)
    attn: EncoderAttention,
    mlp_norm: Array,
    mlp: EncoderMlp,
    eps: f32,
}

impl EncoderLayer {
    fn apply(&self, index: usize, x: &Array, masks: &AttentionMasks, s: Stream) -> MlxResult<Array> {
        let mask = if self.full_attention { &masks.full } else { &masks.local };
        let normed_input = match &self.attn_norm {
            Some(n) => layer_norm(x, n, None, self.eps, s)?,
            None => x.identity(s)?,
        };
        let attn_out = self.attn.apply(&normed_input, mask, s)?;
        dump_stage(&format!("attn_out_{index:02}"), &attn_out, s);
        let h = x.add(&attn_out, s)?;
        let normed_mlp = layer_norm(&h, &self.mlp_norm, None, self.eps, s)?;
        let mlp_out = self.mlp.apply(index, &normed_mlp, s)?;
        dump_stage(&format!("mlp_out_{index:02}"), &mlp_out, s);
        h.add(&mlp_out, s)
    }
}

struct AttentionMasks {
    full: Array,
    local: Array,
}

impl AttentionMasks {
    /// Boolean key masks mirroring laya_mlx.model.attention_masks:
    /// full = key validity; local additionally bounds |i-j| <= window/2,
    /// and padded query rows may see valid keys (they are never used as
    /// keys or pooled, so valid-token results are unchanged).
    fn build(attention_mask: &Array, window: usize, s: Stream) -> MlxResult<AttentionMasks> {
        let valid = attention_mask.astype(Dtype::Bool, s)?; // [B, L]
        let full = valid.expand_dims(&[1, 2], s)?; // [B,1,1,L]
        let length = valid.dim(1) as i32;
        let positions = Array::arange_i32(0, length, s)?; // [L]
        let distance = positions
            .expand_dims(&[1], s)?
            .sub(&positions.expand_dims(&[0], s)?, s)?
            .abs(s)?; // [L,L]
        let local = distance.less_equal(&Array::scalar_i32((window / 2) as i32), s)?;
        let local = local.expand_dims(&[0, 1], s)?; // [1,1,L,L]
        let row_valid = valid.expand_dims(&[1, 3], s)?; // [B,1,L,1]
        // (local | ~rowValid) & full:
        let or_invalid = Array::where_(&row_valid, &local, &Array::scalar_bool(true), s)?;
        let local = Array::where_(&or_invalid, &full, &Array::scalar_bool(false), s)?;
        Ok(AttentionMasks { full, local })
    }
}

struct ModernBert {
    tok_embeddings: Array,
    embeddings_norm: Array,
    layers: Vec<EncoderLayer>,
    final_norm: Array,
    local_attention: usize,
    eps: f32,
}

impl ModernBert {
    fn apply(&self, input_ids: &Array, attention_mask: &Array, s: Stream) -> MlxResult<Array> {
        // C mlx_take is the flat (axis-None) take — row gathers go through
        // the flat trick: flatten the table, flat index = id*cols + col.
        let b0 = input_ids.dim(0);
        let l0 = input_ids.dim(1);
        let hidden0 = self.tok_embeddings.dim(1);
        let x = gather_rows(&self.tok_embeddings, input_ids, hidden0, s)?;
        let x = x.reshape(&[b0, l0, hidden0], s)?;
        let x = layer_norm(&x, &self.embeddings_norm, None, self.eps, s)?;
        dump_stage("x0_emb", &x, s);
        let masks = AttentionMasks::build(attention_mask, self.local_attention, s)?;
        dump_stage("mask_full", &masks.full, s);
        dump_stage("mask_local", &masks.local, s);
        let mut h = x;
        let profile = std::env::var("LAYA_PROFILE").is_ok();
        for (i, layer) in self.layers.iter().enumerate() {
            let t = if profile { Some(std::time::Instant::now()) } else { None };
            h = layer.apply(i, &h, &masks, s)?;
            if profile {
                let _ = h.eval();
                eprintln!("layer {i:02}: {:?}", t.unwrap().elapsed());
            }
            dump_stage(&format!("h_after_layer_{i:02}"), &h, s);
        }
        let out = layer_norm(&h, &self.final_norm, None, self.eps, s);
        if let Ok(o) = &out {
            dump_stage("enc_final", o, s);
        }
        out
    }
}

struct HeadAttention {
    in_proj: Linear,
    out_proj: Linear,
    num_heads: usize,
    head_dim: usize,
}

impl HeadAttention {
    fn apply(&self, x: &Array, mask: &Array, s: Stream) -> MlxResult<Array> {
        let b = x.dim(0);
        let length = x.dim(1);
        let (q, k, v) = split_heads_qkv(&self.in_proj.apply(x, s)?, b, length, self.num_heads, self.head_dim, s)?;
        let out = Array::sdp_attention(&q, &k, &v, (self.head_dim as f32).powf(-0.5), mask, s)?;
        let merged = out
            .transpose_axes(&[0, 2, 1, 3], s)?
            .reshape(&[b, length, self.num_heads * self.head_dim], s)?;
        self.out_proj.apply(&merged, s)
    }
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

impl HeadLayer {
    fn apply(&self, x: &Array, mask: &Array, s: Stream) -> MlxResult<Array> {
        let h = x.add(
            &self
                .self_attn
                .apply(&layer_norm(x, &self.norm1, Some(&self.norm1_bias), self.eps, s)?, mask, s)?,
            s,
        )?;
        let ff = self
            .linear1
            .apply(&layer_norm(&h, &self.norm2, Some(&self.norm2_bias), self.eps, s)?, s)?;
        let ff = self.linear2.apply(&relu(&ff, s)?, s)?;
        h.add(&ff, s)
    }
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
                eps: norm_eps,
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

    pub fn forward(&self, batch: &Batch, s: Stream) -> MlxResult<ForwardOutput> {
        CURRENT_FW.with(|c| c.set(FORWARD_IDX.fetch_add(1, std::sync::atomic::Ordering::SeqCst)));
        dump_stage("in_ids", &batch.input_ids, s);
        dump_stage("in_mask", &batch.attention_mask, s);
        dump_stage("in_marker_pos", &batch.marker_pos, s);
        dump_stage("in_marker_mask", &batch.marker_mask, s);
        dump_stage("in_qtype", &batch.qtype, s);
        let mut h = self.encoder.apply(&batch.input_ids, &batch.attention_mask, s)?;
        let b = batch.qtype.dim(0);
        let type_rows = gather_rows(&self.type_emb, &batch.qtype, self.type_emb.dim(1), s)?;
        let type_add = type_rows.expand_dims(&[1], s)?;
        h = h.add(&type_add, s)?;
        let head_mask = batch
            .attention_mask
            .expand_dims(&[1, 2], s)?
            .astype(Dtype::Bool, s)?;
        for layer in &self.head_layers {
            h = layer.apply(&h, &head_mask, s)?;
        }

        let b = h.dim(0);
        let lengths = h.dim(1);
        let kmax = batch.marker_mask.dim(1);
        let hidden = self.hidden_size;

        // Gather marker vectors: flat take along axis 0 of [B*L, hidden].
        let flat = h.reshape(&[b * lengths, hidden], s)?;
        let rows = Array::arange_i32(0, b as i32, s)?.mul(&Array::scalar_i32(lengths as i32), s)?;
        let flat_index = batch
            .marker_pos
            .max_elemwise(&Array::scalar_i32(0), s)?
            .add(&rows.expand_dims(&[1], s)?, s)?;
        let markers = gather_rows(&flat, &flat_index, hidden, s)?
            .reshape(&[b, kmax, hidden], s)?;

        let normed = layer_norm(&markers, &self.scorer_norm, Some(&self.scorer_norm_bias), self.eps, s)?;
        let logits = self
            .scorer_linear2
            .apply(&gelu(&self.scorer_linear1.apply(&normed, s)?, s)?, s)?
            .reshape(&[b, kmax], s)?
            .astype(Dtype::Float32, s)?;
        let neg_cap = Array::full_f32(-1e4, &[b, kmax], s)?;
        let logits = Array::where_(&batch.marker_mask, &logits, &neg_cap, s)?;

        // Action head sees the pooled sequence plus a detached summary of the
        // answer distribution (the checkpoint's J1-M "escalate" feature set).
        let p = logits.softmax(s)?;
        let counts = batch
            .marker_mask
            .astype(Dtype::Float32, s)?
            .sum_axes(&[-1], false, s)?
            .max_elemwise(&Array::scalar_f32(2.0), s)?;
        let log_p = p.max_elemwise(&Array::scalar_f32(1e-9), s)?.log(s)?;
        // entropy = -(Σ p·log p) / log(counts)
        let entropy = p
            .mul(&log_p, s)?
            .sum_axes(&[-1], false, s)?
            .mul(&Array::scalar_f32(-1.0), s)?
            .div(&counts.log(s)?, s)?;
        let sorted_p = p.sort_axis(-1, s)?;
        let top1 = sorted_p
            .take_along_axis(&Array::full((kmax - 1) as f64, &[b, 1], Dtype::Int32, s)?, 1, s)?
            .squeeze_axes(&[1], s)?;
        let top2 = sorted_p
            .take_along_axis(&Array::full((kmax - 2) as f64, &[b, 1], Dtype::Int32, s)?, 1, s)?
            .squeeze_axes(&[1], s)?;
        let gap = top1.sub(&top2, s)?;
        let counts_scaled = counts.div(&Array::scalar_f32(255.0), s)?;
        let features = Array::stack_axis(&[&top1, &gap, &entropy, &counts_scaled], -1, s)?;
        let first = h
            .take_along_axis(&Array::full(0.0, &[b, 1, 1], Dtype::Int32, s)?, 1, s)?
            .squeeze_axes(&[1], s)?
            .astype(Dtype::Float32, s)?;
        let pooled = Array::concatenate_axis(&[&first, &features], -1, s)?;
        let pooled16 = pooled.astype(self.act_linear1.weight.dtype(), s)?;
        let action = self
            .act_linear2
            .apply(&gelu(&self.act_linear1.apply(&pooled16, s)?, s)?, s)?
            .astype(Dtype::Float32, s)?;

        // Materialize as float32 host-side (double conversion happens in the
        // JSON layer; float64 astype is unsupported on the GPU).
        dump_stage("logits", &logits, s);
        dump_stage("act", &action, s);
        let logits_v = read_rows(&logits, b, kmax, s)?;
        let act_v = read_rows(&action, b, 2, s)?;
        Ok(ForwardOutput {
            logits: logits_v,
            act: act_v,
        })
    }
}

/// Row gather from a [rows, cols] table through the flat take:
/// flatten to 1-D, indices = row_id*cols + col, take, reshape back.
/// (take_along_axis preserves the INDICES' shape, so it cannot express a
/// row gather with narrow indices — paid for in the golden bisection.)
fn gather_rows(table: &Array, row_ids: &Array, cols: usize, s: Stream) -> MlxResult<Array> {
    let rows = table.dim(0);
    let flat_table = table.reshape(&[rows * cols], s)?;
    // Always a column: [count, 1] * cols + [cols] broadcasts to [count, cols].
    let count: usize = (0..row_ids.ndim()).map(|d| row_ids.dim(d as i32)).product();
    let ids_col = row_ids.reshape(&[count, 1], s)?;
    let col_index = Array::arange_i32(0, cols as i32, s)?; // [cols]
    let flat_index = ids_col
        .mul(&Array::scalar_i32(cols as i32), s)?
        .add(&col_index, s)?; // broadcast [.., cols]
    flat_table.take(&flat_index, s)
}

fn read_rows(arr: &Array, rows: usize, cols: usize, s: Stream) -> MlxResult<Vec<Vec<f32>>> {
    let flat = arr.to_f32_vec(s)?;
    Ok((0..rows)
        .map(|r| ((r * cols)..((r + 1) * cols)).map(|i| flat[i]).collect())
        .collect())
}
