//! Qwen3.5 (model_type `qwen3_5`) TEXT TOWER — load + greedy generate.
//!
//! House pattern: the Python-first reference (tool/nursery/wm_qwen35_*.py,
//! sibling actor) is the semantics source of record; this file is the RUST
//! half, kept separate from qwen.rs (which stays the Qwen3-dense engine) so
//! the two implementations can be compared and benchmarked side by side.
//! The durable parity contract is
//! `pkgs/xsoulspace_inference_mlx_native/testdata/qwen35_parity_digests.json`
//! (fixture provenance: mlx 0.32.4 / mlx-lm 0.32.2 / py 3.12.13, GPU).
//!
//! # Semantics source (cited)
//!
//! Primary: mlx-lm `mlx_lm/models/qwen3_5.py` (+ its imports `qwen3_next.py`
//! for Attention/MLP/RMSNormGated, `gated_delta.py` for the recurrence,
//! `activations.py` for swiglu/precise_swiglu, `base.py` for the mask/sdpa
//! helpers, `rope_utils.py` for initialize_rope), ml-explore/mlx-lm main @
//! 56230fa02b8ff8330daf26dc95c28480423ed5fe (2026-11-05). The installed
//! mlx-lm 0.32.0/0.32.2 line is byte-identical for single-rank execution
//! (the only diff vs main is distributed-sharding code).
//!
//! Cross-check: HF transformers `models/qwen3_5/modeling_qwen3_5.py` (main,
//! fetched 2026-11-05) — confirms the two quirks this loader replicates:
//!   * `Qwen3_5RMSNorm` is PLUS-ONE: `output * (1.0 + weight)` for
//!     input/post_attention/final/q/k norms — mlx-lm's `sanitize` folds the
//!     +1 into the weight at load (gated ONLY on HF-format conv1d, i.e.
//!     `shape[-1] != 1`; replicated below).
//!   * `Qwen3_5RMSNormGated` (linear_attn.norm) is norm-BEFORE-gate with
//!     the RAW weight (no +1): `silu(z) * rms_norm(out, w)` in f32 → bf16
//!     (mlx-lm `precise_swiglu`).
//!
//! # Bitwise-parity strategy
//!
//! Every op routes through the same mlx-c kernel the python reference
//! dispatches (matmul, conv1d, fast rms_norm, fast rope, fast sdpa with the
//! `"causal"` string prefill mask, sigmoid/logaddexp/logsumexp), in the same
//! dtype at every step — including mlx's weak-scalar semantics (empirically
//! pinned on this machine 2026-11-05: python `scalar * bf16_array` is
//! bitwise `bf16(scalar) * bf16_array`, and `rms_norm(x, None, eps)` is
//! bitwise `rms_norm(x, ones_bf16, eps)`).
//!
//! The gated-delta recurrence runs the VERBATIM mlx-lm packed Metal kernel
//! (`kernels/gated_delta_packed.metal`, same source text, same
//! `metal_kernel` JIT via mlx-c) because the reference GPU path runs it and
//! its mul+add sites compile with Metal's default FMA contraction — an
//! ops-composed replica of the same reduction tree was measured to diverge
//! from the kernel in 40% of state elements at T=2 ($TMPDIR probe
//! qwen35_probe/fma_probe.py, 2026-11-05: fma=False state diff
//! 105007/262144, fma=True state diff 0/262144). The unpacked/xtree
//! comparator kernels are bitwise-identical to the packed one for these
//! shapes (measured 0 diffs), so a MLX_GDN_PACKED=0 reference matches too.
//!
//! # Scope / documented readings (open questions)
//!
//! 1. TEXT TOWER ONLY: `model.language_model.*` weights; `model.visual.*`
//!    and `mtp.*` tensors stay unread in the store and never break loading
//!    (mlx-lm sanitize drops both). The MTP head is not part of greedy
//!    single-token generation.
//! 2. mrope: config declares `mrope_interleaved` + `mrope_section [11,11,10]`,
//!    but for text-only generation all three position planes are equal, so
//!    interleaved-mrope reduces exactly to standard 1-D NeoX rope over the
//!    first `head_dim * partial_rotary_factor` = 64 dims — which is what
//!    mlx-lm's Attention runs (`initialize_rope` → plain `nn.RoPE` for
//!    rope_type "default"). Reading of record: plain rope; multimodal
//!    position ids are out of scope.
//! 3. Single sequence, batch 1, no padding: ssm_mask is None (no
//!    left-padding bookkeeping), the full-attention prefill mask is the
//!    kernel-native "causal" path, decode runs maskless. Batched/padded
//!    inputs are REFUSED, not silently mis-masked.
//! 4. `tie_word_embeddings: true` is required (the checkpoint ships no
//!    lm_head tensor; an untied config is refused rather than guessed).
//! 5. The GDN packed kernel is python-eligible for every shape this model
//!    produces (mask None, Dk=128, Dv%8==0, g/state f32), so the Rust side
//!    runs it for both prefill and decode with no ops fallback.
//! 6. The 0.8B checkpoint's single shard is named
//!    `model.safetensors-00001-of-00001.safetensors` and is reachable only
//!    through `model.safetensors.index.json` — see
//!    `crate::safetensors::WeightStore` (single-file stores behave exactly
//!    as before; the index is read only when `model.safetensors` is absent).

use std::path::{Path, PathBuf};

use crate::mlx::{
    Array, Dtype, MetalKernel, MlxError, MlxResult, Stream, TemplateArg, TemplateValue,
};
use crate::safetensors::WeightStore;

/// One decoder layer's kind, from `text_config.layer_types`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LayerKind {
    LinearAttention,
    FullAttention,
}

/// Parsed `config.json` (the `text_config` sub-object; a flat text-only
/// config.json is accepted too, mirroring mlx-lm's `ModelArgs.from_dict`).
#[derive(Clone)]
pub struct Qwen35Config {
    pub hidden_size: usize,
    pub layers: usize,
    pub heads: usize,
    pub kv_heads: usize,
    pub head_dim: usize,
    pub intermediate: usize,
    pub vocab: usize,
    pub rms_eps: f32,
    pub rope_theta: f32,
    pub rotary_dims: usize,
    pub layer_types: Vec<LayerKind>,
    pub tied: bool,
    pub lin_k_heads: usize,
    pub lin_v_heads: usize,
    pub lin_k_dim: usize,
    pub lin_v_dim: usize,
    pub conv_kernel: usize,
}

impl Qwen35Config {
    fn parse(doc: &serde_json::Value) -> Result<Qwen35Config, String> {
        let model_type = doc.get("model_type").and_then(|v| v.as_str()).unwrap_or("");
        let text = match doc.get("text_config") {
            Some(t) => t,
            None => doc,
        };
        let text_type = text.get("model_type").and_then(|v| v.as_str()).unwrap_or("");
        if model_type != "qwen3_5" && text_type != "qwen3_5_text" && text_type != "qwen3_5" {
            return Err(format!(
                "QWEN35_CONFIG_MODEL_TYPE_UNSUPPORTED: model_type={model_type:?} \
                 text model_type={text_type:?} (this engine implements qwen3_5)"
            ));
        }
        let get_u = |k: &str| -> Result<usize, String> {
            text.get(k)
                .and_then(|v| v.as_u64())
                .ok_or_else(|| format!("QWEN35_CONFIG_MISSING_FIELD: {k}"))
                .map(|v| v as usize)
        };
        let get_f = |k: &str| -> Result<f64, String> {
            text.get(k)
                .and_then(|v| v.as_f64())
                .ok_or_else(|| format!("QWEN35_CONFIG_MISSING_FIELD: {k}"))
        };
        let hidden = get_u("hidden_size")?;
        let heads = get_u("num_attention_heads")?;
        let head_dim = text
            .get("head_dim")
            .and_then(|v| v.as_u64())
            .map(|v| v as usize)
            .unwrap_or(hidden / heads);
        let rope = text.get("rope_parameters").or_else(|| text.get("rope_scaling"));
        let rope_theta = match rope.and_then(|r| r.get("rope_theta")).and_then(|v| v.as_f64()) {
            Some(t) => t,
            None => get_f("rope_theta")?,
        };
        let partial = rope
            .and_then(|r| r.get("partial_rotary_factor"))
            .and_then(|v| v.as_f64())
            .unwrap_or(0.25);
        let layer_types_raw = text
            .get("layer_types")
            .and_then(|v| v.as_array())
            .ok_or("QWEN35_CONFIG_MISSING_FIELD: layer_types")?;
        let mut layer_types = Vec::with_capacity(layer_types_raw.len());
        for lt in layer_types_raw {
            match lt.as_str() {
                Some("linear_attention") => layer_types.push(LayerKind::LinearAttention),
                Some("full_attention") => layer_types.push(LayerKind::FullAttention),
                Some(other) => {
                    return Err(format!("QWEN35_CONFIG_UNSUPPORTED_LAYER_TYPE: {other}"))
                }
                None => return Err("QWEN35_CONFIG_BAD_LAYER_TYPE".to_string()),
            }
        }
        let tied = text
            .get("tie_word_embeddings")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        Ok(Qwen35Config {
            hidden_size: hidden,
            layers: get_u("num_hidden_layers")?,
            heads,
            kv_heads: get_u("num_key_value_heads")?,
            head_dim,
            intermediate: get_u("intermediate_size")?,
            vocab: get_u("vocab_size")?,
            rms_eps: get_f("rms_norm_eps")? as f32,
            rope_theta: rope_theta as f32,
            rotary_dims: (head_dim as f64 * partial) as usize,
            layer_types,
            tied,
            lin_k_heads: get_u("linear_num_key_heads")?,
            lin_v_heads: get_u("linear_num_value_heads")?,
            lin_k_dim: get_u("linear_key_head_dim")?,
            lin_v_dim: get_u("linear_value_head_dim")?,
            conv_kernel: get_u("linear_conv_kernel_dim")?,
        })
    }

    /// Shape invariants this engine's kernel/dispatch choices rely on
    /// (refuse loudly instead of computing something else).
    fn validate(&self) -> Result<(), String> {
        if self.layer_types.len() != self.layers {
            return Err(format!(
                "QWEN35_CONFIG_LAYER_COUNT_MISMATCH: layer_types {} vs num_hidden_layers {}",
                self.layer_types.len(),
                self.layers
            ));
        }
        if !self.tied {
            return Err(
                "QWEN35_UNTIED_EMBEDDINGS_UNSUPPORTED: this checkpoint declares \
                 tie_word_embeddings=false; the loader implements the tied head only"
                    .to_string(),
            );
        }
        if self.lin_k_dim != 128 || self.lin_v_dim % 8 != 0 {
            return Err(format!(
                "QWEN35_GDN_SHAPE_UNSUPPORTED: packed kernel needs Dk==128 and Dv%8==0, got \
                 Dk={} Dv={}",
                self.lin_k_dim, self.lin_v_dim
            ));
        }
        if self.lin_v_heads % self.lin_k_heads != 0 {
            return Err("QWEN35_GDN_HEAD_REPEAT_UNSUPPORTED: Hv must divide by Hk".to_string());
        }
        if self.rotary_dims % 2 != 0 || self.rotary_dims > self.head_dim {
            return Err(format!(
                "QWEN35_ROPE_DIMS_INVALID: rotary {} head_dim {}",
                self.rotary_dims, self.head_dim
            ));
        }
        Ok(())
    }
}

struct MlpW {
    /// Transposed views ([in, out]) of the checkpoint weights — the same
    /// strided operand `nn.Linear`'s `x @ w.T` hands the matmul kernel.
    gate_t: Array,
    up_t: Array,
    down_t: Array,
}

struct LinearAttnW {
    qkv_t: Array,
    z_t: Array,
    b_t: Array,
    a_t: Array,
    /// [conv_dim, kernel, 1] — the checkpoint's [conv_dim, 1, kernel] with
    /// axes swapped (mlx-lm sanitize's `moveaxis(2, 1)`).
    conv_w: Array,
    dt_bias: Array,
    /// f32 [Hv] — the checkpoint stores A_log in f32 and mlx-lm's
    /// cast_predicate keeps it there.
    a_log: Array,
    /// RAW f32 [Dv] gated-norm weight (never +1-offset).
    gated_norm_w: Array,
    out_t: Array,
}

struct FullAttnW {
    q_t: Array,
    k_t: Array,
    v_t: Array,
    o_t: Array,
    /// +1.0 folded in at load (HF `Qwen3_5RMSNorm` is plus-one).
    q_norm: Array,
    k_norm: Array,
}

enum LayerW {
    Linear {
        ln1: Array,
        ln2: Array,
        mlp: MlpW,
        attn: LinearAttnW,
    },
    Full {
        ln1: Array,
        ln2: Array,
        mlp: MlpW,
        attn: FullAttnW,
    },
}

impl LayerW {
    fn ln1(&self) -> &Array {
        match self {
            LayerW::Linear { ln1, .. } | LayerW::Full { ln1, .. } => ln1,
        }
    }
    fn ln2(&self) -> &Array {
        match self {
            LayerW::Linear { ln2, .. } | LayerW::Full { ln2, .. } => ln2,
        }
    }
    fn mlp(&self) -> &MlpW {
        match self {
            LayerW::Linear { mlp, .. } | LayerW::Full { mlp, .. } => mlp,
        }
    }
}

/// Per-linear-layer recurrent cache (mlx-lm `ArraysCache(size=2)`):
/// slot 0 = depthwise-conv carry [1, K-1, conv_dim] bf16, slot 1 = the
/// gated-delta state [1, Hv, Dv, Dk] f32.
struct GdnState {
    conv: Array,
    rec: Array,
}

struct KvSlot {
    k: Option<Array>,
    v: Option<Array>,
}

/// The hybrid cache: KV buffers for the full-attention layers (growth
/// policy byte-for-byte the mlx-lm `KVCache` one — zero-padded blocks of
/// 256, slice-assignment writes, sliced reads — replicated with direct
/// array ops; qwen.rs's KvCache keeps its private update contract), plus
/// the conv/recurrent states for the linear layers. `offset` is the shared
/// position cursor (rope offset + KV write index), bumped once per forward.
pub struct Qwen35Cache {
    kv: Vec<KvSlot>,
    kv_slot_of_layer: Vec<Option<usize>>,
    gdn: Vec<Option<GdnState>>,
    pub offset: usize,
}

const KV_STEP: usize = 256;

impl Qwen35Cache {
    pub fn new(cfg: &Qwen35Config) -> Qwen35Cache {
        let mut kv = Vec::new();
        let mut kv_slot_of_layer = Vec::with_capacity(cfg.layers);
        let mut gdn = Vec::with_capacity(cfg.layers);
        for kind in &cfg.layer_types {
            match kind {
                LayerKind::FullAttention => {
                    kv_slot_of_layer.push(Some(kv.len()));
                    kv.push(KvSlot { k: None, v: None });
                    gdn.push(None);
                }
                LayerKind::LinearAttention => {
                    kv_slot_of_layer.push(None);
                    gdn.push(None);
                }
            }
        }
        Qwen35Cache {
            kv,
            kv_slot_of_layer,
            gdn,
            offset: 0,
        }
    }

    /// Pre-grow every full-attention KV buffer to hold `total` tokens
    /// (allocation only — padding is never read, numerics untouched).
    pub fn reserve(
        &mut self,
        batch: usize,
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
        for slot in self.kv.iter_mut() {
            Self::ensure_capacity(&mut slot.k, prev, n, (batch, kv_heads, head_dim), s)?;
            Self::ensure_capacity(&mut slot.v, prev, n, (batch, kv_heads, head_dim), s)?;
        }
        Ok(())
    }

    fn ensure_capacity(
        buf: &mut Option<Array>,
        prev: usize,
        n: usize,
        bhd: (usize, usize, usize),
        s: Stream,
    ) -> MlxResult<()> {
        let needed = prev + n;
        if let Some(bf) = buf {
            if needed <= bf.dim(2) as usize {
                return Ok(());
            }
        }
        let block = (needed - prev).div_ceil(KV_STEP) * KV_STEP;
        let (b, h, d) = bhd;
        let zeros = Array::full(0.0, &[b, h, block, d], Dtype::BFloat16, s)?;
        let grown = match buf.take() {
            None => zeros,
            Some(bf) => {
                let alloc = bf.dim(2) as usize;
                let trimmed = if prev % KV_STEP != 0 && prev < alloc {
                    bf.slice(
                        &[0, 0, 0, 0],
                        &[b as i32, h as i32, prev as i32, d as i32],
                        &[1, 1, 1, 1],
                        s,
                    )?
                } else {
                    bf
                };
                Array::concatenate_axis(&[&trimmed, &zeros], 2, s)?
            }
        };
        *buf = Some(grown);
        Ok(())
    }

    /// Write `new` rows at `offset` and return the read view down to the
    /// total written length (the qwen.rs update_one/keys_and_values policy).
    fn kv_update(
        buf: &mut Option<Array>,
        new: &Array,
        prev: usize,
        s: Stream,
    ) -> MlxResult<Array> {
        let b = new.dim(0) as usize;
        let h = new.dim(1) as usize;
        let n = new.dim(2) as usize;
        let d = new.dim(3) as usize;
        Self::ensure_capacity(buf, prev, n, (b, h, d), s)?;
        let bf = buf.as_ref().ok_or(MlxError(-978))?;
        let out = Array::slice_update(
            bf,
            new,
            &[0, 0, prev as i32, 0],
            &[b as i32, h as i32, (prev + n) as i32, d as i32],
            &[1, 1, 1, 1],
            s,
        )?;
        *buf = Some(out);
        let bf = buf.as_ref().unwrap();
        let total = prev + n;
        let alloc = bf.dim(2) as usize;
        if total < alloc {
            bf.slice(
                &[0, 0, 0, 0],
                &[b as i32, h as i32, total as i32, d as i32],
                &[1, 1, 1, 1],
                s,
            )
        } else {
            bf.identity(s)
        }
    }
}

/// The mlx-lm packed gated-delta kernel (verbatim source; see
/// kernels/gated_delta_packed.metal for the citation and the FMA rationale).
const GATED_DELTA_PACKED_MSL: &str = include_str!("kernels/gated_delta_packed.metal");

fn gated_delta_kernel() -> Option<&'static MetalKernel> {
    use std::sync::OnceLock;
    static KERNEL: OnceLock<Option<MetalKernel>> = OnceLock::new();
    KERNEL
        .get_or_init(|| {
            MetalKernel::new(
                "gated_delta_step_packed_btree",
                &["q", "k", "v", "g", "beta", "state_in", "T"],
                &["y", "state_out"],
                GATED_DELTA_PACKED_MSL,
            )
            .map(Some)
            .unwrap_or_else(|e| {
                eprintln!("qwen3_5: gated-delta kernel init failed: {e:?}");
                None
            })
        })
        .as_ref()
}

/// The mx.compile'd `nn.softplus` replica (verbatim LogAddExp functor in
/// the node dtype — see kernels/softplus_compiled.metal for why the eager
/// logaddexp route is bitwise-different and how this was pinned: 9474/9474
/// on the exhaustive bf16 grid vs the compiled reference).
const SOFTPLUS_COMPILED_MSL: &str = include_str!("kernels/softplus_compiled.metal");

fn softplus_kernel() -> Option<&'static MetalKernel> {
    use std::sync::OnceLock;
    static KERNEL: OnceLock<Option<MetalKernel>> = OnceLock::new();
    KERNEL
        .get_or_init(|| {
            MetalKernel::new(
                "laya_softplus_compiled",
                &["x", "shape"],
                &["out"],
                SOFTPLUS_COMPILED_MSL,
            )
            .map(Some)
            .unwrap_or_else(|e| {
                eprintln!("qwen3_5: softplus kernel init failed: {e:?}");
                None
            })
        })
        .as_ref()
}

pub struct Qwen35 {
    pub cfg: Qwen35Config,
    embed: Array,
    /// Transposed embedding view — the tied lm_head (`as_linear`).
    embed_t: Array,
    layers: Vec<LayerW>,
    norm: Array,
    // normalize_qk constants (see the module header for the pinning):
    /// bf16 ones [lin_k_dim] — bitwise-identical stand-in for
    /// `rms_norm(x, None, eps)`.
    ones_dk: Array,
    /// bf16 scalar `(Dk**-0.5)**2` (q readout scale, folded per reference).
    s_q: Array,
    /// bf16 scalar `Dk**-0.5` (the l2norm scale on k).
    s_k: Array,
    /// `eps * inv_scale**2` — normalize_qk's rms epsilon, f32.
    qk_norm_eps: f32,
    zero_f32: Array,
    attn_scale: f32,
}

impl Qwen35 {
    /// Loads config.json + the (possibly sharded) safetensors store from an
    /// HF snapshot directory. Weight names are the HF checkpoint names
    /// (`model.language_model.*`); `model.visual.*` / `mtp.*` tensors are
    /// left unread.
    pub fn load(dir: &Path) -> Result<Qwen35, String> {
        let raw = std::fs::read_to_string(dir.join("config.json"))
            .map_err(|e| format!("QWEN35_CONFIG_IO: {e}"))?;
        let doc: serde_json::Value =
            serde_json::from_str(&raw).map_err(|e| format!("QWEN35_CONFIG_PARSE: {e}"))?;
        let cfg = Qwen35Config::parse(&doc)?;
        cfg.validate()?;
        let s = crate::mlx::gpu().map_err(|e| format!("QWEN35_GPU_UNAVAILABLE: {e:?}"))?;
        Self::load_with_stream(dir, &cfg, s)
    }

    /// [`Self::load`] on an explicit stream (tests/benches that already
    /// pinned the metallib and opened the GPU stream).
    pub fn load_with_stream(dir: &Path, cfg: &Qwen35Config, s: Stream) -> Result<Qwen35, String> {
        let store = WeightStore::open_dir(dir).map_err(|e| format!("QWEN35_STORE_IO: {e:?}"))?;
        let err = |what: String| move |e: MlxError| format!("QWEN35_WEIGHT_{what}: {e:?}");

        // mlx-lm sanitize's conv1d-format gate for the plus-one norm fold:
        // `has_unsanitized_conv1d = any(conv1d.weight with shape[-1] != 1)`
        // — an HF-format checkpoint stores raw plus-one norm weights and
        // gets the +1.0 fold; a pre-sanitized mlx export (conv last dim 1)
        // must NOT be offset again. Every linear layer's conv weight is
        // pre-read once (kept for the main loop, no double load) so the
        // ANY-gate matches the reference exactly, mixed layouts included.
        let mut convs: Vec<Option<Array>> = (0..cfg.layers).map(|_| None).collect();
        let mut hf_format = false;
        for (li, kind) in cfg.layer_types.iter().enumerate() {
            if *kind != LayerKind::LinearAttention {
                continue;
            }
            let c = store
                .take_any(&format!(
                    "model.language_model.layers.{li}.linear_attn.conv1d.weight"
                ))
                .map_err(|e| format!("QWEN35_WEIGHT_CONV1D_L{li}: {e:?}"))?;
            if c.ndim() == 3 && c.dim(2) as usize != 1 {
                hf_format = true;
            }
            convs[li] = Some(c);
        }

        let take = |name: &str| -> Result<Array, String> {
            store.take_any(name).map_err(err(name.to_string()))
        };
        let plus_one = |w: Array| -> Result<Array, String> {
            if !hf_format {
                return Ok(w);
            }
            let one = Array::full(1.0, &[1], Dtype::BFloat16, s).map_err(err("ONE".into()))?;
            w.add(&one, s).map_err(err("PLUS_ONE".into()))
        };
        let transpose = |w: Array| -> Result<Array, String> {
            w.transpose_axes(&[1, 0], s).map_err(err("TRANSPOSE".into()))
        };
        let lm = "model.language_model";

        let mut layers = Vec::with_capacity(cfg.layers);
        for (li, kind) in cfg.layer_types.iter().enumerate() {
            let p = format!("{lm}.layers.{li}");
            let ln1 = plus_one(take(&format!("{p}.input_layernorm.weight"))?)?;
            let ln2 = plus_one(take(&format!("{p}.post_attention_layernorm.weight"))?)?;
            let mlp = MlpW {
                gate_t: transpose(take(&format!("{p}.mlp.gate_proj.weight"))?)?,
                up_t: transpose(take(&format!("{p}.mlp.up_proj.weight"))?)?,
                down_t: transpose(take(&format!("{p}.mlp.down_proj.weight"))?)?,
            };
            match kind {
                LayerKind::LinearAttention => {
                    let conv_src = convs[li]
                        .take()
                        .ok_or_else(|| format!("QWEN35_WEIGHT_CONV1D_L{li}: not pre-read"))?;
                    let conv_w = if hf_format {
                        // [C, 1, K] -> [C, K, 1] (sanitize's moveaxis(2,1)).
                        conv_src
                            .transpose_axes(&[0, 2, 1], s)
                            .map_err(err("CONV1D_TRANSPOSE".into()))?
                    } else {
                        conv_src
                    };
                    layers.push(LayerW::Linear {
                        ln1,
                        ln2,
                        mlp,
                        attn: LinearAttnW {
                            qkv_t: transpose(take(&format!("{p}.linear_attn.in_proj_qkv.weight"))?)?,
                            z_t: transpose(take(&format!("{p}.linear_attn.in_proj_z.weight"))?)?,
                            b_t: transpose(take(&format!("{p}.linear_attn.in_proj_b.weight"))?)?,
                            a_t: transpose(take(&format!("{p}.linear_attn.in_proj_a.weight"))?)?,
                            conv_w,
                            dt_bias: take(&format!("{p}.linear_attn.dt_bias"))?,
                            a_log: take(&format!("{p}.linear_attn.A_log"))?,
                            gated_norm_w: take(&format!("{p}.linear_attn.norm.weight"))?,
                            out_t: transpose(take(&format!("{p}.linear_attn.out_proj.weight"))?)?,
                        },
                    });
                }
                LayerKind::FullAttention => {
                    layers.push(LayerW::Full {
                        ln1,
                        ln2,
                        mlp,
                        attn: FullAttnW {
                            q_t: transpose(take(&format!("{p}.self_attn.q_proj.weight"))?)?,
                            k_t: transpose(take(&format!("{p}.self_attn.k_proj.weight"))?)?,
                            v_t: transpose(take(&format!("{p}.self_attn.v_proj.weight"))?)?,
                            o_t: transpose(take(&format!("{p}.self_attn.o_proj.weight"))?)?,
                            q_norm: plus_one(take(&format!("{p}.self_attn.q_norm.weight"))?)?,
                            k_norm: plus_one(take(&format!("{p}.self_attn.k_norm.weight"))?)?,
                        },
                    });
                }
            }
        }

        let embed = take(&format!("{lm}.embed_tokens.weight"))?;
        let embed_t = embed
            .transpose_axes(&[1, 0], s)
            .map_err(err("EMBED_TRANSPOSE".into()))?;
        let norm = plus_one(take(&format!("{lm}.norm.weight"))?)?;

        // normalize_qk constants — computed in f64 exactly like the python
        // reference (`inv_scale = head_k_dim**-0.5; rms_eps = eps *
        // inv_scale**2`), then rounded to bf16 for the scalar multiplies
        // (the pinned weak-scalar semantics).
        let inv_scale = (cfg.lin_k_dim as f64).powf(-0.5);
        let qk_norm_eps = (cfg.rms_eps as f64) * (inv_scale * inv_scale);
        let ones_dk = Array::full(1.0, &[cfg.lin_k_dim], Dtype::BFloat16, s)
            .map_err(err("ONES_DK".into()))?;
        let s_q = Array::full(inv_scale * inv_scale, &[1], Dtype::BFloat16, s)
            .map_err(err("S_Q".into()))?;
        let s_k = Array::full(inv_scale, &[1], Dtype::BFloat16, s).map_err(err("S_K".into()))?;
        let zero_f32 =
            Array::full(0.0, &[1], Dtype::Float32, s).map_err(err("ZERO_F32".into()))?;

        Ok(Qwen35 {
            cfg: cfg.clone(),
            embed,
            embed_t,
            layers,
            norm,
            ones_dk,
            s_q,
            s_k,
            qk_norm_eps: qk_norm_eps as f32,
            zero_f32,
            attn_scale: (cfg.head_dim as f32).powf(-0.5),
        })
    }

    // ---- forward ----

    /// Env-gated shape trace (QWEN35_SHAPE_DEBUG=1) — the diagnostic idiom
    /// of LAYA_QWEN_PLAN_DEBUG; the golden path pays one cached bool read
    /// (the qwen_profiling OnceLock pattern), never an env scan.
    fn shape_dbg(tag: &str, a: &Array) {
        use std::sync::OnceLock;
        static ON: OnceLock<bool> = OnceLock::new();
        if *ON.get_or_init(|| std::env::var_os("QWEN35_SHAPE_DEBUG").is_some()) {
            let dims: Vec<usize> = (0..a.ndim()).map(|d| a.dim(d as i32)).collect();
            eprintln!("qwen3_5 {tag}: {dims:?} {:?}", a.dtype());
        }
    }

    /// Env-gated per-stage digest (QWEN35_LAYER_DIGESTS=1): sha256 of the
    /// exact f32 widening bytes + the last four values — the cross-version
    /// bisection tool (located the vendored-MLX-0.32.2-vs-fixture-0.32.4
    /// prefill drift; pairs with the python-side per-layer digest probe).
    /// Diagnostic only; forces eval when enabled.
    fn digest_dbg(tag: &str, a: &Array, s: Stream) {
        use std::sync::OnceLock;
        static ON: OnceLock<bool> = OnceLock::new();
        if !*ON.get_or_init(|| std::env::var_os("QWEN35_LAYER_DIGESTS").is_some()) {
            return;
        }
        match a.astype(Dtype::Float32, s).and_then(|f| f.to_f32_vec(s)) {
            Ok(f) => {
                let bytes: Vec<u8> = f.iter().flat_map(|x| x.to_le_bytes()).collect();
                let tail: Vec<f32> = f[f.len().saturating_sub(4)..].to_vec();
                eprintln!(
                    "qwen3_5 digest {tag}: {} last4 {tail:?}",
                    crate::nursery::sha256_hex(&bytes)
                );
            }
            Err(e) => eprintln!("qwen3_5 digest {tag}: readback failed {e:?}"),
        }
    }

    /// One forward over `tokens` [1, L] i32. `with_head` runs the tied
    /// lm_head and returns logits [1, L, V] (bf16); otherwise the final
    /// normed hidden state [1, L, H]. Bumps `cache.offset` by L (the
    /// step owner's contract, same as qwen.rs).
    pub fn forward(
        &self,
        tokens: &Array,
        cache: &mut Qwen35Cache,
        with_head: bool,
        s: Stream,
    ) -> MlxResult<Array> {
        if tokens.dim(0) != 1 {
            // Documented reading 3: single sequence only — a padded batch
            // would need the ssm/keep masks this engine deliberately omits.
            return Err(MlxError(-975));
        }
        let l = tokens.dim(1) as usize;
        // Row gather [V, H] × ids [1, L] → [1, L, H]: the flat-index take
        // idiom of qwen.rs's gather_rows — mlx's no-axis `take` indexes the
        // FLATTENED table, so the row-major index math (id * H + col) is
        // explicit. Pure data movement: the same rows python's
        // `weight[inputs]` gather returns, bitwise.
        let mut h = {
            let hidden = self.cfg.hidden_size;
            let flat = self.embed.reshape(&[self.cfg.vocab * hidden], s)?;
            let ids_col = tokens.reshape(&[1, l, 1], s)?;
            let scaled = ids_col.mul(&Array::scalar_i32(hidden as i32), s)?;
            let col_idx = Array::arange_i32(0, hidden as i32, s)?;
            let flat_idx = scaled.add(&col_idx, s)?;
            flat.take(&flat_idx, s)? // [1, L, H] bf16
        };
        Self::shape_dbg("embed", &h);
        Self::digest_dbg("embed", &h, s);

        for (li, layer) in self.layers.iter().enumerate() {
            let ln1 = Array::rms_norm(&h, layer.ln1(), self.cfg.rms_eps, s)?;
            let r = match layer {
                LayerW::Linear { attn, .. } => self.gated_delta_net(attn, &ln1, li, cache, l, s)?,
                LayerW::Full { attn, .. } => self.attention(attn, &ln1, cache, li, l, s)?,
            };
            Self::shape_dbg(&format!("l{li:02}.r"), &r);
            Self::digest_dbg(&format!("l{li:02}.r"), &r, s);
            let h1 = h.add(&r, s)?;
            Self::digest_dbg(&format!("l{li:02}.h1"), &h1, s);
            let ln2 = Array::rms_norm(&h1, layer.ln2(), self.cfg.rms_eps, s)?;
            let mlp = layer.mlp();
            let g = ln2.matmul(&mlp.gate_t, s)?;
            let u = ln2.matmul(&mlp.up_t, s)?;
            // swiglu(g, u) = nn.silu(g) * u = (g * sigmoid(g)) * u — the
            // reference composite, op for op, in bf16.
            let act = g.mul(&g.sigmoid(s)?, s)?.mul(&u, s)?;
            Self::digest_dbg(&format!("l{li:02}.act"), &act, s);
            let ff = act.matmul(&mlp.down_t, s)?;
            h = h1.add(&ff, s)?;
            Self::digest_dbg(&format!("l{li:02}"), &h, s);
        }

        cache.offset += l;
        let t = Array::rms_norm(&h, &self.norm, self.cfg.rms_eps, s)?;
        if with_head {
            // Tied head: `embed_tokens.as_linear(t)` = t @ embed.T.
            t.matmul(&self.embed_t, s)
        } else {
            Ok(t)
        }
    }

    /// `Qwen3NextAttention` (qwen3_5 reuses it): gated output, per-head
    /// plus-one QK norms, PARTIAL rope (first `rotary_dims`), GQA sdpa.
    fn attention(
        &self,
        w: &FullAttnW,
        x: &Array,
        cache: &mut Qwen35Cache,
        li: usize,
        l: usize,
        s: Stream,
    ) -> MlxResult<Array> {
        let cfg = &self.cfg;
        let slot = cache.kv_slot_of_layer[li].ok_or(MlxError(-978))?;

        let q = x.matmul(&w.q_t, s)?; // [1, L, heads*head_dim*2]
        let qh = q.reshape(&[1, l, cfg.heads, cfg.head_dim * 2], s)?;
        Self::shape_dbg("attn.qh", &qh);
        let (queries, gate) = qh.split2(-1, s)?; // [1, L, heads, head_dim] each
        let gate = gate.reshape(&[1, l, cfg.heads * cfg.head_dim], s)?;
        let k = x
            .matmul(&w.k_t, s)?
            .reshape(&[1, l, cfg.kv_heads, cfg.head_dim], s)?;
        let v = x
            .matmul(&w.v_t, s)?
            .reshape(&[1, l, cfg.kv_heads, cfg.head_dim], s)?;

        let qn = Array::rms_norm(&queries, &w.q_norm, cfg.rms_eps, s)?;
        let kn = Array::rms_norm(&k, &w.k_norm, cfg.rms_eps, s)?;
        let qt = qn.transpose_axes(&[0, 2, 1, 3], s)?; // [1, H, L, D]
        let kt = kn.transpose_axes(&[0, 2, 1, 3], s)?;
        let vt = v.transpose_axes(&[0, 2, 1, 3], s)?;

        // PARTIAL rope: dims = head_dim * partial_rotary_factor; the kernel
        // rotates the first `dims` and passes the tail through — exactly
        // mlx-lm's initialize_rope(64, base=theta, traditional=False).
        let off = cache.offset as i32;
        let qr = qt.rope(cfg.rotary_dims as i32, cfg.rope_theta, off, s)?;
        let kr = kt.rope(cfg.rotary_dims as i32, cfg.rope_theta, off, s)?;

        let (kc, vc) = {
            let kslot = &mut cache.kv[slot];
            let kview = Qwen35Cache::kv_update(&mut kslot.k, &kr, cache.offset, s)?;
            let vview = Qwen35Cache::kv_update(&mut kslot.v, &vt, cache.offset, s)?;
            (kview, vview)
        };

        // Prefill (L>1): the kernel-native causal path — the `"causal"`
        // mask string mlx-lm's create_attention_mask returns. Decode: no
        // mask (the single query attends everything cached).
        let att = if l > 1 {
            Array::sdp_attention_mode(&qr, &kc, &vc, self.attn_scale, "causal", None, s)?
        } else {
            Array::sdp_attention_mode(&qr, &kc, &vc, self.attn_scale, "", None, s)?
        };
        let att_r = att
            .transpose_axes(&[0, 2, 1, 3], s)?
            .reshape(&[1, l, cfg.heads * cfg.head_dim], s)?;
        let gated = att_r.mul(&gate.sigmoid(s)?, s)?;
        gated.matmul(&w.o_t, s)
    }

    /// `GatedDeltaNet` (qwen3_5.py): split in-projections, depthwise conv
    /// with carry state, l2-normalized q/k, the packed gated-delta kernel,
    /// norm-before-gate f32 RMSNormGated, out projection.
    #[allow(clippy::too_many_arguments)]
    fn gated_delta_net(
        &self,
        w: &LinearAttnW,
        x: &Array,
        li: usize,
        cache: &mut Qwen35Cache,
        l: usize,
        s: Stream,
    ) -> MlxResult<Array> {
        let cfg = &self.cfg;
        let hk = cfg.lin_k_heads;
        let hv = cfg.lin_v_heads;
        let dk = cfg.lin_k_dim;
        let dv = cfg.lin_v_dim;
        let key_dim = hk * dk;
        let conv_dim = key_dim * 2 + hv * dv;
        if hk != hv {
            // The kernel takes Hk/Hv templates and repeats heads when they
            // differ; this checkpoint has Hk == Hv and the repeat path is
            // deliberately not implemented (refuse, never silently differ).
            return Err(MlxError(-975));
        }

        let qkv = x.matmul(&w.qkv_t, s)?; // [1, L, conv_dim]
        let z = x.matmul(&w.z_t, s)?; // [1, L, hv*dv]
        let b = x.matmul(&w.b_t, s)?; // [1, L, hv]
        let a = x.matmul(&w.a_t, s)?;

        // Conv carry state (ArraysCache slot 0); zeros on first use, bf16
        // like the reference (`dtype=inputs.dtype`).
        let conv_state = match &cache.gdn[li] {
            Some(st) => st.conv.identity(s)?,
            None => Array::full(
                0.0,
                &[1, cfg.conv_kernel - 1, conv_dim],
                Dtype::BFloat16,
                s,
            )?,
        };
        let conv_in = Array::concatenate_axis(&[&conv_state, &qkv], 1, s)?; // [1, L+K-1, C]
        let total = l + cfg.conv_kernel - 1;
        let new_conv = conv_in.slice(
            &[0, total as i32 - (cfg.conv_kernel as i32 - 1), 0],
            &[1, total as i32, conv_dim as i32],
            &[1, 1, 1],
            s,
        )?;
        let conv_out = crate::mlx::conv1d(
            &conv_in,
            &w.conv_w,
            1,
            0,
            1,
            conv_dim as i32,
            s,
        )?; // [1, L, C]
        let conv_act = conv_out.mul(&conv_out.sigmoid(s)?, s)?; // nn.silu
        Self::shape_dbg("gdn.conv_act", &conv_act);
        Self::digest_dbg(&format!("l{li:02}.conv_act"), &conv_act, s);

        let q_raw = conv_act.slice(&[0, 0, 0], &[1, l as i32, key_dim as i32], &[1, 1, 1], s)?;
        let k_raw = conv_act.slice(
            &[0, 0, key_dim as i32],
            &[1, l as i32, 2 * key_dim as i32],
            &[1, 1, 1],
            s,
        )?;
        let v_raw = conv_act.slice(
            &[0, 0, 2 * key_dim as i32],
            &[1, l as i32, conv_dim as i32],
            &[1, 1, 1],
            s,
        )?;
        let q3 = q_raw.reshape(&[1, l, hk, dk], s)?;
        let k3 = k_raw.reshape(&[1, l, hk, dk], s)?;
        let v3 = v_raw.reshape(&[1, l, hv, dv], s)?;

        // normalize_qk(q, k, inv_scale=dk**-0.5, eps=1e-6): rms_norm with
        // the scaled epsilon, then the folded scales (see module header for
        // the bitwise pinning of both substitutions).
        let qn = Array::rms_norm(&q3, &self.ones_dk, self.qk_norm_eps, s)?.mul(&self.s_q, s)?;
        let kn = Array::rms_norm(&k3, &self.ones_dk, self.qk_norm_eps, s)?.mul(&self.s_k, s)?;

        // beta = sigmoid(b) (bf16, as the reference); g = exp(-exp(A_log) *
        // softplus(a + dt_bias)) in f32 (compute_g's exact dtype chain:
        // softplus = logaddexp(x, 0) in bf16, promotion at the multiply).
        let dt = a.add(&w.dt_bias, s)?; // [1, L, hv] bf16
        // softplus(dt) with the COMPILED reference semantics (the eager
        // logaddexp diverges at bf16 sub-expression rounding — see
        // kernels/softplus_compiled.metal for the measurement).
        let sp = {
            let n = l * hv;
            let kernel = softplus_kernel().ok_or(MlxError(-974))?;
            // 1-D [1] int array — a 0-d scalar would bind as `const int&`
            // in the generated signature and `shape[0]` would not compile.
            let shape = Array::from_data_i32(&[n as i32], &[1])?;
            let flat = dt.reshape(&[n], s)?;
            let mut outs = kernel
                .apply(
                    &[&flat, &shape],
                    &[&[n]],
                    Dtype::BFloat16,
                    (n as i32, 1, 1),
                    (256, 1, 1),
                    s,
                )?
                .into_iter();
            outs.next()
                .ok_or(MlxError(-978))?
                .reshape(&[1, l, hv], s)?
        };
        let exp_a = w.a_log.exp(s)?; // f32 [hv]
        let g = self.zero_f32.sub(&exp_a.mul(&sp, s)?, s)?.exp(s)?; // f32 [1, L, hv]
        Self::digest_dbg(&format!("l{li:02}.a"), &a, s);
        Self::digest_dbg(&format!("l{li:02}.dt"), &dt, s);
        Self::digest_dbg(&format!("l{li:02}.sp"), &sp, s);
        Self::digest_dbg(&format!("l{li:02}.exp_a"), &exp_a, s);
        Self::digest_dbg(&format!("l{li:02}.g"), &g, s);
        let beta = b.sigmoid(s)?; // bf16 [1, L, hv]
        Self::digest_dbg(&format!("l{li:02}.qn"), &qn, s);
        Self::digest_dbg(&format!("l{li:02}.kn"), &kn, s);
        Self::digest_dbg(&format!("l{li:02}.v"), &v3, s);
        Self::digest_dbg(&format!("l{li:02}.beta"), &beta, s);

        // The recurrence: the verbatim mlx-lm packed kernel (module header
        // for why an ops composition cannot be bitwise-equal).
        let rec_in = match &cache.gdn[li] {
            Some(st) => st.rec.identity(s)?,
            None => Array::full(0.0, &[1, hv, dv, dk], Dtype::Float32, s)?,
        };
        let kernel = gated_delta_kernel().ok_or(MlxError(-974))?;
        let t_arr = Array::scalar_i32(l as i32);
        let y_shape = [1usize, l, hv, dv];
        let state_shape = [1usize, hv, dv, dk];
        let outs = kernel.apply_templated(
            &[&qn, &kn, &v3, &g, &beta, &rec_in, &t_arr],
            &[(&y_shape, Dtype::BFloat16), (&state_shape, Dtype::Float32)],
            &[
                TemplateArg {
                    name: "InT",
                    value: TemplateValue::Dtype(Dtype::BFloat16),
                },
                TemplateArg {
                    name: "StT",
                    value: TemplateValue::Dtype(Dtype::Float32),
                },
                TemplateArg {
                    name: "Dk",
                    value: TemplateValue::Int(dk as i32),
                },
                TemplateArg {
                    name: "Dv",
                    value: TemplateValue::Int(dv as i32),
                },
                TemplateArg {
                    name: "Hk",
                    value: TemplateValue::Int(hk as i32),
                },
                TemplateArg {
                    name: "Hv",
                    value: TemplateValue::Int(hv as i32),
                },
            ],
            (32, dv as i32 / 8, hv as i32),
            (32, 2, 1),
            s,
        )?;
        let mut outs = outs.into_iter();
        let y = outs.next().ok_or(MlxError(-978))?; // [1, L, Hv, Dv] bf16
        Self::shape_dbg("gdn.y", &y);
        Self::digest_dbg(&format!("l{li:02}.gdn_y"), &y, s);
        let rec_out = outs.next().ok_or(MlxError(-978))?; // [1, Hv, Dv, Dk] f32
        cache.gdn[li] = Some(GdnState {
            conv: new_conv,
            rec: rec_out,
        });

        // RMSNormGated (norm BEFORE gate, RAW f32 weight — the reference's
        // Qwen3NextRMSNormGated): x = rms_norm(y, w, eps) in f32, then
        // precise_swiglu: (silu(z.f32()) * x).astype(bf16).
        let normed = Array::rms_norm(&y, &w.gated_norm_w, cfg.rms_eps, s)?; // f32
        let z32 = z
            .reshape(&[1, l, hv, dv], s)?
            .astype(Dtype::Float32, s)?;
        let silu_z = z32.mul(&z32.sigmoid(s)?, s)?; // f32
        let gated = silu_z.mul(&normed, s)?.astype(Dtype::BFloat16, s)?;
        Self::digest_dbg(&format!("l{li:02}.gated"), &gated, s);

        let flat = gated.reshape(&[1, l, hv * dv], s)?;
        Self::shape_dbg("gdn.flat", &flat);
        flat.matmul(&w.out_t, s)
    }
}

// ---- greedy generation (the parity pipeline) ----

impl Qwen35 {
    /// Greedy decode mirroring the fixture's normative pipeline
    /// (testdata/qwen35_parity_digests.json rounding_rule):
    ///   * prefill: chunks of <= `PREFILL_STEP` (2048, mlx-lm
    ///     generate_step's default and the fixture's provenance) over
    ///     `prompt[..len-1]`; the LAST prompt token rides the decode loop;
    ///   * each step: logits = forward([next]); the raw bf16 logits row is
    ///     handed to `on_step` for the first `keep_logits_steps` steps
    ///     (BEFORE any logsumexp, model output dtype — the digest input);
    ///   * token choice: `argmax(logits - logsumexp(logits, keepdims))`
    ///     (mlx-lm's greedy sampler, dedicated LogSumExp primitive);
    ///   * NO EOS stop — the stream runs exactly `max_tokens` steps.
    /// Returns the GENERATED tokens (prompt excluded).
    pub fn generate_greedy(
        &self,
        prompt_ids: &[i32],
        max_tokens: usize,
        keep_logits_steps: usize,
        s: Stream,
        on_step: &mut dyn FnMut(usize, i32, Option<&Array>),
    ) -> MlxResult<Vec<i32>> {
        if prompt_ids.is_empty() {
            return Err(MlxError(-978));
        }
        let mut cache = Qwen35Cache::new(&self.cfg);
        cache.reserve(
            1,
            self.cfg.kv_heads,
            self.cfg.head_dim,
            prompt_ids.len() + max_tokens,
            s,
        )?;

        // The chunk split is PARITY-LOAD-BEARING (the qwen.rs lesson): it
        // decides kernel tiling for the chunk-length ops (conv1d, sdpa,
        // GEMM M-dim). 2048 is mlx-lm generate_step's default and the
        // fixture's provenance; QWEN35_PREFILL_STEP overrides for A/B
        // bisecting a chunk-kernel divergence.
        const PREFILL_STEP_DEFAULT: usize = 2048;
        let prefill_step = std::env::var("QWEN35_PREFILL_STEP")
            .ok()
            .and_then(|v| v.parse::<usize>().ok())
            .filter(|v| *v > 0)
            .unwrap_or(PREFILL_STEP_DEFAULT);
        let mut rest = prompt_ids;
        while rest.len() > 1 {
            let n = prefill_step.min(rest.len() - 1);
            let t = Array::from_data_i32(&rest[..n], &[1, n])?;
            // KV/state-only chunk: no lm_head (a chunk's logits are never
            // read; dead outputs have no numerical effect).
            self.forward(&t, &mut cache, false, s)?;
            rest = &rest[n..];
        }

        let mut next: i32 = rest[0];
        let mut out: Vec<i32> = Vec::with_capacity(max_tokens);
        for step in 0..max_tokens {
            let tokens = Array::from_data_i32(&[next], &[1, 1])?;
            let logits = self.forward(&tokens, &mut cache, true, s)?; // [1,1,V] bf16
            let row = logits.reshape(&[1, self.cfg.vocab], s)?;
            let lse = row.logsumexp_axis(-1, true, s)?; // f32 [1,1]
            let adj = row.sub(&lse, s)?; // f32 [1,V]
            let am = adj.argmax_axis(-1, false, s)?;
            let f = am.astype(Dtype::Float32, s)?;
            let v = f.to_f32_vec(s)?;
            let tok = v.first().copied().ok_or(MlxError(-978))? as i32;
            let keep = step < keep_logits_steps;
            on_step(step, tok, if keep { Some(&row) } else { None });
            out.push(tok);
            next = tok;
        }
        Ok(out)
    }

    /// Convenience for tests/benches: greedy tokens only.
    pub fn generate_greedy_tokens(
        &self,
        prompt_ids: &[i32],
        max_tokens: usize,
        s: Stream,
    ) -> MlxResult<Vec<i32>> {
        self.generate_greedy(prompt_ids, max_tokens, 0, s, &mut |_, _, _| {})
    }
}

// ---- digest helpers (the fixture's normative rounding rule) ----

/// Formats one step's logits row per the fixture rounding rule: values are
/// the exact f32 widening of the bf16 logits, each formatted C fixed-point
/// `{:.6}` (ties-to-even; `-0.0` → `-0.000000`), joined with `','`
/// (no spaces). `per_step_sha256` digests `step_text + "\n"`.
pub fn format_logits_row(row_f32: &[f32]) -> String {
    let mut out = String::with_capacity(row_f32.len() * 10);
    for (i, v) in row_f32.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        // f32 -> f64 is exact; {:.6} is the correctly rounded 6-decimal
        // representation (matches python '%.6f' on the same binary value,
        // per the fixture's rounding_rule).
        out.push_str(&format!("{:.6}", *v as f64));
    }
    out
}

/// SHA-256 lowercase hex of one step text plus its trailing newline.
pub fn per_step_sha256(step_text: &str) -> String {
    let mut buf = step_text.as_bytes().to_vec();
    buf.push(b'\n');
    crate::nursery::sha256_hex(&buf)
}

/// SHA-256 lowercase hex of the step texts joined with '\n' plus ONE
/// trailing '\n' (the fixture's combined-digest input).
pub fn steps_sha256(step_texts: &[String]) -> String {
    let mut buf = Vec::new();
    for (i, t) in step_texts.iter().enumerate() {
        if i > 0 {
            buf.push(b'\n');
        }
        buf.extend_from_slice(t.as_bytes());
    }
    buf.push(b'\n');
    crate::nursery::sha256_hex(&buf)
}

/// Reads a bf16 logits row back as the exact f32 widening (digest input).
pub fn logits_row_f32(row: &Array, s: Stream) -> MlxResult<Vec<f32>> {
    row.astype(Dtype::Float32, s)?.to_f32_vec(s)
}

/// The default Qwen3.5-0.8B snapshot location on this machine (HF hub
/// layout); `QWEN35_SNAPSHOT` overrides everywhere in this lane.
pub fn default_snapshot_dir() -> Option<PathBuf> {
    if let Some(over) = std::env::var_os("QWEN35_SNAPSHOT") {
        let p = PathBuf::from(over);
        return if p.is_dir() { Some(p) } else { None };
    }
    let home = std::env::var_os("HOME")?;
    let main = PathBuf::from(home)
        .join(".cache/huggingface/hub/models--Qwen--Qwen3.5-0.8B/snapshots/main");
    if main.is_dir() {
        return Some(main);
    }
    // Generic hub layout: any snapshot dir with a config.json.
    let hub = PathBuf::from(std::env::var_os("HOME")?)
        .join(".cache/huggingface/hub/models--Qwen--Qwen3.5-0.8B/snapshots");
    for entry in std::fs::read_dir(&hub).ok()?.flatten() {
        if entry.path().is_dir() && entry.path().join("config.json").is_file() {
            return Some(entry.path());
        }
    }
    None
}

