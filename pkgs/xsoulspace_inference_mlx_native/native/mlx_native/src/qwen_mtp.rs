//! Native Rust MTP (multi-token prediction) speculative-decode path — the
//! DeepSeek-V3/V4 shape.
//!
//! WHAT THIS IS. The draft is NOT a separate small model: it is a chain of
//! cheap HEADS that read the TRUNK's hidden state and the trunk's own last
//! token, and propose the token(s) further ahead. The trunk then verifies the
//! whole proposal in ONE batched forward over the proposed positions.
//!
//! THE HEAD. The shape is fixed by the Python reference
//! (`tool/nursery/mtp_retarget.py`, `head_forward`) and this port mirrors it
//! op for op:
//!
//! ```text
//! x = concat([prev_hidden, token_emb], axis=-1)   # [..., H] + [..., H]
//! x = x @ proj.T                                  # proj [H, 2H] -> [..., H]
//! x = rms_norm(x, norm, eps)                      # norm [H]
//! g = x @ gate.T                                  # gate [F, H]  -> [..., F]
//! u = x @ up.T                                    # up   [F, H]  -> [..., F]
//! d = (g * sigmoid(g) * u) @ down.T               # down [H, F]  -> [..., H]
//! out = x + d
//! ```
//!
//! The head output is then projected to the vocabulary with the trunk's TIED
//! lm_head (the embedding weight applied as linear — the reference's
//! `model.model.embed_tokens.as_linear`) and argmax gives the proposed token.
//!
//! THE CHAIN ("MTP count" K). Head 0 reads the TRUNK's hidden state and the
//! embedding of the trunk's last token; head j>0 reads head j-1's output
//! hidden and the embedding of head j-1's proposed token.
//!
//! THE ALIGNMENT (the subtle part, and the reference's own). The head does
//! NOT read the hidden at the last committed position: it reads the hidden at
//! the SECOND-to-last committed position — the hidden that PREDICTED the last
//! committed token — together with that token's embedding. In the
//! reference's greedy records, the head at index `i` is fed `hs[i]` (the
//! hidden at position `P+i-1`) and `emb(toks[i])` (the token at position
//! `P+i`, which is exactly `argmax(hs[i])`), and it is scored against
//! `toks[i+1]`. So the head proposes the slot AFTER the last committed token
//! while seeing the hidden from one position earlier — the DeepSeek MTP
//! shape, and strictly less information than the trunk has. The decode in
//! this module reproduces that pairing exactly; `MTP_DEBUG=1` traces it.
//!
//! THE EMBEDDING WORKAROUND (documented, deliberate). `Qwen3.embed` and
//! `Qwen3::embed()` are PRIVATE to `qwen.rs`, and `qwen.rs` is outside this
//! change's write scope. The head needs two things from the trunk's embedding
//! matrix — the token rows (the head's `token_emb` input) and the tied vocab
//! projection (the head's own lm_head) — so [`TiedEmbedding`] loads
//! `model.embed_tokens` DIRECTLY from the model's own safetensors file and
//! reproduces the trunk's two embed paths (quantized row-gather + dequantize,
//! or plain row-gather; and the tied `as_linear` projection). The arithmetic
//! is the same ops in the same order as the trunk's own, so the head's
//! projection is the same projection the trunk would have run.
//!
//! THE SCALE. The Python reference has no scale in `head_forward`. This port
//! carries one (`MtpHead::scale`, default 1.0) that multiplies the residual
//! delta `d`, i.e. `out = x + scale * d`. With `scale = 1.0` the port is
//! bit-for-bit the reference; a different scale is an explicit, visible
//! deviation (never a silent one).
//!
//! COSTS (measured on this machine, and the reason this path is delicate):
//! the trunk's vocab projection alone costs ~8.9 ms on bf16 and ~6.3 ms on
//! 4-bit. A draft head that must produce a TOKEN pays that projection — once
//! per head, because the chain is sequential (head j needs head j-1's argmax
//! to pick head j's input token). The head's own lm_head is therefore part of
//! the cycle cost, and [`MtpStats`] reports it separately.

use std::path::Path;
use std::time::{Duration, Instant};

use crate::mlx::{Array, Dtype, MlxError, MlxResult, Stream};
use crate::nursery::sha256_hex;
use crate::qwen::{KvCache, Qwen3};
use crate::safetensors::SafetensorsFile;

/// The RMS-norm epsilon the reference head uses (`mx.fast.rms_norm(x, w, 1e-5)`).
pub const MTP_RMS_EPS: f32 = 1e-5;

/// The decode's step trace (`MTP_DEBUG=1`): the committed token, the head's
/// first proposal and the trunk's own next token, per round. The trace is
/// how the alignment is checked against the python reference.
fn mtp_debug() -> bool {
    use std::sync::OnceLock;
    static ON: OnceLock<bool> = OnceLock::new();
    *ON.get_or_init(|| std::env::var_os("MTP_DEBUG").is_some_and(|v| !v.is_empty()))
}

/// The tensor-name prefix the Python exporter writes
/// (`model.mtp.d{j}.{proj,norm,gate,up,down}.weight`).
pub const MTP_TENSOR_PREFIX: &str = "model.mtp.d";

/// One MTP draft head: the five weights plus the residual scale.
///
/// * `proj` `[H, 2H]` — concat(prev_hidden, token_emb) -> H
/// * `norm` `[H]` — the RMS-norm weight
/// * `gate` `[F, H]`, `up` `[F, H]` — the SwiGLU projections
/// * `down` `[H, F]` — the SwiGLU down-projection
pub struct MtpHead {
    pub proj: Array,
    pub norm: Array,
    pub gate: Array,
    pub up: Array,
    pub down: Array,
    /// Multiplier on the residual delta `d` (`out = x + scale * d`).
    /// `1.0` reproduces the Python reference exactly.
    pub scale: f32,
    /// The chain depth this head was loaded for (0 = the first head).
    pub depth: usize,
    /// The sha256 of the file the weights came from — the cache key the
    /// adapter-digest law will need (a head is a different model when its
    /// weights change, so any cached prefix computed under other weights is
    /// stale).
    pub digest: String,
}

impl MtpHead {
    /// Load the depth-0 head from a safetensors file written by the Python
    /// exporter (`model.mtp.d0.{proj,norm,gate,up,down}.weight`).
    pub fn load(path: &Path, scale: f32, s: Stream) -> Result<Self, String> {
        Self::load_depth(path, 0, scale, s)
    }

    /// Load the head at chain `depth` from a safetensors file.
    pub fn load_depth(path: &Path, depth: usize, scale: f32, s: Stream) -> Result<Self, String> {
        let bytes = std::fs::read(path).map_err(|e| format!("read mtp head: {e}"))?;
        let digest = sha256_hex(&bytes);
        let file = SafetensorsFile::open(path).map_err(|e| format!("open mtp head: {}", e.0))?;
        let take = |part: &str| -> Result<Array, String> {
            let name = format!("{MTP_TENSOR_PREFIX}{depth}.{part}.weight");
            let arr = file
                .take_any(&name)
                .map_err(|e| format!("mtp head tensor {name}: {}", e.0))?;
            let arr = arr
                .astype(Dtype::Float32, s)
                .map_err(|e| format!("mtp head tensor {name}: {}", e.0))?;
            arr.eval()
                .map_err(|e| format!("mtp head tensor {name}: {}", e.0))?;
            Ok(arr)
        };
        let head = MtpHead {
            proj: take("proj")?,
            norm: take("norm")?,
            gate: take("gate")?,
            up: take("up")?,
            down: take("down")?,
            scale,
            depth,
            digest,
        };
        head.check_shapes()?;
        Ok(head)
    }

    /// The head's hidden width `H`.
    pub fn hidden_size(&self) -> usize {
        self.proj.dim(0) as usize
    }

    /// The head's MLP width `F`.
    pub fn mlp_width(&self) -> usize {
        self.gate.dim(0) as usize
    }

    fn check_shapes(&self) -> Result<(), String> {
        let h = self.hidden_size();
        let f = self.mlp_width();
        let ok = self.proj.ndim() == 2
            && self.proj.dim(0) as usize == h
            && self.proj.dim(1) as usize == 2 * h
            && self.norm.ndim() == 1
            && self.norm.dim(0) as usize == h
            && self.gate.ndim() == 2
            && self.gate.dim(0) as usize == f
            && self.gate.dim(1) as usize == h
            && self.up.ndim() == 2
            && self.up.dim(0) as usize == f
            && self.up.dim(1) as usize == h
            && self.down.ndim() == 2
            && self.down.dim(0) as usize == h
            && self.down.dim(1) as usize == f;
        if !ok {
            return Err(format!(
                "mtp head d{}: shape contract broken (proj {:?}, norm {:?}, gate {:?}, up {:?}, down {:?})",
                self.depth,
                shape_of(&self.proj),
                shape_of(&self.norm),
                shape_of(&self.gate),
                shape_of(&self.up),
                shape_of(&self.down),
            ));
        }
        Ok(())
    }

    /// The head forward — the reference's `head_forward`, op for op.
    ///
    /// `prev_hidden` `[..., H]` is the trunk's hidden (depth 0) or the
    /// previous head's output (depth > 0); `token_emb` `[..., H]` is the
    /// embedding of the token the depth conditions on.
    pub fn forward(&self, prev_hidden: &Array, token_emb: &Array, s: Stream) -> MlxResult<Array> {
        // Both inputs are cast to float32 first. The reference always feeds a
        // float32 hidden (its records store the trunk's hidden as float32)
        // and float32 token embeddings; the trunk's own hidden is bfloat16 on
        // a bf16/4-bit checkpoint, and bfloat16 -> float32 is exact, so the
        // cast is the same arithmetic the reference's concatenation
        // promotion does — stated here rather than left to the promotion's
        // discretion.
        let prev_hidden = prev_hidden.astype(Dtype::Float32, s)?;
        let token_emb = token_emb.astype(Dtype::Float32, s)?;
        // x = concat([prev_hidden, token_emb], axis=-1)
        let x = Array::concatenate_axis(&[&prev_hidden, &token_emb], -1, s)?;
        // x = x @ proj.T
        let proj_t = self.proj.transpose_axes(&[1, 0], s)?;
        let x = x.matmul(&proj_t, s)?;
        // x = rms_norm(x, norm, eps)
        let x = Array::rms_norm(&x, &self.norm, MTP_RMS_EPS, s)?;
        // g = x @ gate.T ; u = x @ up.T
        let gate_t = self.gate.transpose_axes(&[1, 0], s)?;
        let up_t = self.up.transpose_axes(&[1, 0], s)?;
        let g = x.matmul(&gate_t, s)?;
        let u = x.matmul(&up_t, s)?;
        // d = (g * sigmoid(g) * u) @ down.T
        let sig = g.sigmoid(s)?;
        let gs = g.mul(&sig, s)?;
        let d = gs.mul(&u, s)?;
        let down_t = self.down.transpose_axes(&[1, 0], s)?;
        let d = d.matmul(&down_t, s)?;
        // out = x + scale * d
        let d = if self.scale == 1.0 {
            d
        } else {
            d.mul(&Array::scalar_f32(self.scale), s)?
        };
        x.add(&d, s)
    }
}

fn shape_of(a: &Array) -> Vec<usize> {
    (0..a.ndim()).map(|d| a.dim(d as i32) as usize).collect()
}

/// The chain of `K` draft heads (the "MTP count").
pub struct MtpChain {
    pub heads: Vec<MtpHead>,
    /// The sha256 of the file the chain came from.
    pub digest: String,
    pub scale: f32,
}

impl MtpChain {
    /// Load every head present in a safetensors file (depths
    /// `model.mtp.d0.*`, `model.mtp.d1.*`, ... in order).
    pub fn load(path: &Path, scale: f32, s: Stream) -> Result<Self, String> {
        let file = SafetensorsFile::open(path).map_err(|e| format!("open mtp head: {}", e.0))?;
        let mut depths: Vec<usize> = Vec::new();
        for name in file.names() {
            let Some(rest) = name.strip_prefix(MTP_TENSOR_PREFIX) else {
                continue;
            };
            let Some((depth, _)) = rest.split_once('.') else {
                continue;
            };
            if let Ok(d) = depth.parse::<usize>() {
                if !depths.contains(&d) {
                    depths.push(d);
                }
            }
        }
        if depths.is_empty() {
            return Err(format!(
                "no {MTP_TENSOR_PREFIX}{{j}}.*.weight tensors in {}",
                path.display()
            ));
        }
        depths.sort_unstable();
        let mut heads = Vec::with_capacity(depths.len());
        for d in &depths {
            heads.push(MtpHead::load_depth(path, *d, scale, s)?);
        }
        let digest = heads.first().map(|h| h.digest.clone()).unwrap_or_default();
        let chain = MtpChain {
            heads,
            digest,
            scale,
        };
        let h = chain.heads[0].hidden_size();
        if chain.heads.iter().any(|x| x.hidden_size() != h) {
            return Err("mtp chain: heads disagree on the hidden width".to_string());
        }
        Ok(chain)
    }

    /// The MTP count `K` (the number of chained heads).
    pub fn len(&self) -> usize {
        self.heads.len()
    }

    pub fn is_empty(&self) -> bool {
        self.heads.is_empty()
    }

    /// The first `k` heads as their own chain (the "MTP count" arm of the
    /// bench: the same weights, a shorter chain).
    pub fn sub(&self, k: usize, s: Stream) -> MlxResult<MtpChain> {
        if k == 0 || k > self.heads.len() {
            return Err(MlxError(-978));
        }
        let heads = self.heads[..k]
            .iter()
            .map(|h| {
                Ok(MtpHead {
                    proj: h.proj.identity(s)?,
                    norm: h.norm.identity(s)?,
                    gate: h.gate.identity(s)?,
                    up: h.up.identity(s)?,
                    down: h.down.identity(s)?,
                    scale: h.scale,
                    depth: h.depth,
                    digest: h.digest.clone(),
                })
            })
            .collect::<MlxResult<Vec<MtpHead>>>()?;
        Ok(MtpChain {
            heads,
            digest: self.digest.clone(),
            scale: self.scale,
        })
    }
}

/// The trunk's tied embedding matrix — the head's token rows AND the tied
/// vocab projection (the reference's `model.model.embed_tokens.as_linear`).
///
/// Loaded from the model's own safetensors because `Qwen3.embed` is private
/// to `qwen.rs` (see the module comment).
pub struct TiedEmbedding {
    kind: EmbedKind,
    pub vocab: usize,
    pub hidden: usize,
    group_size: i32,
    bits: i32,
    /// The dtype the projection runs in (the scales' dtype for a quantized
    /// checkpoint, the weight's dtype otherwise).
    compute_dtype: Dtype,
}

enum EmbedKind {
    /// Affine-quantized (the mlx-community 4-bit exports): packed U32 rows
    /// plus per-group scales/biases.
    Quant {
        w: Array,
        scales: Array,
        biases: Array,
    },
    /// A plain checkpoint tensor (bf16 / f32).
    Plain(Array),
}

impl TiedEmbedding {
    /// Load the tied embedding from a model directory (`config.json` +
    /// `model.safetensors`).
    pub fn load(model_dir: &Path, s: Stream) -> MlxResult<TiedEmbedding> {
        let cfg_raw: serde_json::Value = serde_json::from_str(
            &std::fs::read_to_string(model_dir.join("config.json")).map_err(|_| MlxError(-12))?,
        )
        .map_err(|_| MlxError(-12))?;
        let (group_size, bits) = match &cfg_raw["quantization"] {
            serde_json::Value::Null => (0, 0),
            q => (
                q["group_size"].as_i64().unwrap_or(0) as i32,
                q["bits"].as_i64().unwrap_or(0) as i32,
            ),
        };
        let file = model_dir.join("model.safetensors");
        if !file.is_file() {
            // Sharded checkpoints are not supported here: the tied embedding
            // must live in one file for the head's rows and projection.
            return Err(MlxError(-12));
        }
        Self::load_file(&file, group_size, bits, s)
    }

    /// Load the tied embedding from an explicit safetensors file (the
    /// synthetic parity fixture uses this: a plain f32 `model.embed_tokens`).
    ///
    /// The stream is accepted for symmetry with the other loaders; the
    /// safetensors reader hands over eager host buffers, so no stream op runs
    /// here.
    pub fn load_file(
        path: &Path,
        group_size: i32,
        bits: i32,
        _s: Stream,
    ) -> MlxResult<TiedEmbedding> {
        let st = SafetensorsFile::open(path)?;
        if st.dtype_of("model.embed_tokens.scales").is_some() {
            let q = st.take_quantized("model.embed_tokens")?;
            let vocab = q.w.dim(0) as usize;
            let hidden = q.w.dim(1) as usize * 32 / (bits.max(1) as usize);
            let compute_dtype = q.scales.dtype();
            Ok(TiedEmbedding {
                kind: EmbedKind::Quant {
                    w: q.w,
                    scales: q.scales,
                    biases: q.biases,
                },
                vocab,
                hidden,
                group_size,
                bits,
                compute_dtype,
            })
        } else {
            let w = st.take_any("model.embed_tokens.weight")?;
            let vocab = w.dim(0) as usize;
            let hidden = w.dim(1) as usize;
            let compute_dtype = w.dtype();
            Ok(TiedEmbedding {
                kind: EmbedKind::Plain(w),
                vocab,
                hidden,
                group_size,
                bits,
                compute_dtype,
            })
        }
    }

    /// The embedding rows of `ids` → `[n, H]` float32 (the reference's
    /// `emb_w[ids].astype(mx.float32)`).
    pub fn embedding_rows(&self, ids: &[i32], s: Stream) -> MlxResult<Array> {
        if ids.is_empty() {
            return Err(MlxError(-978));
        }
        for id in ids {
            if *id < 0 || *id as usize >= self.vocab {
                return Err(MlxError(-978));
            }
        }
        let rows = match &self.kind {
            EmbedKind::Quant { w, scales, biases } => {
                let packed_row = w.dim(1) as usize;
                let scale_row = scales.dim(1) as usize;
                let wq = gather_rows(w, ids, packed_row, s)?;
                let ws = gather_rows(scales, ids, scale_row, s)?;
                let wb = gather_rows(biases, ids, scale_row, s)?;
                Array::dequantize(&wq, &ws, &wb, self.group_size, self.bits, s)?
            }
            EmbedKind::Plain(w) => gather_rows(w, ids, self.hidden, s)?,
        };
        // The reference casts the embedding to float32 before the head reads it.
        rows.astype(Dtype::Float32, s)
    }

    /// The tied lm_head: `hidden [..., H]` → logits `[..., V]`.
    ///
    /// This is the same projection the trunk's own lm_head runs (the
    /// reference's `as_linear`), so the head's proposed token is drawn from
    /// the same distribution the trunk would use.
    pub fn as_linear(&self, hidden: &Array, s: Stream) -> MlxResult<Array> {
        let h = hidden.astype(self.compute_dtype, s)?;
        match &self.kind {
            EmbedKind::Quant { w, scales, biases } => {
                Array::quantized_matmul(&h, w, scales, biases, true, self.group_size, self.bits, s)
            }
            EmbedKind::Plain(w) => {
                let wt = w.transpose_axes(&[1, 0], s)?;
                h.matmul(&wt, s)
            }
        }
    }
}

/// Row gather from `[rows, cols]` by `ids` → `[n, cols]` (the trunk's
/// `gather_rows` shape, re-implemented here because `qwen.rs`'s copy is
/// private).
fn gather_rows(table: &Array, ids: &[i32], cols: usize, s: Stream) -> MlxResult<Array> {
    let count: usize = (0..table.ndim())
        .map(|d| table.dim(d as i32) as usize)
        .product();
    let flat = table.reshape(&[count], s)?;
    let ids_arr = Array::from_data_i32(ids, &[1, ids.len()])?;
    let ids_col = ids_arr.reshape(&[1, ids.len(), 1], s)?;
    let scaled = ids_col.mul(&Array::scalar_i32(cols as i32), s)?;
    let col_idx = Array::arange_i32(0, cols as i32, s)?;
    let flat_idx = scaled.add(&col_idx, s)?;
    flat.take(&flat_idx, s)
}

/// The counters and the COST BREAKDOWN of one MTP decode run.
///
/// `head_lm_us` is the part the old lane's cost model omitted entirely: the
/// draft head's OWN vocab projection (one per head, because the chain is
/// sequential). It is reported separately so no reader can mistake the draft
/// for a nearly-free MLP.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct MtpStats {
    /// Propose+verify rounds executed.
    pub rounds: usize,
    /// Tokens the head chain proposed (`K` per round).
    pub drafted: usize,
    /// Verified-prefix tokens the trunk kept (the accepted prefix).
    pub accepted: usize,
    /// Tokens emitted (the accepted prefix; a round that accepts nothing
    /// still emits the trunk's own token).
    pub emitted: usize,
    /// Time in the head chain's MLP (the five weights).
    pub head_mlp_us: u64,
    /// Time in the head chain's OWN vocab projection (the draft's lm_head).
    pub head_lm_us: u64,
    /// Time in the trunk's batched verify forward (K positions + the tied
    /// projection over them).
    pub verify_us: u64,
    /// Time in the resync forward (the rare round that accepted nothing: the
    /// trunk's hidden at the new committed position has to be recomputed,
    /// because the verify's position there consumed the REJECTED draft).
    pub resync_us: u64,
    /// How many resync forwards ran (one per round that accepted nothing).
    pub resyncs: usize,
    /// `prefix_hist[j]` = the number of rounds whose ACCEPTED PREFIX reached
    /// depth `j+1` (i.e. the head at depth `j` was accepted). The reference's
    /// `accept_self[j]` is `prefix_hist[j] / rounds` — the J-G1 metric.
    pub prefix_hist: Vec<usize>,
    /// The decode-only clock (prefill excluded).
    pub decode: Duration,
}

impl MtpStats {
    /// The acceptance rate at one depth: P(the head at depth `j` proposed the
    /// trunk's own next token) — the reference's `accept_self[j]` and the
    /// J-G1 metric.
    pub fn depth_acceptance(&self, depth: usize) -> f64 {
        if self.rounds == 0 {
            0.0
        } else {
            self.prefix_hist.get(depth).copied().unwrap_or(0) as f64 / self.rounds as f64
        }
    }

    /// The mean accepted prefix length per drafted token (a summary number;
    /// the per-depth acceptance above is the gate's metric).
    pub fn acceptance(&self) -> f64 {
        if self.drafted == 0 {
            0.0
        } else {
            self.accepted as f64 / self.drafted as f64
        }
    }
}

/// The MTP decode: greedy, verified by the trunk, token-exact against the
/// trunk's plain greedy.
///
/// THE ALIGNMENT (the DeepSeek-V3 MTP shape, and the reference's). The head
/// does NOT read the trunk's hidden at the last committed position: it reads
/// the hidden at the SECOND-to-last committed position — the hidden that
/// PREDICTED the last committed token — together with that token's
/// embedding. In the reference's own greedy records (`mtp_retarget.py`), the
/// head at index `i` is fed `hs[i]` (the hidden at position `P+i-1`) and
/// `emb(toks[i])` (the token at position `P+i`, which is exactly
/// `argmax(hs[i])`), and it is scored against `toks[i+1]`. So the head's
/// proposal for the slot after the last committed token competes with the
/// trunk's prediction from the LATER hidden — the head has strictly less
/// information than the trunk, which is the whole point of the measurement.
///
/// THE ROUND. With the committed prefix ending at position `q` (the last
/// committed token `ctx_token`, the trunk's hidden there `ctx_hidden`, and
/// the head's input hidden `head_hidden` = the hidden at `q-1`):
///
/// 1. the head chain: `d_0 = argmax(as_linear(head_0(head_hidden, emb(ctx_token))))`,
///    `d_1 = argmax(as_linear(head_1(h_0, emb(d_0))))`, ... `K` proposals and
///    `K` vocab projections (the chain is sequential: head j needs head j-1's
///    argmax to pick its input token);
/// 2. ONE batched trunk forward over the `K` proposed positions, then the
///    tied projection over its hidden states;
/// 3. the accepted prefix: `d_0` is accepted iff it equals the trunk's own
///    next token (`t_prev`), `d_j` (j>0) iff it equals the trunk's prediction
///    at the previous verified position;
/// 4. the accepted prefix is committed. The next round's head input hidden is
///    the trunk's hidden at the new second-to-last committed position — which
///    the verify forward produced, so no extra trunk forward is needed.
///
/// The trunk's free "bonus" token (the prediction at the last verified
/// position) is NOT committed: committing it would move the committed
/// position one past the verify forward's last hidden state, and the head
/// needs the hidden AT the second-to-last committed position. The cost of that
/// choice is recorded here rather than hidden: the MTP lane trades the bonus
/// token for a single batched trunk forward per round.
///
/// THE `a == 0` CASE. When the head's first proposal is rejected, the round
/// still has to make progress, so the trunk's own token `t_prev` is committed
/// — but the verify forward's position there consumed the REJECTED draft, so
/// the trunk's hidden at the new committed position is recomputed with one
/// extra hidden-only forward (`resync_us`).
pub fn generate_greedy_mtp(
    trunk: &Qwen3,
    embed: &TiedEmbedding,
    chain: &MtpChain,
    prompt_ids: &[i32],
    max_tokens: usize,
    s: Stream,
) -> MlxResult<(Vec<i32>, MtpStats)> {
    if prompt_ids.is_empty() || chain.is_empty() {
        return Err(MlxError(-978));
    }
    // The head reads the hidden at the second-to-last committed position, so
    // a one-token prompt has no such hidden.
    if prompt_ids.len() < 2 {
        return Err(MlxError(-978));
    }
    let k = chain.len();
    let mut stats = MtpStats::default();
    stats.prefix_hist = vec![0usize; k];

    let mut cache = KvCache::new(trunk.cfg.layers);
    let total = prompt_ids.len() + max_tokens + k + 4;
    cache.reserve(
        trunk.table(),
        trunk.cfg.kv_heads,
        trunk.cfg.head_dim,
        total,
        s,
    )?;

    // Prefill prompt[..len-1] (KV only) — the same chunking the plain greedy
    // uses, so the context the trunk sees is the plain greedy's context. The
    // LAST prefill position's hidden is the head's first input hidden.
    const PREFILL_STEP: usize = 2048;
    let mut rest = &prompt_ids[..];
    let mut prefill: Option<(Array, usize)> = None;
    while rest.len() > 1 {
        let n = PREFILL_STEP.min(rest.len() - 1);
        let t = Array::from_data_i32(&rest[..n], &[1, n])?;
        let h = trunk.forward_hidden(&t, &mut cache, s)?;
        prefill = Some((h, n));
        rest = &rest[n..];
    }
    let seed = rest[0];

    // The decode clock starts AFTER the prefill, at the same place the plain
    // greedy's decode clock starts (its first decode step is the seed).
    let decode_clock = Instant::now();

    let mut out: Vec<i32> = Vec::with_capacity(prompt_ids.len() + max_tokens);
    out.extend_from_slice(prompt_ids);

    // The head's input hidden: the hidden at the second-to-last committed
    // position (the last prefill position).
    let (ph, ph_len) = prefill.ok_or(MlxError(-978))?;
    let mut head_hidden = slice_position(&ph, (ph_len - 1) as i32, s)?;
    // The trunk's hidden at the last committed position, and the trunk's own
    // next token there.
    let seed_arr = Array::from_data_i32(&[seed], &[1, 1])?;
    let mut ctx_hidden = trunk.forward_hidden(&seed_arr, &mut cache, s)?;
    let seed_logits = embed.as_linear(&ctx_hidden, s)?;
    let mut t_prev = argmax_tokens(&seed_logits, s)?
        .first()
        .copied()
        .ok_or(MlxError(-978))?;
    let mut ctx_token = seed;
    // The committed prefix length (the prompt plus whatever the rounds add).
    let mut ctx_len = prompt_ids.len();

    while out.len() - prompt_ids.len() < max_tokens {
        stats.rounds += 1;
        stats.drafted += k;

        // ---- 1. the head chain ----
        let mut drafts: Vec<i32> = Vec::with_capacity(k);
        let mut prev_hidden = head_hidden.identity(s)?;
        let mut prev_token = ctx_token;
        for head in chain.heads.iter() {
            let t_head = Instant::now();
            let emb = embed.embedding_rows(&[prev_token], s)?;
            emb.eval()?;
            let h = head.forward(&prev_hidden, &emb, s)?;
            h.eval()?;
            stats.head_mlp_us += t_head.elapsed().as_micros() as u64;
            if mtp_debug() && stats.rounds <= 3 && head.depth == 0 {
                let hv = h.to_f32_vec(s).unwrap_or_default();
                let pv = prev_hidden
                    .astype(Dtype::Float32, s)
                    .ok()
                    .and_then(|a| a.to_f32_vec(s).ok())
                    .unwrap_or_default();
                let ev = emb.to_f32_vec(s).unwrap_or_default();
                eprintln!(
                    "MTP-DEBUG head0: in_hidden[0..4] {:?} emb[0..4] {:?} out[0..6] {:?}",
                    &pv[..pv.len().min(4)],
                    &ev[..ev.len().min(4)],
                    &hv[..hv.len().min(6)],
                );
            }

            let t_lm = Instant::now();
            let logits = embed.as_linear(&h, s)?;
            let token = argmax_tokens(&logits, s)?
                .first()
                .copied()
                .ok_or(MlxError(-978))?;
            stats.head_lm_us += t_lm.elapsed().as_micros() as u64;

            drafts.push(token);
            prev_hidden = h;
            prev_token = token;
        }

        // ---- 2. the batched verify ----
        let t_verify = Instant::now();
        let dt = Array::from_data_i32(&drafts, &[1, k])?;
        let hidden = trunk.forward_hidden(&dt, &mut cache, s)?;
        let logits = embed.as_linear(&hidden, s)?;
        let trunk_tokens = argmax_tokens(&logits, s)?;
        if trunk_tokens.len() < k {
            return Err(MlxError(-978));
        }
        stats.verify_us += t_verify.elapsed().as_micros() as u64;

        // ---- 3. the accepted prefix ----
        // d_0 competes with the trunk's own next token at the committed
        // position; d_j (j>0) with the trunk's prediction at the previous
        // verified position.
        let mut accepted = 0usize;
        if drafts[0] == t_prev {
            accepted = 1;
            while accepted < k && drafts[accepted] == trunk_tokens[accepted - 1] {
                accepted += 1;
            }
        }
        stats.accepted += accepted;
        for j in 0..accepted {
            if let Some(cell) = stats.prefix_hist.get_mut(j) {
                *cell += 1;
            }
        }
        if mtp_debug() && stats.rounds <= 8 {
            let hv = head_hidden.to_f32_vec(s).unwrap_or_default();
            let ev = embed
                .embedding_rows(&[ctx_token], s)
                .ok()
                .and_then(|a| a.to_f32_vec(s).ok())
                .unwrap_or_default();
            eprintln!(
                "MTP-DEBUG round {}: ctx_len {} committed_token {} head_input_hidden_pos {} \
                 draft0 {} trunk_next {} accepted {} | hidden[0..4] {:?} emb[0..4] {:?}",
                stats.rounds,
                ctx_len,
                ctx_token,
                ctx_len - 2,
                drafts[0],
                t_prev,
                accepted,
                &hv[..hv.len().min(4)],
                &ev[..ev.len().min(4)],
            );
        }

        let room = max_tokens - (out.len() - prompt_ids.len());
        if accepted > 0 {
            let committed = accepted.min(room);
            for &tok in drafts.iter().take(committed) {
                out.push(tok);
            }
            let old_ctx_hidden = ctx_hidden.identity(s)?;
            ctx_len += committed;
            // The new last committed position's hidden is the verify's hidden
            // at the accepted-prefix end (index committed-1); the head's next
            // input hidden is the one before it (index committed-2), or the
            // old last committed hidden when only one token was committed.
            ctx_hidden = slice_position(&hidden, (committed - 1) as i32, s)?;
            head_hidden = if committed >= 2 {
                slice_position(&hidden, (committed - 2) as i32, s)?
            } else {
                old_ctx_hidden
            };
            ctx_token = drafts[committed - 1];
            t_prev = trunk_tokens[committed - 1];
            // Rewind the KV to the committed prefix's end: the rejected
            // drafts' rows (positions ctx_len_old..) are stale and the next
            // forward overwrites them.
            cache.offset = ctx_len;
        } else {
            // Nothing accepted: the trunk's own token is committed and the
            // trunk's hidden at the new position is recomputed (the verify's
            // position there consumed the rejected draft).
            let committed = room.min(1);
            for _ in 0..committed {
                out.push(t_prev);
            }
            // The head's next input hidden is the hidden at the new
            // second-to-last committed position — which is the OLD last
            // committed hidden (the trunk's own token took the new last
            // position).
            let old_ctx_hidden = ctx_hidden.identity(s)?;
            // Rewind the KV to BEFORE the trunk's own token's position: the
            // verify wrote the rejected draft there, so the resync forward
            // rewrites it.
            cache.offset = ctx_len;
            ctx_len += committed;
            ctx_token = t_prev;
            let t_resync = Instant::now();
            let arr = Array::from_data_i32(&[t_prev], &[1, 1])?;
            ctx_hidden = trunk.forward_hidden(&arr, &mut cache, s)?;
            head_hidden = old_ctx_hidden;
            let lg = embed.as_linear(&ctx_hidden, s)?;
            t_prev = argmax_tokens(&lg, s)?
                .first()
                .copied()
                .ok_or(MlxError(-978))?;
            stats.resync_us += t_resync.elapsed().as_micros() as u64;
            stats.resyncs += 1;
            if committed == 0 {
                break;
            }
        }
        stats.emitted = out.len() - prompt_ids.len();
        if out.len() - prompt_ids.len() >= max_tokens {
            break;
        }
    }

    stats.emitted = out.len() - prompt_ids.len();
    stats.decode = decode_clock.elapsed();
    Ok((out, stats))
}

/// `[1, L, H]` -> the position `idx` as `[1, 1, H]`.
fn slice_position(hidden: &Array, idx: i32, s: Stream) -> MlxResult<Array> {
    hidden.slice(
        &[0, idx, 0],
        &[1, idx + 1, hidden.dim(2) as i32],
        &[1, 1, 1],
        s,
    )
}

/// The argmax over the last axis → one token id per position.
fn argmax_tokens(logits: &Array, s: Stream) -> MlxResult<Vec<i32>> {
    let am = logits.argmax_axis(-1, false, s)?;
    let f = am.astype(Dtype::Float32, s)?;
    let v = f.to_f32_vec(s)?;
    Ok(v.iter().map(|x| *x as i32).collect())
}
