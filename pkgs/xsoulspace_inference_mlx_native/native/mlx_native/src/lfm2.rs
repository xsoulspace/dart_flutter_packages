//! LiquidAI LFM2 family (LFM2.5-1.2B-Instruct-MLX-4bit first) — the hybrid
//! short-conv/GQA decoder (ADR 0055: the concrete path to ADR 0051's
//! "≥45 tok/s 1.2B q4 class" gate). 16 blocks: 10 double-gated
//! short-range-convolution layers (O(n), NO KV cache — a sliding conv state
//! of the last L_cache-1 rows) + 6 full-attention layers (GQA 32/8 — the
//! qwen3 machinery reused op-for-op).
//!
//! The reference is mlx_lm's `models/lfm2.py` in the pinned venv
//! (`~/.venvs/mlx-ref`); every op dispatches through the binding table like
//! the qwen walk (eval1), so the RmsNorm row and any future rows apply
//! here too. The whole forward is ALSO a declared plan (ADR 0054 R6) and
//! that plan is the DEFAULT path — the imperative walk remains as its
//! bit-identity reference (`LAYA_LFM2_PLAN=0`). Parity is token-for-token
//! against a venv-recorded fixture (testdata/lfm25_12b_parity.json); the
//! fixture's prompt_ids come from the reference tokenizer (the Qwen-specific
//! bpe.rs does NOT encode LFM2 — tokenizer probes are deliberately absent
//! from this fixture).

use std::path::Path;

use serde::Deserialize;

use crate::bindings::BindingTable;
use crate::mlx::{Array, Dtype, MlxError, MlxResult, Stream};
use crate::plan::{BinKind, Node, Op, UnaryKind};
use crate::safetensors::{QuantizedTensor, SafetensorsFile};

const KV_STEP: usize = 256;

#[allow(non_snake_case)]
fn Bin(kind: BinKind) -> Op {
    Op::Binary { kind }
}

fn eval1(
    table: &BindingTable,
    name: &str,
    group: &str,
    op: Op,
    ins: &[&Array],
    s: Stream,
) -> MlxResult<Array> {
    let node = Node {
        name: name.to_string(),
        group: group.to_string(),
        op,
        inputs: Vec::new(),
        dump: None,
    };
    let outs = crate::bindings::eval(&node, ins, table, s)?;
    Ok(outs.into_iter().next().ok_or(MlxError(-9710))?)
}

#[derive(Deserialize)]
struct ConfigJson {
    hidden_size: usize,
    num_hidden_layers: usize,
    num_attention_heads: usize,
    num_key_value_heads: usize,
    norm_eps: f64,
    /// Top-level on the 1.2B/700M; the 2.6B nests it under
    /// `rope_parameters.rope_theta` — resolved after parse.
    rope_theta: Option<f64>,
    #[serde(default)]
    rope_parameters: Option<RopeParametersJson>,
    conv_bias: bool,
    conv_L_cache: usize,
    /// LFM2.5-style per-layer list; ABSENT in v1 configs (LFM2-700M),
    /// which carry `full_attn_idxs` instead — derived below.
    #[serde(default)]
    layer_types: Vec<String>,
    #[serde(default)]
    full_attn_idxs: Vec<usize>,
    quantization: Option<QuantizationJson>,
    block_ff_dim: Option<usize>,
    intermediate_size: Option<usize>,
    /// The reference's `block_auto_adjust_ff_dim` rounds 2/3*ff up to a
    /// multiple of this (256). LFM2.5-1.2B's 2*12288/3 = 8192 is exact, so
    /// the ceiling was invisible until the 700M row.
    #[serde(default = "default_multiple_of")]
    block_multiple_of: usize,
    #[serde(default)]
    tie_embedding: bool,
    /// 1 for the low-id-special checkpoints, 124894 for the 2.6B's 128k
    /// vocab — read, never guessed.
    #[serde(default = "default_bos")]
    bos_token_id: usize,
}

#[derive(Deserialize)]
struct RopeParametersJson {
    rope_theta: Option<f64>,
}

fn default_multiple_of() -> usize {
    256
}

fn default_bos() -> usize {
    1
}

impl ConfigJson {
    fn rope_theta_resolved(&self) -> f64 {
        self.rope_theta
            .or_else(|| self.rope_parameters.as_ref().and_then(|r| r.rope_theta))
            .unwrap_or(1_000_000.0)
    }
}

#[derive(Deserialize)]
struct QuantizationJson {
    group_size: i32,
    bits: i32,
}

pub struct Lfm2Config {
    pub hidden_size: usize,
    pub layers: usize,
    pub heads: usize,
    pub kv_heads: usize,
    pub head_dim: usize,
    pub ff_dim: usize,
    pub norm_eps: f32,
    pub rope_theta: f32,
    pub conv_l_cache: usize,
    pub conv_bias: bool,
    /// "conv" | "full_attention" per layer.
    pub layer_types: Vec<LayerKind>,
    pub group_size: i32,
    pub bits: i32,
    /// The checkpoint's BOS id (1 low-id-special, 124894 on the 2.6B).
    pub bos_token_id: usize,
}

#[derive(Clone, Copy, PartialEq)]
pub enum LayerKind {
    Conv,
    Attn,
}

enum Weight {
    Quant(QuantizedTensor),
    Plain(Array),
}


pub struct Lfm2Layer {
    pub kind: LayerKind,
    attn: Option<AttnWeights>,
    conv: Option<ConvWeights>,
    w1: Weight,
    w2: Weight,
    w3: Weight,
    operator_norm: Array,
    ffn_norm: Array,
}

struct AttnWeights {
    q: Weight,
    k: Weight,
    v: Weight,
    o: Weight,
    q_norm: Array,
    k_norm: Array,
}

struct ConvWeights {
    in_proj: Weight,
    /// Depthwise conv weight, sanitized [channels, kernel, 1] (bf16 plain).
    conv: Array,
    out_proj: Weight,
}

pub struct Lfm2 {
    pub cfg: Lfm2Config,
    embed: Weight,
    layers: Vec<Lfm2Layer>,
    embedding_norm: Array,
    table: BindingTable,
}

/// Per-layer cache: full-attention layers carry a qwen3-style KV pair
/// (identical 256-step growth policy), conv layers carry the last
/// L_cache-1 rows of Bx (None until the first chunk).
pub enum LayerCache {
    Attn { k: Option<Array>, v: Option<Array> },
    Conv(Option<Array>),
}

pub struct Lfm2Cache {
    pub layers: Vec<LayerCache>,
    pub offset: usize,
}

impl Lfm2Cache {
    pub fn new(layer_types: &[LayerKind]) -> Lfm2Cache {
        Lfm2Cache {
            layers: layer_types
                .iter()
                .map(|t| match t {
                    LayerKind::Attn => LayerCache::Attn { k: None, v: None },
                    LayerKind::Conv => LayerCache::Conv(None),
                })
                .collect(),
            offset: 0,
        }
    }

    pub fn reserve(
        &mut self,
        table: &BindingTable,
        kv_heads: usize,
        head_dim: usize,
        total: usize,
        s: Stream,
    ) -> MlxResult<()> {
        let prev = self.offset;
        let n = total.saturating_sub(prev);
        if n == 0 {
            return Ok(());
        }
        for (li, slot) in self.layers.iter_mut().enumerate() {
            if let LayerCache::Attn { k, v } = slot {
                grow(table, &format!("cache.k{li}"), k, prev, n, (1, kv_heads, head_dim), s)?;
                grow(table, &format!("cache.v{li}"), v, prev, n, (1, kv_heads, head_dim), s)?;
            }
        }
        Ok(())
    }

    /// Appends roped k/v to one attention layer's buffers — byte-for-byte
    /// the qwen KvCache policy (zero-padded 256-step growth, trim on
    /// misalignment, functional slice_update write, view down to total).
    fn attn_update(
        table: &BindingTable,
        name: &str,
        k_slot: &mut Option<Array>,
        v_slot: &mut Option<Array>,
        kr: &Array,
        vr: &Array,
        prev: usize,
        s: Stream,
    ) -> MlxResult<(Array, Array)> {
        let n = kr.dim(2) as usize;
        grow(table, &format!("{name}.k"), k_slot, prev, n, (1, kr.dim(1) as usize, kr.dim(3) as usize), s)?;
        grow(table, &format!("{name}.v"), v_slot, prev, n, (1, vr.dim(1) as usize, vr.dim(3) as usize), s)?;
        let write = |nm: &str, buf: &Option<Array>, new: &Array| -> MlxResult<Array> {
            let b = buf.as_ref().expect("grown");
            let (bh, dd) = (b.dim(1) as i32, b.dim(3) as i32);
            eval1(
                table,
                nm,
                "l.cache",
                Op::SliceUpdate {
                    start: vec![0, 0, prev as i32, 0],
                    stop: vec![1, bh, (prev + n) as i32, dd],
                    strides: vec![1, 1, 1, 1],
                },
                &[b, new],
                s,
            )
        };
        let kb = write(&format!("{name}.kw"), k_slot, kr)?;
        let vb = write(&format!("{name}.vw"), v_slot, vr)?;
        let total = prev + n;
        let view = |nm: &str, buf: &Array| -> MlxResult<Array> {
            if total < buf.dim(2) as usize {
                let (b, h, d) = (buf.dim(0) as i32, buf.dim(1) as i32, buf.dim(3) as i32);
                eval1(
                    table,
                    nm,
                    "l.cache",
                    Op::Slice {
                        start: vec![0, 0, 0, 0],
                        stop: vec![b, h, total as i32, d],
                        strides: vec![1, 1, 1, 1],
                    },
                    &[buf],
                    s,
                )
            } else {
                buf.identity(s)
            }
        };
        Ok((view(&format!("{name}.kv"), &kb)?, view(&format!("{name}.vv"), &vb)?))
    }
}

/// The shared 256-step growth policy (qwen's update_one, same math).
fn grow(
    table: &BindingTable,
    name: &str,
    slot: &mut Option<Array>,
    prev: usize,
    n: usize,
    bhd: (usize, usize, usize),
    s: Stream,
) -> MlxResult<()> {
    let needed = prev + n;
    let buf = match slot {
        Some(bf) if needed <= bf.dim(2) as usize => return Ok(()),
        None => {
            let (b, h, d) = bhd;
            let alloc = (KV_STEP + n - 1) / KV_STEP * KV_STEP;
            eval1(
                table,
                &format!("{name}.zeros"),
                "l.cache",
                Op::Full { value: 0.0, dtype: Dtype::BFloat16, shape: vec![b, h, alloc, d] },
                &[],
                s,
            )?
        }
        Some(bf) => {
            let block = (KV_STEP + n - 1) / KV_STEP * KV_STEP;
            let (b, h, d) = (bf.dim(0) as usize, bf.dim(1) as usize, bf.dim(3) as usize);
            let trimmed = if prev % KV_STEP != 0 {
                eval1(
                    table,
                    &format!("{name}.trim"),
                    "l.cache",
                    Op::Slice {
                        start: vec![0, 0, 0, 0],
                        stop: vec![b as i32, h as i32, prev as i32, d as i32],
                        strides: vec![1, 1, 1, 1],
                    },
                    &[bf],
                    s,
                )?
            } else {
                bf.identity(s)?
            };
            let zeros = eval1(
                table,
                &format!("{name}.zeros"),
                "l.cache",
                Op::Full { value: 0.0, dtype: Dtype::BFloat16, shape: vec![b, h, block, d] },
                &[],
                s,
            )?;
            eval1(
                table,
                &format!("{name}.grow"),
                "l.cache",
                Op::Concatenate { axis: 2 },
                &[&trimmed, &zeros],
                s,
            )?
        }
    };
    *slot = Some(buf);
    Ok(())
}

/// The declared forward plan is the DEFAULT path (ADR 0054 R6, promoted
/// after the bit-parity gate): `LAYA_LFM2_PLAN=0` reverts to the imperative
/// walk for A/B — the same pattern as the qwen step plan.
fn lfm2_plan_mode() -> bool {
    use std::sync::OnceLock;
    static ON: OnceLock<bool> = OnceLock::new();
    *ON.get_or_init(|| {
        std::env::var_os("LAYA_LFM2_PLAN")
            .map(|v| v != "0")
            .unwrap_or(true)
    })
}

/// One declared forward (decode l = 1 or a prefill chunk l > 1, ADR 0054
/// R6) plus the pool entries that are not per-call inputs (the weights —
/// owned by [`Lfm2`], which outlives the execution).
pub struct ForwardPlan<'a> {
    pub plan: crate::plan::Plan,
    pub pool_weights: Vec<&'a Array>,
}

impl Lfm2 {
    /// The binding table (public read: drivers that drive the cache —
    /// e.g. the model bench's whole-window reserve — need it for
    /// `Lfm2Cache::reserve`), mirroring `Qwen3::table`.
    pub fn table(&self) -> &crate::bindings::BindingTable {
        &self.table
    }

    pub fn load(dir: &Path) -> MlxResult<Lfm2> {
        // The conv-weight sanitize (python's Model.sanitize) needs a stream;
        // this engine is GPU-only anyway.
        let s = crate::mlx::gpu()?;
        let cfg_raw: ConfigJson = serde_json::from_str(
            &std::fs::read_to_string(dir.join("config.json")).map_err(|_| MlxError(-12))?,
        )
        .map_err(|_| MlxError(-12))?;
        let (group_size, bits) = match &cfg_raw.quantization {
            Some(q) => (q.group_size, q.bits),
            None => (0, 0),
        };
        let head_dim = cfg_raw.hidden_size / cfg_raw.num_attention_heads;
        // ff_dim mirrors the reference's auto-adjust: 2/3 of block_ff_dim,
        // rounded UP to block_multiple_of (LFM2.5-1.2B: 2*12288/3 = 8192,
        // exact; LFM2-700M: 2*10240/3 = 6826.67 -> 6912 — the ceiling was
        // invisible until this row).
        let ff_base = cfg_raw.block_ff_dim.or(cfg_raw.intermediate_size).unwrap_or(8192);
        let m = cfg_raw.block_multiple_of;
        let ff_dim = ((2 * ff_base) / 3).div_ceil(m) * m;
        let layer_types = if !cfg_raw.layer_types.is_empty() {
            cfg_raw
                .layer_types
                .iter()
                .map(|t| match t.as_str() {
                    "conv" => LayerKind::Conv,
                    _ => LayerKind::Attn,
                })
                .collect::<Vec<_>>()
        } else {
            // v1 config dialect: full_attn_idxs lists the attention layers;
            // everything else is a conv block.
            let attn = |i: usize| cfg_raw.full_attn_idxs.contains(&i);
            (0..cfg_raw.num_hidden_layers)
                .map(|i| if attn(i) { LayerKind::Attn } else { LayerKind::Conv })
                .collect::<Vec<_>>()
        };
        let cfg = Lfm2Config {
            hidden_size: cfg_raw.hidden_size,
            layers: cfg_raw.num_hidden_layers,
            heads: cfg_raw.num_attention_heads,
            kv_heads: cfg_raw.num_key_value_heads,
            head_dim,
            ff_dim,
            norm_eps: cfg_raw.norm_eps as f32,
            rope_theta: cfg_raw.rope_theta_resolved() as f32,
            conv_l_cache: cfg_raw.conv_L_cache,
            conv_bias: cfg_raw.conv_bias,
            layer_types,
            group_size,
            bits,
            bos_token_id: cfg_raw.bos_token_id,
        };

        let st = SafetensorsFile::open(&dir.join("model.safetensors"))?;
        // Some mlx-community conversions wrap the text model for a
        // multimodal container and prefix every weight with
        // `language_model.` (the LFM2.5-2.6B ships an empty vision_config
        // this way). Detect once from the embedding row; never guess per
        // weight.
        let prefix = if st.dtype_of("model.embed_tokens.weight").is_some() {
            ""
        } else if st
            .dtype_of("language_model.model.embed_tokens.weight")
            .is_some()
        {
            "language_model."
        } else {
            return Err(MlxError(-13));
        };
        let weight = |name: &str| -> MlxResult<Weight> {
            if st.dtype_of(&format!("{name}.scales")).is_some() {
                Ok(Weight::Quant(st.take_quantized(name)?))
            } else {
                Ok(Weight::Plain(st.take_any(&format!("{name}.weight"))?))
            }
        };

        let mut layers = Vec::with_capacity(cfg.layers);
        for (li, kind) in cfg.layer_types.iter().enumerate() {
            let p = format!("{prefix}model.layers.{li}");
            let (attn, conv) = match kind {
                LayerKind::Attn => (
                    Some(AttnWeights {
                        q: weight(&format!("{p}.self_attn.q_proj"))?,
                        k: weight(&format!("{p}.self_attn.k_proj"))?,
                        v: weight(&format!("{p}.self_attn.v_proj"))?,
                        o: weight(&format!("{p}.self_attn.out_proj"))?,
                        q_norm: st.take_any(&format!("{p}.self_attn.q_layernorm.weight"))?,
                        k_norm: st.take_any(&format!("{p}.self_attn.k_layernorm.weight"))?,
                    }),
                    None,
                ),
                LayerKind::Conv => (
                    None,
                    Some(ConvWeights {
                        in_proj: weight(&format!("{p}.conv.in_proj"))?,
                        // sanitize(): [channels, 1, kernel] → [channels, kernel, 1]
                        conv: {
                            let w = st.take_any(&format!("{p}.conv.conv.weight"))?;
                            if w.dim(2) as usize > w.dim(1) as usize {
                                w.transpose_axes(&[0, 2, 1], s)?
                            } else {
                                w
                            }
                        },
                        out_proj: weight(&format!("{p}.conv.out_proj"))?,
                    }),
                ),
            };
            layers.push(Lfm2Layer {
                kind: *kind,
                attn,
                conv,
                w1: weight(&format!("{p}.feed_forward.w1"))?,
                w2: weight(&format!("{p}.feed_forward.w2"))?,
                w3: weight(&format!("{p}.feed_forward.w3"))?,
                operator_norm: st.take_any(&format!("{p}.operator_norm.weight"))?,
                ffn_norm: st.take_any(&format!("{p}.ffn_norm.weight"))?,
            });
        }

        Ok(Lfm2 {
            cfg,
            embed: weight(&format!("{prefix}model.embed_tokens"))?,
            layers,
            embedding_norm: st.take_any(&format!("{prefix}model.embedding_norm.weight"))?,
            table: BindingTable::baseline(),
        })
    }

    fn linear(&self, name: &str, w: &Weight, x: &Array, s: Stream) -> MlxResult<Array> {
        match w {
            Weight::Quant(q) => eval1(
                &self.table,
                name,
                "l.linear",
                Op::QuantizedMatmul {
                    group_size: self.cfg.group_size,
                    bits: self.cfg.bits,
                    transpose: true,
                },
                &[x, &q.w, &q.scales, &q.biases],
                s,
            ),
            Weight::Plain(w) => {
                let wt = eval1(
                    &self.table,
                    &format!("{name}.w_t"),
                    "l.linear",
                    Op::Transpose { axes: vec![1, 0] },
                    &[w],
                    s,
                )?;
                eval1(&self.table, name, "l.linear", Op::Matmul, &[x, &wt], s)
            }
        }
    }

    fn rms(&self, name: &str, x: &Array, weight: &Array, s: Stream) -> MlxResult<Array> {
        eval1(
            &self.table,
            name,
            "l.norm",
            Op::RmsNorm { eps: self.cfg.norm_eps },
            &[x, weight],
            s,
        )
    }

    /// QuantizedEmbedding gather + dequant (plain tables gather directly).
    fn embed(&self, ids: &Array, l: usize, s: Stream) -> MlxResult<Array> {
        match &self.embed {
            Weight::Quant(q) => {
                let packed_row = q.w.dim(1) as i32;
                let scale_row = q.scales.dim(1) as i32;
                let wq = self.gather_rows("embed.w", &q.w, ids, l, packed_row, s)?;
                let ws = self.gather_rows("embed.s", &q.scales, ids, l, scale_row, s)?;
                let wb = self.gather_rows("embed.b", &q.biases, ids, l, scale_row, s)?;
                eval1(
                    &self.table,
                    "embed.deq",
                    "l.embed",
                    Op::Dequantize { group_size: self.cfg.group_size, bits: self.cfg.bits },
                    &[&wq, &ws, &wb],
                    s,
                )
            }
            Weight::Plain(w) => {
                self.gather_rows("embed.plain", w, ids, l, self.cfg.hidden_size as i32, s)
            }
        }
    }

    fn gather_rows(
        &self,
        name: &str,
        table_arr: &Array,
        ids: &Array,
        l: usize,
        cols: i32,
        s: Stream,
    ) -> MlxResult<Array> {
        let count: usize = (0..table_arr.ndim())
            .map(|d| table_arr.dim(d as i32) as usize)
            .product();
        let flat = eval1(
            &self.table,
            &format!("{name}.flat"),
            "l.embed",
            Op::Reshape { shape: vec![count] },
            &[table_arr],
            s,
        )?;
        let cols_c = eval1(
            &self.table,
            &format!("{name}.cols"),
            "l.embed",
            Op::ConstI32 { value: cols },
            &[],
            s,
        )?;
        let ids_col = eval1(
            &self.table,
            &format!("{name}.ids_col"),
            "l.embed",
            Op::Reshape { shape: vec![1, l, 1] },
            &[ids],
            s,
        )?;
        let scaled = eval1(
            &self.table,
            &format!("{name}.ids_scaled"),
            "l.embed",
            Bin(BinKind::Mul),
            &[&ids_col, &cols_c],
            s,
        )?;
        let col_idx = eval1(
            &self.table,
            &format!("{name}.cols_idx"),
            "l.embed",
            Op::ArangeI32 { start: 0, stop: cols },
            &[],
            s,
        )?;
        let flat_idx = eval1(
            &self.table,
            &format!("{name}.flat_idx"),
            "l.embed",
            Bin(BinKind::Add),
            &[&scaled, &col_idx],
            s,
        )?;
        eval1(&self.table, name, "l.embed", Op::Take, &[&flat, &flat_idx], s)
    }

    /// The whole transformer except the tied-embedding head — the declared
    /// plan is the DEFAULT path (ADR 0054 R6, promoted after the bit-parity
    /// gate); `LAYA_LFM2_PLAN=0` reverts to the imperative walk for A/B,
    /// the same pattern as the qwen step plan.
    pub fn forward_hidden(
        &self,
        tokens: &Array,
        cache: &mut Lfm2Cache,
        s: Stream,
    ) -> MlxResult<Array> {
        self.hidden_states(tokens, cache, lfm2_plan_mode(), s)
    }

    /// One forward pass on an explicit path: `use_plan` runs the declared
    /// plan (decode l = 1 or a prefill chunk l > 1, ADR 0054 R6), else the
    /// imperative walk. Bit-identity is the parity tests' contract.
    pub fn hidden_states(
        &self,
        tokens: &Array,
        cache: &mut Lfm2Cache,
        use_plan: bool,
        s: Stream,
    ) -> MlxResult<Array> {
        if use_plan {
            return self.forward_plan(tokens, cache, false, s);
        }
        self.forward_hidden_impl(tokens, cache, s)
    }

    /// The imperative walk (one `eval1` through the binding table per op) —
    /// the plan path's bit-identity reference.
    fn forward_hidden_impl(
        &self,
        tokens: &Array,
        cache: &mut Lfm2Cache,
        s: Stream,
    ) -> MlxResult<Array> {
        let l = tokens.dim(1) as usize;
        let cfg = &self.cfg;
        let (n_h, n_kv, d) = (cfg.heads, cfg.kv_heads, cfg.head_dim);
        let scale = (d as f32).powf(-0.5);
        let mut h = self.embed(tokens, l, s)?;

        for (li, layer) in self.layers.iter().enumerate() {
            let g = format!("l.l{li:02}");
            let normed = self.rms(&format!("{g}.op_norm"), &h, &layer.operator_norm, s)?;
            let r = match (layer.kind, &layer.attn, &layer.conv) {
                (LayerKind::Attn, Some(attn), _) => {
                    let q = self.linear(&format!("{g}.q"), &attn.q, &normed, s)?;
                    let k = self.linear(&format!("{g}.k"), &attn.k, &normed, s)?;
                    let v = self.linear(&format!("{g}.v"), &attn.v, &normed, s)?;
                    let qh = eval1(&self.table, &format!("{g}.q_h"), &g, Op::Reshape { shape: vec![1, l, n_h, d] }, &[&q], s)?;
                    let kh = eval1(&self.table, &format!("{g}.k_h"), &g, Op::Reshape { shape: vec![1, l, n_kv, d] }, &[&k], s)?;
                    let vh = eval1(&self.table, &format!("{g}.v_h"), &g, Op::Reshape { shape: vec![1, l, n_kv, d] }, &[&v], s)?;
                    let qn = self.rms(&format!("{g}.q_norm"), &qh, &attn.q_norm, s)?;
                    let kn = self.rms(&format!("{g}.k_norm"), &kh, &attn.k_norm, s)?;
                    let qt = eval1(&self.table, &format!("{g}.q_t"), &g, Op::Transpose { axes: vec![0, 2, 1, 3] }, &[&qn], s)?;
                    let kt = eval1(&self.table, &format!("{g}.k_t"), &g, Op::Transpose { axes: vec![0, 2, 1, 3] }, &[&kn], s)?;
                    let vt = eval1(&self.table, &format!("{g}.v_t"), &g, Op::Transpose { axes: vec![0, 2, 1, 3] }, &[&vh], s)?;
                    let off = cache.offset as i32;
                    let qr = eval1(&self.table, &format!("{g}.rope_q"), &g, Op::Rope { dims: d as i32, base: cfg.rope_theta, offset: off }, &[&qt], s)?;
                    let kr = eval1(&self.table, &format!("{g}.rope_k"), &g, Op::Rope { dims: d as i32, base: cfg.rope_theta, offset: off }, &[&kt], s)?;
                    let (k_slot, v_slot) = match &mut cache.layers[li] {
                        LayerCache::Attn { k, v } => (k, v),
                        _ => return Err(MlxError(-978)),
                    };
                    let (kc, vc) = Lfm2Cache::attn_update(&self.table, &format!("{g}.cache"), k_slot, v_slot, &kr, &vt, cache.offset, s)?;
                    // THE qwen lesson, ported late: attn_update is functional —
                    // the written buffers must land back in the slots or every
                    // decode step attends to an empty cache (the prefill hides
                    // this because its single chunk consumes the update's
                    // return value directly).
                    if let LayerCache::Attn { k, v } = &mut cache.layers[li] {
                        *k = Some(kc.identity(s)?);
                        *v = Some(vc.identity(s)?);
                    }
                    let att = eval1(
                        &self.table,
                        &format!("{g}.sdp"),
                        &g,
                        Op::Sdp { scale, causal: l > 1 },
                        &[&qr, &kc, &vc],
                        s,
                    )?;
                    let att_t = eval1(&self.table, &format!("{g}.att_t"), &g, Op::Transpose { axes: vec![0, 2, 1, 3] }, &[&att], s)?;
                    let att_r = eval1(&self.table, &format!("{g}.att_r"), &g, Op::Reshape { shape: vec![1, l, n_h * d] }, &[&att_t], s)?;
                    self.linear(&format!("{g}.o"), &attn.o, &att_r, s)?
                }
                (LayerKind::Conv, _, Some(conv)) => {
                    // Reference ShortConv: BCx = in_proj(x); B,C,x = split;
                    // Bx = B*x; Bx = concat(state, Bx); state = Bx[:, -2:];
                    // y = C * conv1d(Bx); out_proj(y).
                    let bcx = self.linear(&format!("{g}.in_proj"), &conv.in_proj, &normed, s)?;
                    let parts = {
                        let node = Node {
                            name: format!("{g}.split"),
                            group: g.clone(),
                            op: Op::Split { num: 3, axis: -1 },
                            inputs: Vec::new(),
                            dump: None,
                        };
                        crate::bindings::eval(&node, &[&bcx], &self.table, s)?
                    };
                    if parts.len() != 3 {
                        return Err(MlxError(-982));
                    }
                    let (b, c, x) = (&parts[0], &parts[1], &parts[2]);
                    let bx = eval1(&self.table, &format!("{g}.bx"), &g, Bin(BinKind::Mul), &[b, x], s)?;
                    let state_len = cfg.conv_l_cache - 1;
                    let bx_full = match &cache.layers[li] {
                        LayerCache::Conv(Some(state)) => eval1(
                            &self.table,
                            &format!("{g}.state_cat"),
                            &g,
                            Op::Concatenate { axis: 1 },
                            &[state, &bx],
                            s,
                        )?,
                        _ => {
                            // First chunk: zeros prefix [1, L_cache-1, hidden].
                            let zeros = eval1(
                                &self.table,
                                &format!("{g}.state_zeros"),
                                &g,
                                Op::Full {
                                    value: 0.0,
                                    dtype: Dtype::BFloat16,
                                    shape: vec![1, state_len, cfg.hidden_size],
                                },
                                &[],
                                s,
                            )?;
                            eval1(
                                &self.table,
                                &format!("{g}.state_cat"),
                                &g,
                                Op::Concatenate { axis: 1 },
                                &[&zeros, &bx],
                                s,
                            )?
                        }
                    };
                    // New state: the last L_cache-1 rows of the padded Bx.
                    let new_state = eval1(
                        &self.table,
                        &format!("{g}.state_next"),
                        &g,
                        Op::Slice {
                            start: vec![0, l as i32, 0],
                            stop: vec![1, (l + state_len) as i32, cfg.hidden_size as i32],
                            strides: vec![1, 1, 1],
                        },
                        &[&bx_full],
                        s,
                    )?;
                    cache.layers[li] = LayerCache::Conv(Some(new_state.identity(s)?));
                    let conv_out = eval1(
                        &self.table,
                        &format!("{g}.conv"),
                        &g,
                        Op::Conv1d { stride: 1, padding: 0, dilation: 1, groups: cfg.hidden_size as i32 },
                        &[&bx_full, &conv.conv],
                        s,
                    )?;
                    let y = eval1(&self.table, &format!("{g}.gate"), &g, Bin(BinKind::Mul), &[c, &conv_out], s)?;
                    let r = self.linear(&format!("{g}.out_proj"), &conv.out_proj, &y, s)?;
                    r
                }
                _ => return Err(MlxError(-9711)),
            };
            let h1 = eval1(&self.table, &format!("{g}.res1"), &g, Bin(BinKind::Add), &[&h, &r], s)?;
            let ff_in = self.rms(&format!("{g}.ffn_norm"), &h1, &layer.ffn_norm, s)?;
            let g1 = self.linear(&format!("{g}.w1"), &layer.w1, &ff_in, s)?;
            let g3 = self.linear(&format!("{g}.w3"), &layer.w3, &ff_in, s)?;
            let sig = eval1(&self.table, &format!("{g}.sig"), &g, Op::Unary { kind: UnaryKind::Sigmoid }, &[&g1], s)?;
            let silu = eval1(&self.table, &format!("{g}.silu"), &g, Bin(BinKind::Mul), &[&g1, &sig], s)?;
            let ff = eval1(&self.table, &format!("{g}.ff_in"), &g, Bin(BinKind::Mul), &[&silu, &g3], s)?;
            let g2 = self.linear(&format!("{g}.w2"), &layer.w2, &ff, s)?;
            h = eval1(&self.table, &format!("{g}.res2"), &g, Bin(BinKind::Add), &[&h1, &g2], s)?;
        }
        let t = self.rms("l.embedding_norm", &h, &self.embedding_norm, s)?;
        cache.offset += l;
        Ok(t)
    }

    /// One forward pass with the tied-embedding head — plan-default
    /// dispatch (see [`Lfm2::forward_hidden`]). Returns logits [1, L, V]
    /// (unevaluated).
    pub fn forward_step(
        &self,
        tokens: &Array,
        cache: &mut Lfm2Cache,
        s: Stream,
    ) -> MlxResult<Array> {
        self.step_logits(tokens, cache, lfm2_plan_mode(), s)
    }

    /// The decode step on an explicit path: `use_plan` runs the declared
    /// step plan (head inside the plan), else the imperative walk. Both
    /// submit the same ops through the same binding table — the parity
    /// test guards bit-identity between them.
    pub fn step_logits(
        &self,
        tokens: &Array,
        cache: &mut Lfm2Cache,
        use_plan: bool,
        s: Stream,
    ) -> MlxResult<Array> {
        if use_plan {
            // The declared plan runs the head too; its tail IS the logits.
            return self.forward_plan(tokens, cache, true, s);
        }
        let t = self.forward_hidden_impl(tokens, cache, s)?;
        let logits = self.linear("l.lm_head", &self.embed, &t, s)?;
        Ok(logits)
    }

    /// Runs one forward through the declared plan. The attention KV
    /// buffers are grown OUTSIDE the plan first (allocation is an engine
    /// concern, [`grow`]'s exact policy — the plan sees fixed buffers);
    /// conv states are fixed-size (L_cache-1 rows) and never grow. The
    /// written buffers/states land back in the slots after execution (the
    /// qwen lesson: functional updates must be stored back or the next
    /// step reads a stale cache).
    fn forward_plan(
        &self,
        tokens: &Array,
        cache: &mut Lfm2Cache,
        with_head: bool,
        s: Stream,
    ) -> MlxResult<Array> {
        let l = tokens.dim(1) as usize;
        let offset = cache.offset; // constant for this plan (RoPE + slice bounds)
        {
            let (n_kv, d) = (self.cfg.kv_heads, self.cfg.head_dim);
            for (li, slot) in cache.layers.iter_mut().enumerate() {
                if let LayerCache::Attn { k, v } = slot {
                    grow(&self.table, &format!("cache.k{li}"), k, offset, l, (1, n_kv, d), s)?;
                    grow(&self.table, &format!("cache.v{li}"), v, offset, l, (1, n_kv, d), s)?;
                }
            }
        }
        let fp = self.build_forward_plan(tokens, cache, offset, l, with_head)?;
        if let Some(path) = std::env::var_os("LAYA_LFM2_PLAN_DUMP") {
            let _ = std::fs::write(std::path::PathBuf::from(path), fp.plan.to_json());
        }
        // Pool order mirrors build_forward_plan's registration order: tokens,
        // then every pinned array (state/KV buffers, weights) in first-use
        // order. Weight/cache arrays are owned by `self`/`cache`, which
        // outlive the execution.
        let mut pool: Vec<&Array> = Vec::with_capacity(fp.pool_weights.len() + 1);
        pool.push(tokens);
        pool.extend(fp.pool_weights.iter().copied());
        let outs = crate::plan::execute_outputs(
            &fp.plan,
            &crate::plan::ExecPool { arrays: pool },
            &self.table,
            s,
            crate::plan::ExecOptions::runtime(),
        )?;
        // Outputs: [state writes per layer in declaration order, (hidden |
        // logits)] — two per attention layer (k', v'), one per conv layer
        // (new state).
        let tail = outs.last().ok_or(MlxError(-983))?.identity(s)?;
        let mut oi = 0usize;
        for slot in cache.layers.iter_mut() {
            match slot {
                LayerCache::Attn { k, v } => {
                    *k = Some(outs[oi].identity(s)?);
                    *v = Some(outs[oi + 1].identity(s)?);
                    oi += 2;
                }
                LayerCache::Conv(st) => {
                    *st = Some(outs[oi].identity(s)?);
                    oi += 1;
                }
            }
        }
        cache.offset += l;
        Ok(tail)
    }

    /// Declares one forward (decode l = 1, or a prefill chunk l > 1) as a
    /// plan: node-for-node the imperative walk — same ops, same order,
    /// same names — with the RoPE offset and slice bounds as per-plan
    /// constants (the plan is rebuilt per call, like the qwen step plan).
    /// Attention KV buffers and conv states are plan inputs; the written
    /// buffers/states plus (hidden | logits) are the declared outputs
    /// (functional slice_update / slice, python-parity order). Prefill
    /// chunks run KV/CONV-ONLY: `with_head = false` ends the plan at the
    /// final norm (a chunk's logits are never read — the R5 waste this
    /// exists to keep dead).
    fn build_forward_plan<'a>(
        &'a self,
        tokens: &Array,
        cache: &'a Lfm2Cache,
        offset: usize,
        l: usize,
        with_head: bool,
    ) -> MlxResult<ForwardPlan<'a>> {
        let cfg = &self.cfg;
        let (n_h, n_kv, d) = (cfg.heads, cfg.kv_heads, cfg.head_dim);
        let total = offset + l; // plan constant (RoPE + slice bounds)
        let scale = (d as f32).powf(-0.5);
        let state_len = cfg.conv_l_cache - 1;
        let mut b = crate::plan::PlanBuilder::default();
        let mut pool_weights: Vec<&'a Array> = Vec::new();
        // Every non-token array enters the pool through an Input node; the
        // executor skips Input nodes, so duplicates only cost pool slots.
        let pin = |b: &mut crate::plan::PlanBuilder,
                   pool: &mut Vec<&'a Array>,
                   arr: &'a Array,
                   name: &str|
         -> crate::plan::NodeId { pool.push(arr); b.input(name, None) };

        // pool[0]; NOT registered in pool_weights (the pool already carries it).
        let tok = b.input("l.tokens", None);

        // ---- embed (QuantizedEmbedding gather + dequant, op for op) ----
        let emb_g = "l.embed";
        let gather = |b: &mut crate::plan::PlanBuilder,
                      pool: &mut Vec<&'a Array>,
                      nm: &str,
                      table_arr: &'a Array,
                      cols: i32|
         -> MlxResult<crate::plan::NodeId> {
            let tn = pin(b, pool, table_arr, &format!("{nm}.table"));
            let count: usize =
                (0..table_arr.ndim()).map(|dd| table_arr.dim(dd as i32) as usize).product();
            let flat = b.push(emb_g, Op::Reshape { shape: vec![count] }, &format!("{nm}.flat"), &[(tn, 0)], None);
            let cols_c = b.push(emb_g, Op::ConstI32 { value: cols }, &format!("{nm}.cols"), &[], None);
            let ids_col = b.push(emb_g, Op::Reshape { shape: vec![1, l, 1] }, &format!("{nm}.ids_col"), &[(tok, 0)], None);
            let scaled = b.push(emb_g, Bin(BinKind::Mul), &format!("{nm}.ids_scaled"), &[(ids_col, 0), (cols_c, 0)], None);
            let col_idx = b.push(emb_g, Op::ArangeI32 { start: 0, stop: cols }, &format!("{nm}.cols_idx"), &[], None);
            let flat_idx = b.push(emb_g, Bin(BinKind::Add), &format!("{nm}.flat_idx"), &[(scaled, 0), (col_idx, 0)], None);
            Ok(b.push(emb_g, Op::Take, nm, &[(flat, 0), (flat_idx, 0)], None))
        };
        let h: crate::plan::NodeId = match &self.embed {
            Weight::Quant(q) => {
                let packed_row = q.w.dim(1) as i32;
                let scale_row = q.scales.dim(1) as i32;
                let wq = gather(&mut b, &mut pool_weights, "embed.w", &q.w, packed_row)?;
                let ws = gather(&mut b, &mut pool_weights, "embed.s", &q.scales, scale_row)?;
                let wb = gather(&mut b, &mut pool_weights, "embed.b", &q.biases, scale_row)?;
                b.push(emb_g, Op::Dequantize { group_size: cfg.group_size, bits: cfg.bits }, "embed.deq", &[(wq, 0), (ws, 0), (wb, 0)], None)
            }
            Weight::Plain(w) => {
                gather(&mut b, &mut pool_weights, "embed.plain", w, cfg.hidden_size as i32)?
            }
        };
        let mut h = h;

        // ---- per layer ----
        let mut writes: Vec<crate::plan::NodeId> = Vec::with_capacity(cfg.layers * 2);
        for (li, layer) in self.layers.iter().enumerate() {
            let g = format!("l.l{li:02}");
            let on_w = pin(&mut b, &mut pool_weights, &layer.operator_norm, &format!("{g}.op_norm.w"));
            let normed = b.push("l.norm", Op::RmsNorm { eps: cfg.norm_eps }, &format!("{g}.op_norm"), &[(h, 0), (on_w, 0)], None);
            let linear = |b: &mut crate::plan::PlanBuilder,
                          pool: &mut Vec<&'a Array>,
                          nm: &str,
                          w: &'a Weight,
                          x: crate::plan::Slot|
             -> MlxResult<crate::plan::NodeId> {
                match w {
                    Weight::Quant(q) => {
                        let wn = pin(b, pool, &q.w, &format!("{nm}.q8"));
                        let sn = pin(b, pool, &q.scales, &format!("{nm}.q8_scales"));
                        let bn = pin(b, pool, &q.biases, &format!("{nm}.q8_biases"));
                        Ok(b.push("l.linear", Op::QuantizedMatmul { group_size: cfg.group_size, bits: cfg.bits, transpose: true }, nm, &[x, (wn, 0), (sn, 0), (bn, 0)], None))
                    }
                    Weight::Plain(w) => {
                        let wn = pin(b, pool, w, &format!("{nm}.w"));
                        let wt = b.push("l.linear", Op::Transpose { axes: vec![1, 0] }, &format!("{nm}.w_t"), &[(wn, 0)], None);
                        Ok(b.push("l.linear", Op::Matmul, nm, &[x, (wt, 0)], None))
                    }
                }
            };
            let r: crate::plan::NodeId = match (layer.kind, &layer.attn, &layer.conv) {
                (LayerKind::Attn, Some(attn), _) => {
                    let q = linear(&mut b, &mut pool_weights, &format!("{g}.q"), &attn.q, (normed, 0))?;
                    let k = linear(&mut b, &mut pool_weights, &format!("{g}.k"), &attn.k, (normed, 0))?;
                    let v = linear(&mut b, &mut pool_weights, &format!("{g}.v"), &attn.v, (normed, 0))?;
                    let qh = b.push(&g, Op::Reshape { shape: vec![1, l, n_h, d] }, &format!("{g}.q_h"), &[(q, 0)], None);
                    let kh = b.push(&g, Op::Reshape { shape: vec![1, l, n_kv, d] }, &format!("{g}.k_h"), &[(k, 0)], None);
                    let vh = b.push(&g, Op::Reshape { shape: vec![1, l, n_kv, d] }, &format!("{g}.v_h"), &[(v, 0)], None);
                    let qn_w = pin(&mut b, &mut pool_weights, &attn.q_norm, &format!("{g}.q_norm.w"));
                    let qn = b.push("l.norm", Op::RmsNorm { eps: cfg.norm_eps }, &format!("{g}.q_norm"), &[(qh, 0), (qn_w, 0)], None);
                    let kn_w = pin(&mut b, &mut pool_weights, &attn.k_norm, &format!("{g}.k_norm.w"));
                    let kn = b.push("l.norm", Op::RmsNorm { eps: cfg.norm_eps }, &format!("{g}.k_norm"), &[(kh, 0), (kn_w, 0)], None);
                    let qt = b.push(&g, Op::Transpose { axes: vec![0, 2, 1, 3] }, &format!("{g}.q_t"), &[(qn, 0)], None);
                    let kt = b.push(&g, Op::Transpose { axes: vec![0, 2, 1, 3] }, &format!("{g}.k_t"), &[(kn, 0)], None);
                    let vt = b.push(&g, Op::Transpose { axes: vec![0, 2, 1, 3] }, &format!("{g}.v_t"), &[(vh, 0)], None);
                    let qr = b.push(&g, Op::Rope { dims: d as i32, base: cfg.rope_theta, offset: offset as i32 }, &format!("{g}.rope_q"), &[(qt, 0)], None);
                    let kr = b.push(&g, Op::Rope { dims: d as i32, base: cfg.rope_theta, offset: offset as i32 }, &format!("{g}.rope_k"), &[(kt, 0)], None);

                    // Cache write: buf[..., off:off+l, :] = roped k/v
                    // (functional; buffers pre-grown outside the plan).
                    let (kb_in, vb_in) = match &cache.layers[li] {
                        LayerCache::Attn { k: Some(kb), v: Some(vb) } => (
                            pin(&mut b, &mut pool_weights, kb, &format!("{g}.kbuf")),
                            pin(&mut b, &mut pool_weights, vb, &format!("{g}.vbuf")),
                        ),
                        _ => return Err(MlxError(-978)),
                    };
                    let (bh, dd) = (n_kv as i32, d as i32);
                    let kc = b.push("l.cache", Op::SliceUpdate { start: vec![0, 0, offset as i32, 0], stop: vec![1, bh, total as i32, dd], strides: vec![1, 1, 1, 1] }, &format!("{g}.cache.kw"), &[(kb_in, 0), (kr, 0)], None);
                    let vc = b.push("l.cache", Op::SliceUpdate { start: vec![0, 0, offset as i32, 0], stop: vec![1, bh, total as i32, dd], strides: vec![1, 1, 1, 1] }, &format!("{g}.cache.vw"), &[(vb_in, 0), (vt, 0)], None);
                    // Read view: [.., :total, :] — identity when total fills
                    // the alloc (mirrors attn_update exactly). THE STORED
                    // STATE IS THE VIEW (attn_update returns views and the
                    // imperative slots hold them — the prefill parity gate
                    // caught exactly this): the declared outputs are the
                    // same nodes the sdp reads.
                    let k_alloc = match &cache.layers[li] {
                        LayerCache::Attn { k: Some(kb), .. } => kb.dim(2) as usize,
                        _ => return Err(MlxError(-978)),
                    };
                    let kc_view = if total < k_alloc {
                        b.push("l.cache", Op::Slice { start: vec![0, 0, 0, 0], stop: vec![1, bh, total as i32, dd], strides: vec![1, 1, 1, 1] }, &format!("{g}.cache.kv"), &[(kc, 0)], None)
                    } else {
                        kc
                    };
                    let vc_view = if total < k_alloc {
                        b.push("l.cache", Op::Slice { start: vec![0, 0, 0, 0], stop: vec![1, bh, total as i32, dd], strides: vec![1, 1, 1, 1] }, &format!("{g}.cache.vv"), &[(vc, 0)], None)
                    } else {
                        vc
                    };
                    writes.push(kc_view);
                    writes.push(vc_view);

                    let att = b.push(&g, Op::Sdp { scale, causal: l > 1 }, &format!("{g}.sdp"), &[(qr, 0), (kc_view, 0), (vc_view, 0)], None);
                    let att_t = b.push(&g, Op::Transpose { axes: vec![0, 2, 1, 3] }, &format!("{g}.att_t"), &[(att, 0)], None);
                    let att_r = b.push(&g, Op::Reshape { shape: vec![1, l, n_h * d] }, &format!("{g}.att_r"), &[(att_t, 0)], None);
                    linear(&mut b, &mut pool_weights, &format!("{g}.o"), &attn.o, (att_r, 0))?
                }
                (LayerKind::Conv, _, Some(conv)) => {
                    // Reference ShortConv: BCx = in_proj(x); B,C,x = split;
                    // Bx = B*x; Bx = concat(state, Bx); state = Bx[:, -2:];
                    // y = C * conv1d(Bx); out_proj(y). The state rides as a
                    // plan input (pinned buffer) — or, on the very first
                    // forward, the zeros node the imperative builds is
                    // declared inline; either way the new state is a
                    // declared output (functional, stored back by
                    // forward_plan).
                    let state_in: crate::plan::NodeId = match &cache.layers[li] {
                        LayerCache::Conv(Some(st)) => pin(&mut b, &mut pool_weights, st, &format!("{g}.state_in")),
                        LayerCache::Conv(None) => b.push(
                            &g,
                            Op::Full { value: 0.0, dtype: Dtype::BFloat16, shape: vec![1, state_len, cfg.hidden_size] },
                            &format!("{g}.state_zeros"),
                            &[],
                            None,
                        ),
                        _ => return Err(MlxError(-978)),
                    };
                    let bcx = linear(&mut b, &mut pool_weights, &format!("{g}.in_proj"), &conv.in_proj, (normed, 0))?;
                    let split = b.push(&g, Op::Split { num: 3, axis: -1 }, &format!("{g}.split"), &[(bcx, 0)], None);
                    let bx = b.push(&g, Bin(BinKind::Mul), &format!("{g}.bx"), &[(split, 0), (split, 2)], None);
                    let bx_full = b.push(&g, Op::Concatenate { axis: 1 }, &format!("{g}.state_cat"), &[(state_in, 0), (bx, 0)], None);
                    // New state: the last L_cache-1 rows of the padded Bx —
                    // a declared output.
                    let new_state = b.push(&g, Op::Slice { start: vec![0, l as i32, 0], stop: vec![1, (l + state_len) as i32, cfg.hidden_size as i32], strides: vec![1, 1, 1] }, &format!("{g}.state_next"), &[(bx_full, 0)], None);
                    writes.push(new_state);
                    let cw = pin(&mut b, &mut pool_weights, &conv.conv, &format!("{g}.conv.weight"));
                    let conv_out = b.push(&g, Op::Conv1d { stride: 1, padding: 0, dilation: 1, groups: cfg.hidden_size as i32 }, &format!("{g}.conv"), &[(bx_full, 0), (cw, 0)], None);
                    let y = b.push(&g, Bin(BinKind::Mul), &format!("{g}.gate"), &[(split, 1), (conv_out, 0)], None);
                    linear(&mut b, &mut pool_weights, &format!("{g}.out_proj"), &conv.out_proj, (y, 0))?
                }
                _ => return Err(MlxError(-9711)),
            };
            // FFN — the imperative decomposes Add and RmsNorm separately
            // (NOT the fused residual row); the plan mirrors it exactly.
            let h1 = b.push(&g, Bin(BinKind::Add), &format!("{g}.res1"), &[(h, 0), (r, 0)], None);
            let fn_w = pin(&mut b, &mut pool_weights, &layer.ffn_norm, &format!("{g}.ffn_norm.w"));
            let ff_in_n = b.push("l.norm", Op::RmsNorm { eps: cfg.norm_eps }, &format!("{g}.ffn_norm"), &[(h1, 0), (fn_w, 0)], None);
            let g1 = linear(&mut b, &mut pool_weights, &format!("{g}.w1"), &layer.w1, (ff_in_n, 0))?;
            let g3 = linear(&mut b, &mut pool_weights, &format!("{g}.w3"), &layer.w3, (ff_in_n, 0))?;
            let sig = b.push(&g, Op::Unary { kind: UnaryKind::Sigmoid }, &format!("{g}.sig"), &[(g1, 0)], None);
            let silu = b.push(&g, Bin(BinKind::Mul), &format!("{g}.silu"), &[(g1, 0), (sig, 0)], None);
            let ff = b.push(&g, Bin(BinKind::Mul), &format!("{g}.ff_in"), &[(silu, 0), (g3, 0)], None);
            let g2 = linear(&mut b, &mut pool_weights, &format!("{g}.w2"), &layer.w2, (ff, 0))?;
            h = b.push(&g, Bin(BinKind::Add), &format!("{g}.res2"), &[(h1, 0), (g2, 0)], None);
        }

        let en_w = pin(&mut b, &mut pool_weights, &self.embedding_norm, "l.embedding_norm.w");
        let t = b.push("l.norm", Op::RmsNorm { eps: cfg.norm_eps }, "l.embedding_norm", &[(h, 0), (en_w, 0)], None);
        // The tail output: logits when the head is wanted (decode), the
        // final-norm hidden otherwise (head-only prefill chunks — R5).
        let tail = if with_head {
            match &self.embed {
                Weight::Quant(q) => {
                    let wn = pin(&mut b, &mut pool_weights, &q.w, "l.lm_head.q8");
                    let sn = pin(&mut b, &mut pool_weights, &q.scales, "l.lm_head.q8_scales");
                    let bn = pin(&mut b, &mut pool_weights, &q.biases, "l.lm_head.q8_biases");
                    b.push("l.linear", Op::QuantizedMatmul { group_size: cfg.group_size, bits: cfg.bits, transpose: true }, "l.lm_head", &[(t, 0), (wn, 0), (sn, 0), (bn, 0)], None)
                }
                Weight::Plain(w) => {
                    let wn = pin(&mut b, &mut pool_weights, w, "l.lm_head.w");
                    let wt = b.push("l.linear", Op::Transpose { axes: vec![1, 0] }, "l.lm_head.w_t", &[(wn, 0)], None);
                    b.push("l.linear", Op::Matmul, "l.lm_head", &[(t, 0), (wt, 0)], None)
                }
            }
        } else {
            t
        };
        let mut outputs = writes;
        outputs.push(tail);
        Ok(ForwardPlan {
            plan: crate::plan::Plan {
                nodes: b.nodes,
                logits: tail,
                act: tail,
                ctx: b.ctx,
                outputs,
            },
            pool_weights,
        })
    }

    /// Greedy decode mirroring mlx_lm's generate_step shape (2048-token
    /// prefill chunks, last token through the decode loop). The conv
    /// window rides the cache; attention layers share the global offset.
    ///
    /// `stop` is the opt-in EOS stop (ADR 0055): when `Some(ids)`, the loop
    /// breaks right after emitting a token in `ids` (the eos token itself is
    /// kept — HF convention). None (every default call site: parity tests,
    /// benches) never stops, so the fixture's pinned stream — which runs
    /// THROUGH `<|im_end|>`/`<|endoftext|>` — stays byte-identical.
    pub fn generate_greedy(
        &self,
        prompt_ids: &[i32],
        max_tokens: usize,
        stop: Option<&[i32]>,
        s: Stream,
    ) -> MlxResult<Vec<i32>> {
        if prompt_ids.is_empty() {
            return Err(MlxError(-9713));
        }
        let mut cache = Lfm2Cache::new(&self.cfg.layer_types);
        // Whole-window reservation (the qwen spike lesson, ADR 0055):
        // attention layers grow once here, not mid-decode. Conv states are
        // fixed-size (L_cache-1 rows) and never grow.
        cache.reserve(&self.table, self.cfg.kv_heads, self.cfg.head_dim, prompt_ids.len() + max_tokens, s)?;
        let mut out: Vec<i32> = Vec::with_capacity(prompt_ids.len() + max_tokens);
        out.extend_from_slice(prompt_ids);

        const PREFILL_STEP: usize = 2048;
        let mut rest = prompt_ids;
        while rest.len() > 1 {
            let n = PREFILL_STEP.min(rest.len() - 1);
            let t = Array::from_data_i32(&rest[..n], &[1, n])?;
            self.forward_hidden(&t, &mut cache, s)?;
            rest = &rest[n..];
        }

        let mut next: i32 = rest[0];
        for _ in 0..max_tokens {
            let tokens = Array::from_data_i32(&[next], &[1, 1])?;
            let logits = self.forward_step(&tokens, &mut cache, s)?;
            let am = logits.argmax_axis(-1, false, s)?;
            let f = am.astype(Dtype::Float32, s)?;
            let v = f.to_f32_vec(s)?;
            let t = v.first().copied().ok_or(MlxError(-9712))? as i32;
            next = t;
            out.push(t);
            if stop.is_some_and(|ids| ids.contains(&t)) {
                break;
            }
        }
        Ok(out)
    }
}

