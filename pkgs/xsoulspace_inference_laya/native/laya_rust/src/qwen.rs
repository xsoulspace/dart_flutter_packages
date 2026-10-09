//! Qwen3 dense decoder (ADR 0054 R2): the mlx-lm reference computation
//! op-for-op, dispatched through the binding table like the laya plan walk.
//! Weights are MLX affine-quantized (packed U32 + bf16 scales/biases) read
//! straight from the HF safetensors; `mlx_quantized_matmul` runs the same
//! kernels the python reference calls, so greedy decode parity is a
//! token-for-token comparison, not an approximation.
//!
//! Architecture notes: the decode loop is cache-stateful (the KV cache grows
//! every step), so the node walk is per-op rather than a whole-plan build —
//! but every op still resolves through `bindings::eval`, which makes this
//! the binding-table's second consumer. R3's fused dequant-GEMV lands as a
//! new binding on the `quantized_matmul` keys without touching this file.
//! A declared per-step plan tree is a later increment, not this rung.

use std::path::Path;

use serde::Deserialize;

use crate::bindings::BindingTable;
use crate::mlx::{Array, Dtype, MlxError, MlxResult, Stream};
use crate::plan::{BinKind, Node, Op, UnaryKind};
use crate::safetensors::{QuantizedTensor, SafetensorsFile};

/// Env-gated step profiler (LAYA_QWEN_PROFILE=1): per-section wall time,
/// accumulated across steps, printed by [`qwen_profile_flush`]. Diagnostic
/// only — the golden path never pays for it beyond one env read per step.
#[derive(Default)]
pub struct StepProfile {
    pub cache_us: u64,
    pub attn_us: u64,
    pub mlp_us: u64,
    pub embed_us: u64,
    pub head_us: u64,
    pub steps: u64,
}

std::thread_local! {
    static STEP_PROFILE: std::cell::RefCell<StepProfile> =
        std::cell::RefCell::new(StepProfile::default());
}

fn qwen_profiling() -> bool {
    use std::sync::OnceLock;
    static ON: OnceLock<bool> = OnceLock::new();
    *ON.get_or_init(|| std::env::var_os("LAYA_QWEN_PROFILE").is_some_and(|v| !v.is_empty()))
}

/// LAYA_QWEN_PLAN=1 — the decode step runs as a declared plan (ADR 0055 P0).
fn qwen_plan_mode() -> bool {
    use std::sync::OnceLock;
    static ON: OnceLock<bool> = OnceLock::new();
    *ON.get_or_init(|| std::env::var_os("LAYA_QWEN_PLAN").is_some_and(|v| !v.is_empty()))
}

/// One decode step's declared plan plus the extra pool entries that are not
/// per-step inputs (the weights — owned by [`Qwen3`], which outlives the
/// execution).
pub struct StepPlan<'a> {
    pub plan: crate::plan::Plan,
    pub pool_weights: Vec<&'a Array>,
}

/// Prints and resets the accumulated profile (call after a decode loop).
pub fn qwen_profile_flush() {
    STEP_PROFILE.with(|p| {
        let mut p = p.borrow_mut();
        if p.steps > 0 {
            eprintln!(
                "qwen profile: {} steps | cache {:.1}ms attn {:.1}ms mlp {:.1}ms embed {:.1}ms head(readback) {:.1}ms | per-step total {:.1}ms",
                p.steps,
                p.cache_us as f64 / 1e3 / p.steps as f64,
                p.attn_us as f64 / 1e3 / p.steps as f64,
                p.mlp_us as f64 / 1e3 / p.steps as f64,
                p.embed_us as f64 / 1e3 / p.steps as f64,
                p.head_us as f64 / 1e3 / p.steps as f64,
                (p.cache_us + p.attn_us + p.mlp_us + p.embed_us + p.head_us) as f64 / 1e3
                    / p.steps as f64,
            );
        }
        *p = StepProfile::default();
    });
}

fn prof_add(section: &str, us: u64) {
    STEP_PROFILE.with(|p| {
        let mut p = p.borrow_mut();
        match section {
            "cache" => p.cache_us += us,
            "attn" => p.attn_us += us,
            "mlp" => p.mlp_us += us,
            "embed" => p.embed_us += us,
            "head" => p.head_us += us,
            "step" => p.steps += 1,
            _ => {}
        }
    });
}

/// Dispatches one op through the binding table. `ins` here are live array
/// refs, not plan slots — the qwen walk binds them at call time.
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
    Ok(outs.into_iter().next().ok_or(MlxError(-978))?)
}

#[allow(non_snake_case)]
fn Bin(kind: BinKind) -> Op {
    Op::Binary { kind }
}

#[derive(Deserialize)]
struct ConfigJson {
    hidden_size: usize,
    num_hidden_layers: usize,
    num_attention_heads: usize,
    num_key_value_heads: usize,
    head_dim: usize,
    intermediate_size: usize,
    vocab_size: usize,
    rms_norm_eps: f64,
    rope_theta: f64,
    tie_word_embeddings: bool,
    quantization: Option<QuantizationJson>,
}

#[derive(Deserialize)]
struct QuantizationJson {
    group_size: i32,
    bits: i32,
}

/// The parsed model config (mirrors config.json).
pub struct Qwen3Config {
    pub hidden_size: usize,
    pub layers: usize,
    pub heads: usize,
    pub kv_heads: usize,
    pub head_dim: usize,
    pub intermediate: usize,
    pub vocab: usize,
    pub rms_eps: f32,
    pub rope_theta: f32,
    pub tied_embeddings: bool,
    pub group_size: i32,
    pub bits: i32,
}

enum Weight {
    /// Affine-quantized (the mlx-community 4-bit exports).
    Quant(QuantizedTensor),
    /// Plain checkpoint tensor (bf16) — the R2 fp16/bf16 rung's path.
    Plain(Array),
}

pub struct Qwen3Layer {
    q: Weight,
    k: Weight,
    v: Weight,
    o: Weight,
    gate: Weight,
    up: Weight,
    down: Weight,
    q_norm: Array,
    k_norm: Array,
    ln1: Array,
    ln2: Array,
}

pub struct Qwen3 {
    pub cfg: Qwen3Config,
    embed: Weight,
    layers: Vec<Qwen3Layer>,
    norm: Array,
    table: BindingTable,
}

/// Per-layer KV cache mirroring mlx_lm's `KVCache` growth policy exactly:
/// zero-padded buffers grown in steps of 256, slice-assignment writes,
/// strided views for reads. The previous exact-size concat per step copied
/// the whole cache every decode token — the measured 5.6x long-context
/// decode gap vs python (ADR 0054 R2). Cache CONTENT is unchanged by the
/// policy (padding is never read), so the parity gate guards identity.
pub struct KvCache {
    layers: Vec<KvLayer>,
    pub offset: usize,
}

const KV_STEP: usize = 256;

pub struct KvLayer {
    /// Allocated buffer [B, Hkv, alloc, D] (alloc is a multiple of
    /// KV_STEP); reads slice [..., :offset, :].
    pub k: Option<Array>,
    pub v: Option<Array>,
}

impl KvCache {
    /// Read-only view of a layer's allocated (k, v) buffers — the awaited
    /// arrays for a UI driver's per-chunk eval+sync.
    pub fn layers_ref(&self) -> &[KvLayer] {
        &self.layers
    }

    pub fn new(layer_count: usize) -> KvCache {
        KvCache {
            layers: (0..layer_count)
                .map(|_| KvLayer { k: None, v: None })
                .collect(),
            offset: 0,
        }
    }

    fn update_one(
        table: &BindingTable,
        name: &str,
        buf: &Option<Array>,
        new: &Array,
        prev: usize,
        n: usize,
        s: Stream,
    ) -> MlxResult<Array> {
        let b = new.dim(0) as usize;
        let h = new.dim(1) as usize;
        let d = new.dim(3) as usize;
        let needs_grow = match buf {
            None => true,
            Some(bf) => prev + n > bf.dim(2) as usize,
        };
        let mut out = match (needs_grow, buf) {
            (false, Some(bf)) => bf.identity(s)?,
            // (false, None) is unreachable: needs_grow is true whenever the
            // buffer is absent.
            (false, None) => unreachable!("no buffer but no growth requested"),
            (true, _) => {
                let n_steps = (KV_STEP + n - 1) / KV_STEP;
                let alloc = n_steps * KV_STEP;
                let zeros = eval1(
                    table,
                    &format!("{name}.zeros"),
                    "q.cache",
                    Op::Full {
                        value: 0.0,
                        dtype: Dtype::BFloat16,
                        shape: vec![b, h, alloc, d],
                    },
                    &[],
                    s,
                )?;
                match buf {
                    None => zeros,
                    Some(bf) => {
                        // Python trims the buffer to `prev` when it holds
                        // padding, then appends the zero block.
                        let trimmed = if prev % KV_STEP != 0 {
                            eval1(
                                table,
                                &format!("{name}.trim"),
                                "q.cache",
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
                        eval1(
                            table,
                            &format!("{name}.grow"),
                            "q.cache",
                            Op::Concatenate { axis: 2 },
                            &[&trimmed, &zeros],
                            s,
                        )?
                    }
                }
            }
        };
        // buf[..., prev:prev+n, :] = new (functional slice update).
        out = eval1(
            table,
            &format!("{name}.write"),
            "q.cache",
            Op::SliceUpdate {
                start: vec![0, 0, prev as i32, 0],
                stop: vec![b as i32, h as i32, (prev + n) as i32, d as i32],
                strides: vec![1, 1, 1, 1],
            },
            &[&out, new],
            s,
        )?;
        Ok(out)
    }

    fn update(
        &mut self,
        table: &BindingTable,
        layer: usize,
        k: &Array,
        v: &Array,
        s: Stream,
    ) -> MlxResult<(Array, Array)> {
        // All layers write at the same step offset (python keeps one offset
        // per layer cache, and they stay in lockstep because every layer
        // processes the same token count); the OWNER of the step —
        // forward_step — bumps the shared offset once, never this method.
        let prev = self.offset;
        let n = k.dim(2) as usize;
        let slot = &mut self.layers[layer];
        let t0 = std::time::Instant::now();
        let kb = Self::update_one(table, "cache.k", &slot.k, k, prev, n, s)?;
        let vb = Self::update_one(table, "cache.v", &slot.v, v, prev, n, s)?;
        if qwen_profiling() {
            // Diagnostic mode pays eval+sync so the section attributes real
            // GPU time, not enqueue time.
            let _ = kb.eval();
            crate::mlx::synchronize_stream(s).ok();
            prof_add("cache", t0.elapsed().as_micros() as u64);
        }
        *slot = KvLayer { k: Some(kb.identity(s)?), v: Some(vb.identity(s)?) };
        // keys_and_values(): views down to the TOTAL written length
        // (prev + n), never the raw allocation.
        let total = prev + n;
        let view = |nm: &str, buf: &Array| -> MlxResult<Array> {
            if total < buf.dim(2) as usize {
                let b = buf.dim(0) as i32;
                let h = buf.dim(1) as i32;
                let d = buf.dim(3) as i32;
                eval1(
                    table,
                    nm,
                    "q.cache",
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
        Ok((view("cache.kv", &kb)?, view("cache.vv", &vb)?))
    }
}

impl Qwen3 {
    /// Loads config.json + model.safetensors from an HF snapshot directory.
    pub fn load(dir: &Path) -> MlxResult<Qwen3> {
        let cfg_raw: ConfigJson = serde_json::from_str(
            &std::fs::read_to_string(dir.join("config.json")).map_err(|_| MlxError(-12))?,
        )
        .map_err(|_| MlxError(-12))?;
        let (group_size, bits) = match &cfg_raw.quantization {
            Some(q) => (q.group_size, q.bits),
            None => (0, 0),
        };
        let cfg = Qwen3Config {
            hidden_size: cfg_raw.hidden_size,
            layers: cfg_raw.num_hidden_layers,
            heads: cfg_raw.num_attention_heads,
            kv_heads: cfg_raw.num_key_value_heads,
            head_dim: cfg_raw.head_dim,
            intermediate: cfg_raw.intermediate_size,
            vocab: cfg_raw.vocab_size,
            rms_eps: cfg_raw.rms_norm_eps as f32,
            rope_theta: cfg_raw.rope_theta as f32,
            tied_embeddings: cfg_raw.tie_word_embeddings,
            group_size,
            bits,
        };

        let st = SafetensorsFile::open(&dir.join("model.safetensors"))?;
        let weight = |name: &str| -> MlxResult<Weight> {
            // A tensor with .scales/.biases siblings is affine-quantized;
            // otherwise it is a plain checkpoint tensor.
            if st.dtype_of(&format!("{name}.scales")).is_some() {
                Ok(Weight::Quant(st.take_quantized(name)?))
            } else {
                Ok(Weight::Plain(st.take_any(&format!("{name}.weight"))?))
            }
        };

        let mut layers = Vec::with_capacity(cfg.layers);
        for l in 0..cfg.layers {
            let p = format!("model.layers.{l}");
            layers.push(Qwen3Layer {
                q: weight(&format!("{p}.self_attn.q_proj"))?,
                k: weight(&format!("{p}.self_attn.k_proj"))?,
                v: weight(&format!("{p}.self_attn.v_proj"))?,
                o: weight(&format!("{p}.self_attn.o_proj"))?,
                gate: weight(&format!("{p}.mlp.gate_proj"))?,
                up: weight(&format!("{p}.mlp.up_proj"))?,
                down: weight(&format!("{p}.mlp.down_proj"))?,
                q_norm: st.take_any(&format!("{p}.self_attn.q_norm.weight"))?,
                k_norm: st.take_any(&format!("{p}.self_attn.k_norm.weight"))?,
                ln1: st.take_any(&format!("{p}.input_layernorm.weight"))?,
                ln2: st.take_any(&format!("{p}.post_attention_layernorm.weight"))?,
            });
        }

        Ok(Qwen3 {
            embed: weight("model.embed_tokens")?,
            layers,
            norm: st.take_any("model.norm.weight")?,
            cfg,
            table: BindingTable::baseline(),
        })
    }

    // ---- op composites (the mlx-lm reference, op for op) ----

    fn linear(&self, name: &str, w: &Weight, x: &Array, s: Stream) -> MlxResult<Array> {
        match w {
            Weight::Quant(q) => eval1(
                &self.table,
                name,
                "q.linear",
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
                    "q.linear",
                    Op::Transpose { axes: vec![1, 0] },
                    &[w],
                    s,
                )?;
                eval1(&self.table, name, "q.linear", Op::Matmul, &[x, &wt], s)
            }
        }
    }

    fn rms(&self, name: &str, x: &Array, weight: &Array, s: Stream) -> MlxResult<Array> {
        eval1(
            &self.table,
            name,
            "q.norm",
            Op::RmsNorm { eps: self.cfg.rms_eps },
            &[x, weight],
            s,
        )
    }

    /// `QuantizedEmbedding.__call__`: gather packed rows for the token ids
    /// (flat take — the paid-for row-gather shape from the laya golden work),
    /// then affine-dequantize.
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
                    "q.embed",
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

    /// Row gather from [rows, cols] by [1, L] ids → [1, L, cols] (flat take
    /// with broadcast-scaled indices; take_along_axis preserves the INDICES'
    /// shape so it cannot express this gather narrowly).
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
            "q.embed",
            Op::Reshape { shape: vec![count] },
            &[table_arr],
            s,
        )?;
        let cols_c = eval1(
            &self.table,
            &format!("{name}.cols"),
            "q.embed",
            Op::ConstI32 { value: cols },
            &[],
            s,
        )?;
        let ids_col = eval1(
            &self.table,
            &format!("{name}.ids_col"),
            "q.embed",
            Op::Reshape { shape: vec![1, l, 1] },
            &[ids],
            s,
        )?;
        let scaled = eval1(
            &self.table,
            &format!("{name}.ids_scaled"),
            "q.embed",
            Bin(BinKind::Mul),
            &[&ids_col, &cols_c],
            s,
        )?;
        let col_idx = eval1(
            &self.table,
            &format!("{name}.cols_idx"),
            "q.embed",
            Op::ArangeI32 { start: 0, stop: cols },
            &[],
            s,
        )?;
        let flat_idx = eval1(
            &self.table,
            &format!("{name}.flat_idx"),
            "q.embed",
            Bin(BinKind::Add),
            &[&scaled, &col_idx],
            s,
        )?;
        eval1(&self.table, name, "q.embed", Op::Take, &[&flat, &flat_idx], s)
    }

    /// The final-norm hidden state for `tokens` ([1, L] i32) with the
    /// cache — the whole transformer EXCEPT the lm_head. R5's chunked
    /// prefill runs chunks through THIS (a chunk's logits are never read;
    /// the old path materialized a [1, 2047, 151936] logit tensor per
    /// chunk — ~0.6 GB and hundreds of GFLOPs of pure waste per 2k-prompt
    /// prefill).
    pub fn forward_hidden(&self, tokens: &Array, cache: &mut KvCache, s: Stream) -> MlxResult<Array> {
        self.forward_impl(tokens, cache, s)
    }

    /// One forward pass over `tokens` ([1, L] i32) with the cache. Returns
    /// logits [1, L, V] (unevaluated, like every plan output).
    pub fn forward_step(&self, tokens: &Array, cache: &mut KvCache, s: Stream) -> MlxResult<Array> {
        self.step_logits(tokens, cache, qwen_plan_mode(), s)
    }

    /// The decode step on an explicit path: `use_plan` runs the declared
    /// step plan (ADR 0055 P0), else the imperative walk. Both submit the
    /// same ops through the same binding table — the parity test guards
    /// bit-identity between them.
    pub fn step_logits(
        &self,
        tokens: &Array,
        cache: &mut KvCache,
        use_plan: bool,
        s: Stream,
    ) -> MlxResult<Array> {
        if use_plan {
            return self.forward_step_plan(tokens, cache, s);
        }
        let t = self.forward_impl(tokens, cache, s)?;
        // Tied embeddings: the lm_head IS the (quantized) embedding table,
        // applied as_linear.
        self.linear("q.lm_head", &self.embed, &t, s)
    }

    /// LAYA_QWEN_PLAN=1 — the decode step runs as a declared plan (ADR 0055
    /// P0) instead of the imperative walk. Both walks submit the same ops in
    /// the same order through the same binding table; the parity test guards
    /// bit-identity between them.
    fn forward_step_plan(
        &self,
        tokens: &Array,
        cache: &mut KvCache,
        s: Stream,
    ) -> MlxResult<Array> {
        // Decode steps see post-prefill caches; a None buffer means the
        // caller violated the prefill-first contract.
        for slot in &cache.layers {
            if slot.k.is_none() || slot.v.is_none() {
                return Err(MlxError(-978));
            }
        }
        let offset = cache.offset; // constant for this plan (RoPE + slice bounds)
        let plan = self.build_step_plan(tokens, cache, offset)?;
        if let Some(path) = std::env::var_os("LAYA_QWEN_PLAN_DUMP") {
            let _ = std::fs::write(std::path::PathBuf::from(path), plan.plan.to_json());
        }
        // Pool order mirrors build_step_plan's registration order: tokens,
        // then every pinned array (embed tables, per-layer cache buffers,
        // weights) in first-use order. Weight/cache arrays are owned by
        // `self`/`cache`, which outlive the execution.
        let mut pool: Vec<&Array> = Vec::with_capacity(plan.pool_weights.len() + 1);
        pool.push(tokens);
        pool.extend(plan.pool_weights.iter().copied());
        if std::env::var_os("LAYA_QWEN_PLAN_DEBUG").is_some() {
            for (i, name) in plan.plan.ctx.iter().enumerate() {
                let a = pool[i];
                eprintln!("pool[{i}] {name} shape {:?} ndim {}", (0..a.ndim()).map(|d| a.dim(d as i32)).collect::<Vec<_>>(), a.ndim());
            }
        }
        let outs = crate::plan::execute_outputs(
            &plan.plan,
            &crate::plan::ExecPool { arrays: pool },
            &self.table,
            s,
            crate::plan::ExecOptions::runtime(),
        )?;
        // Outputs: [k_0', v_0', ..., k_{L-1}', v_{L-1}', logits].
        let l = cache.layers.len();
        if outs.len() != 2 * l + 1 {
            return Err(MlxError(-983));
        }
        for (li, slot) in cache.layers.iter_mut().enumerate() {
            slot.k = Some(outs[2 * li].identity(s)?);
            slot.v = Some(outs[2 * li + 1].identity(s)?);
        }
        cache.offset += 1;
        Ok(outs[2 * l].identity(s)?)
    }

    /// Declares the decode step (l = 1) as a plan: node-for-node the
    /// imperative walk, with the RoPE offset and slice bounds as per-step
    /// plan constants (the plan is rebuilt every step — the shape-keyed
    /// compile route needs an offset-as-input op variant first, ADR 0055).
    /// The KV buffers are plan inputs; the written buffers and logits are
    /// the declared outputs (functional slice_update, python-parity order).
    fn build_step_plan<'a>(
        &'a self,
        tokens: &'a Array,
        cache: &'a KvCache,
        offset: usize,
    ) -> MlxResult<StepPlan<'a>> {
        let cfg = &self.cfg;
        let (n_h, n_kv, d) = (cfg.heads, cfg.kv_heads, cfg.head_dim);
        let l = 1usize;
        let total = offset + 1; // plan constant (RoPE + slice bounds)
        let scale = (d as f32).powf(-0.5);
        let mut b = crate::plan::PlanBuilder::default();
        let mut pool_weights: Vec<&'a Array> = Vec::new();
        // Every non-weight array (weights included) enters the pool through
        // an Input node; weights register lazily per use site — the executor
        // skips Input nodes, so duplicates only cost pool slots.
        let pin = |b: &mut crate::plan::PlanBuilder,
                       pool: &mut Vec<&'a Array>,
                       arr: &'a Array,
                       name: &str|
         -> crate::plan::NodeId { pool.push(arr); b.input(name, None) };

        // pool[0]; NOT registered in pool_weights (the pool already carries it).
        let tok = b.input("q.tokens", None);

        // ---- embed (QuantizedEmbedding.__call__, op for op) ----
        let emb_g = "q.embed";
        let gather = |b: &mut crate::plan::PlanBuilder,
                      pool: &mut Vec<&'a Array>,
                      nm: &str,
                      table_arr: &'a Array,
                      cols: i32|
         -> MlxResult<crate::plan::NodeId> {
            let cols_c = b.push(emb_g, Op::ConstI32 { value: cols }, &format!("{nm}.cols"), &[], None);
            let ids_col = b.push(emb_g, Op::Reshape { shape: vec![1, l, 1] }, &format!("{nm}.ids_col"), &[(tok, 0)], None);
            let scaled = b.push(emb_g, Bin(BinKind::Mul), &format!("{nm}.ids_scaled"), &[(ids_col, 0), (cols_c, 0)], None);
            let col_idx = b.push(emb_g, Op::ArangeI32 { start: 0, stop: cols }, &format!("{nm}.cols_idx"), &[], None);
            let flat_idx = b.push(emb_g, Bin(BinKind::Add), &format!("{nm}.flat_idx"), &[(scaled, 0), (col_idx, 0)], None);
            let tn = pin(b, pool, table_arr, &format!("{nm}.table"));
            let count: usize = (0..table_arr.ndim()).map(|dd| table_arr.dim(dd as i32) as usize).product();
            let flat = b.push(emb_g, Op::Reshape { shape: vec![count] }, &format!("{nm}.flat"), &[(tn, 0)], None);
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
        let mut new_k: Vec<crate::plan::NodeId> = Vec::with_capacity(cfg.layers);
        let mut new_v: Vec<crate::plan::NodeId> = Vec::with_capacity(cfg.layers);
        for (li, layer) in self.layers.iter().enumerate() {
            let g = format!("q.l{li:02}");
            let cache_in = |b: &mut crate::plan::PlanBuilder,
                            pool: &mut Vec<&'a Array>,
                            nm: &str,
                            buf: &'a Option<Array>|
             -> crate::plan::NodeId {
                let arr = buf.as_ref().expect("decode cache buffer");
                pin(b, pool, arr, nm)
            };
            let kb_in = cache_in(&mut b, &mut pool_weights, &format!("{g}.kbuf"), &cache.layers[li].k);
            let vb_in = cache_in(&mut b, &mut pool_weights, &format!("{g}.vbuf"), &cache.layers[li].v);

            let ln1_w = pin(&mut b, &mut pool_weights, &layer.ln1, &format!("{g}.ln1.w"));
            let ln1 = b.push(&g, Op::RmsNorm { eps: cfg.rms_eps }, &format!("{g}.ln1"), &[(h, 0), (ln1_w, 0)], None);
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
                        Ok(b.push(&g, Op::QuantizedMatmul { group_size: cfg.group_size, bits: cfg.bits, transpose: true }, nm, &[x, (wn, 0), (sn, 0), (bn, 0)], None))
                    }
                    Weight::Plain(w) => {
                        let wn = pin(b, pool, w, &format!("{nm}.w"));
                        let wt = b.push(&g, Op::Transpose { axes: vec![1, 0] }, &format!("{nm}.w_t"), &[(wn, 0)], None);
                        Ok(b.push(&g, Op::Matmul, nm, &[x, (wt, 0)], None))
                    }
                }
            };
            let q = linear(&mut b, &mut pool_weights, &format!("{g}.q"), &layer.q, (ln1, 0))?;
            let k = linear(&mut b, &mut pool_weights, &format!("{g}.k"), &layer.k, (ln1, 0))?;
            let v = linear(&mut b, &mut pool_weights, &format!("{g}.v"), &layer.v, (ln1, 0))?;

            let reshape = |b: &mut crate::plan::PlanBuilder, nm: &str, src: crate::plan::NodeId, heads: usize| {
                b.push(&g, Op::Reshape { shape: vec![1, l, heads, d] }, nm, &[(src, 0)], None)
            };
            let qh = reshape(&mut b, &format!("{g}.q_h"), q, n_h);
            let kh = reshape(&mut b, &format!("{g}.k_h"), k, n_kv);
            let vh = reshape(&mut b, &format!("{g}.v_h"), v, n_kv);
            let qn_w = pin(&mut b, &mut pool_weights, &layer.q_norm, &format!("{g}.q_norm.w"));
            let qn = b.push(&g, Op::RmsNorm { eps: cfg.rms_eps }, &format!("{g}.q_norm"), &[(qh, 0), (qn_w, 0)], None);
            let kn_w = pin(&mut b, &mut pool_weights, &layer.k_norm, &format!("{g}.k_norm.w"));
            let kn = b.push(&g, Op::RmsNorm { eps: cfg.rms_eps }, &format!("{g}.k_norm"), &[(kh, 0), (kn_w, 0)], None);
            let transpose = |b: &mut crate::plan::PlanBuilder, nm: &str, src: crate::plan::NodeId| {
                b.push(&g, Op::Transpose { axes: vec![0, 2, 1, 3] }, nm, &[(src, 0)], None)
            };
            let qt = transpose(&mut b, &format!("{g}.q_t"), qn);
            let kt = transpose(&mut b, &format!("{g}.k_t"), kn);
            let vt = transpose(&mut b, &format!("{g}.v_t"), vh);
            let qr = b.push(&g, Op::Rope { dims: d as i32, base: cfg.rope_theta, offset: offset as i32 }, &format!("{g}.rope_q"), &[(qt, 0)], None);
            let kr = b.push(&g, Op::Rope { dims: d as i32, base: cfg.rope_theta, offset: offset as i32 }, &format!("{g}.rope_k"), &[(kt, 0)], None);

            // Cache write: buf[..., off:off+1, :] = new (functional).
            let bh = n_kv as i32;
            let dd = d as i32;
            let kc = b.push(&g, Op::SliceUpdate { start: vec![0, 0, offset as i32, 0], stop: vec![1, bh, (offset + 1) as i32, dd], strides: vec![1, 1, 1, 1] }, &format!("{g}.k_write"), &[(kb_in, 0), (kr, 0)], None);
            let vc = b.push(&g, Op::SliceUpdate { start: vec![0, 0, offset as i32, 0], stop: vec![1, bh, (offset + 1) as i32, dd], strides: vec![1, 1, 1, 1] }, &format!("{g}.v_write"), &[(vb_in, 0), (vt, 0)], None);
            new_k.push(kc);
            new_v.push(vc);
            // Read view: [.., :total, :] — identity when total fills the alloc
            // (mirrors KvCache::update exactly).
            let k_alloc = cache.layers[li].k.as_ref().map(|a| a.dim(2) as usize).unwrap_or(0);
            let v_alloc = cache.layers[li].v.as_ref().map(|a| a.dim(2) as usize).unwrap_or(0);
            let view = |b: &mut crate::plan::PlanBuilder, nm: &str, src: crate::plan::NodeId, alloc: usize| {
                if total < alloc {
                    b.push(&g, Op::Slice { start: vec![0, 0, 0, 0], stop: vec![1, bh, total as i32, dd], strides: vec![1, 1, 1, 1] }, nm, &[(src, 0)], None)
                } else {
                    src
                }
            };
            let kc_view = view(&mut b, &format!("{g}.kv"), kc, k_alloc);
            let vc_view = view(&mut b, &format!("{g}.vv"), vc, v_alloc);

            let att = b.push(&g, Op::Sdp { scale, causal: false }, &format!("{g}.sdp"), &[(qr, 0), (kc_view, 0), (vc_view, 0)], None);
            let att_t = transpose(&mut b, &format!("{g}.att_t"), att);
            let att_r = b.push(&g, Op::Reshape { shape: vec![1, l, n_h * d] }, &format!("{g}.att_r"), &[(att_t, 0)], None);
            let o = linear(&mut b, &mut pool_weights, &format!("{g}.o"), &layer.o, (att_r, 0))?;
            let ln2_w = pin(&mut b, &mut pool_weights, &layer.ln2, &format!("{g}.ln2.w"));
            let fused = b.push(&g, Op::RmsNormResidual { eps: cfg.rms_eps }, &format!("{g}.res1_ln2"), &[(h, 0), (o, 0), (ln2_w, 0)], None);
            let h1 = (fused, 0);
            let ln2 = (fused, 1);

            let gate = linear(&mut b, &mut pool_weights, &format!("{g}.gate"), &layer.gate, ln2)?;
            let up = linear(&mut b, &mut pool_weights, &format!("{g}.up"), &layer.up, ln2)?;
            let sig = b.push(&g, Op::Unary { kind: UnaryKind::Sigmoid }, &format!("{g}.sig"), &[(gate, 0)], None);
            let silu = b.push(&g, Bin(BinKind::Mul), &format!("{g}.silu"), &[(gate, 0), (sig, 0)], None);
            let ff_in = b.push(&g, Bin(BinKind::Mul), &format!("{g}.ff_in"), &[(silu, 0), (up, 0)], None);
            let ff = linear(&mut b, &mut pool_weights, &format!("{g}.down"), &layer.down, (ff_in, 0))?;
            h = b.push(&g, Bin(BinKind::Add), &format!("{g}.res2"), &[h1, (ff, 0)], None);
        }

        let norm_w = pin(&mut b, &mut pool_weights, &self.norm, "q.final_norm.w");
        let t = b.push("q.norm", Op::RmsNorm { eps: cfg.rms_eps }, "q.final_norm", &[(h, 0), (norm_w, 0)], None);
        let logits = match &self.embed {
            Weight::Quant(q) => {
                let wn = pin(&mut b, &mut pool_weights, &q.w, "q.lm_head.q8");
                let sn = pin(&mut b, &mut pool_weights, &q.scales, "q.lm_head.q8_scales");
                let bn = pin(&mut b, &mut pool_weights, &q.biases, "q.lm_head.q8_biases");
                b.push("q.head", Op::QuantizedMatmul { group_size: cfg.group_size, bits: cfg.bits, transpose: true }, "q.lm_head", &[(t, 0), (wn, 0), (sn, 0), (bn, 0)], None)
            }
            Weight::Plain(w) => {
                let wn = pin(&mut b, &mut pool_weights, w, "q.lm_head.w");
                let wt = b.push("q.head", Op::Transpose { axes: vec![1, 0] }, "q.lm_head.w_t", &[(wn, 0)], None);
                b.push("q.head", Op::Matmul, "q.lm_head", &[(t, 0), (wt, 0)], None)
            }
        };
        let mut outputs = Vec::with_capacity(2 * cfg.layers + 1);
        for li in 0..cfg.layers {
            outputs.push(new_k[li]);
            outputs.push(new_v[li]);
        }
        outputs.push(logits);
        Ok(StepPlan {
            plan: crate::plan::Plan {
                nodes: b.nodes,
                logits,
                act: logits,
                ctx: b.ctx,
                outputs,
            },
            pool_weights,
        })
    }

    fn forward_impl(&self, tokens: &Array, cache: &mut KvCache, s: Stream) -> MlxResult<Array> {
        let l = tokens.dim(1) as usize;
        let seq_group = if l > 1 { "q.prefill" } else { "q.decode" };
        let cfg = &self.cfg;
        let (n_h, n_kv, d) = (cfg.heads, cfg.kv_heads, cfg.head_dim);
        let scale = (d as f32).powf(-0.5);

        let prof = qwen_profiling();
        let t_head = std::time::Instant::now();
        let t_embed = std::time::Instant::now();
        let mut h = self.embed(tokens, l, s)?;
        if prof {
            let _ = h.eval();
            crate::mlx::synchronize_stream(s).ok();
            prof_add("embed", t_embed.elapsed().as_micros() as u64);
        }

        for (li, layer) in self.layers.iter().enumerate() {
            let g = format!("q.l{li:02}");
            let t_attn = std::time::Instant::now();

            // --- attention ---
            let ln1 = self.rms(&format!("{g}.ln1"), &h, &layer.ln1, s)?;
            let q = self.linear(&format!("{g}.q"), &layer.q, &ln1, s)?;
            let k = self.linear(&format!("{g}.k"), &layer.k, &ln1, s)?;
            let v = self.linear(&format!("{g}.v"), &layer.v, &ln1, s)?;

            let reshape = |nm: &str, arr: &Array, heads: usize| -> MlxResult<Array> {
                eval1(
                    &self.table,
                    nm,
                    &g,
                    Op::Reshape { shape: vec![1, l, heads, d] },
                    &[arr],
                    s,
                )
            };
            let qh = reshape(&format!("{g}.q_h"), &q, n_h)?;
            let kh = reshape(&format!("{g}.k_h"), &k, n_kv)?;
            let vh = reshape(&format!("{g}.v_h"), &v, n_kv)?;

            // QK-norm over the head axis (before the transpose, as the
            // reference does), then [B, H, L, D].
            let qn = self.rms(&format!("{g}.q_norm"), &qh, &layer.q_norm, s)?;
            let kn = self.rms(&format!("{g}.k_norm"), &kh, &layer.k_norm, s)?;
            let transpose = |nm: &str, arr: &Array| -> MlxResult<Array> {
                eval1(
                    &self.table,
                    nm,
                    &g,
                    Op::Transpose { axes: vec![0, 2, 1, 3] },
                    &[arr],
                    s,
                )
            };
            let qt = transpose(&format!("{g}.q_t"), &qn)?;
            let kt = transpose(&format!("{g}.k_t"), &kn)?;
            let vt = transpose(&format!("{g}.v_t"), &vh)?;

            // RoPE at the cache offset; the cache append AFTER roping (the
            // reference ropes only the step's new keys).
            let off = cache.offset as i32;
            let qr = eval1(
                &self.table,
                &format!("{g}.rope_q"),
                &g,
                Op::Rope { dims: d as i32, base: cfg.rope_theta, offset: off },
                &[&qt],
                s,
            )?;
            let kr = eval1(
                &self.table,
                &format!("{g}.rope_k"),
                &g,
                Op::Rope { dims: d as i32, base: cfg.rope_theta, offset: off },
                &[&kt],
                s,
            )?;
            let (kc, vc) = cache.update(&self.table, li, &kr, &vt, s)?;

            // Prefill (L>1) takes the kernel's native causal path — exactly
            // the "causal" mask string python passes; decode steps pass no
            // mask (a single query attends to everything cached).
            let att = eval1(
                &self.table,
                &format!("{g}.sdp"),
                &g,
                Op::Sdp { scale, causal: l > 1 },
                &[&qr, &kc, &vc],
                s,
            )?;

            let att_t = transpose(&format!("{g}.att_t"), &att)?;
            let att_r = eval1(
                &self.table,
                &format!("{g}.att_r"),
                &g,
                Op::Reshape { shape: vec![1, l, n_h * d] },
                &[&att_t],
                s,
            )?;
            let o = self.linear(&format!("{g}.o"), &layer.o, &att_r, s)?;
            // Fused residual+RMSNorm (R4 epilogue): outputs [sum, normed].
            // The default table's binding is the Add + RmsNorm composition
            // it replaces — bit-identical; LAYA_MSL_NORM=1 swaps in the
            // one-pass kernel.
            let fused = {
                let node = Node {
                    name: format!("{g}.res1_ln2"),
                    group: g.clone(),
                    op: Op::RmsNormResidual { eps: cfg.rms_eps },
                    inputs: Vec::new(),
                    dump: None,
                };
                crate::bindings::eval(&node, &[&h, &o, &layer.ln2], &self.table, s)?
            };
            let mut fused = fused.into_iter();
            let h1 = fused.next().ok_or(MlxError(-978))?;
            let ln2_fused = fused.next().ok_or(MlxError(-978))?;
            if prof {
                let _ = h1.eval();
                crate::mlx::synchronize_stream(s).ok();
                prof_add("attn", t_attn.elapsed().as_micros() as u64);
            }
            let t_mlp = std::time::Instant::now();

            // --- mlp: down(silu(gate(x)) * up(x)) ---
            let ln2 = ln2_fused;
            let gate = self.linear(&format!("{g}.gate"), &layer.gate, &ln2, s)?;
            let up = self.linear(&format!("{g}.up"), &layer.up, &ln2, s)?;
            let sig = eval1(
                &self.table,
                &format!("{g}.sig"),
                &g,
                Op::Unary { kind: UnaryKind::Sigmoid },
                &[&gate],
                s,
            )?;
            let silu = eval1(
                &self.table,
                &format!("{g}.silu"),
                &g,
                Bin(BinKind::Mul),
                &[&gate, &sig],
                s,
            )?;
            let ff_in = eval1(
                &self.table,
                &format!("{g}.ff_in"),
                &g,
                Bin(BinKind::Mul),
                &[&silu, &up],
                s,
            )?;
            let ff = self.linear(&format!("{g}.down"), &layer.down, &ff_in, s)?;
            h = eval1(
                &self.table,
                &format!("{g}.res2"),
                seq_group,
                Bin(BinKind::Add),
                &[&h1, &ff],
                s,
            )?;
            if prof {
                let _ = h.eval();
                crate::mlx::synchronize_stream(s).ok();
                prof_add("mlp", t_mlp.elapsed().as_micros() as u64);
            }
        }

        let t = self.rms("q.final_norm", &h, &self.norm, s)?;
        // One offset bump per step (after the layer loop — see KvCache::update).
        cache.offset += l;
        if prof {
            prof_add("head", t_head.elapsed().as_micros() as u64);
            prof_add("step", 0);
        }
        Ok(t)
    }

    /// Greedy decode, token-for-token the reference pipeline. PARITY-
    /// LOAD-BEARING SHAPE: mlx_lm's generate_step chunks the prefill
    /// (prefill_step_size tokens per call, while more than one token
    /// remains) and rides the LAST prompt token through the one-token
    /// decode loop. The chunk split decides the attention kernel's tiling;
    /// at a bf16 logit tie (observed: "1990s" vs "2000s" at 20.375/20.375)
    /// a whole-prompt prefill breaks the tie the other way. Never merge
    /// the chunked prefill into one pass to save a call.
    pub fn generate_greedy(
        &self,
        prompt_ids: &[i32],
        max_tokens: usize,
        s: Stream,
    ) -> MlxResult<Vec<i32>> {
        if prompt_ids.is_empty() {
            return Err(MlxError(-978));
        }
        let mut cache = KvCache::new(self.cfg.layers);
        let mut out: Vec<i32> = Vec::with_capacity(prompt_ids.len() + max_tokens);
        out.extend_from_slice(prompt_ids);

        const PREFILL_STEP: usize = 2048;
        let mut rest = prompt_ids;
        while rest.len() > 1 {
            let n = PREFILL_STEP.min(rest.len() - 1);
            let t = Array::from_data_i32(&rest[..n], &[1, n])?;
            // KV-only chunk: no lm_head (a chunk's logits are never read).
            self.forward_hidden(&t, &mut cache, s)?;
            rest = &rest[n..];
        }

        // Each step feeds one token and yields the argmax (readback through
        // f32: token ids up to ~152k are exact in f32).
        let mut next: i32 = rest[0];
        for _ in 0..max_tokens {
            let tokens = Array::from_data_i32(&[next], &[1, 1])?;
            let logits = self.forward_step(&tokens, &mut cache, s)?;
            let am = logits.argmax_axis(-1, false, s)?;
            let f = am.astype(Dtype::Float32, s)?;
            let v = f.to_f32_vec(s)?;
            let t = v.first().copied().ok_or(MlxError(-978))? as i32;
            next = t;
            out.push(t);
        }
        if qwen_profiling() {
            qwen_profile_flush();
        }
        Ok(out)
    }
}
