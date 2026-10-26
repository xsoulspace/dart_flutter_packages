//! L-G4 — the batched-decode lever: the batch API, the batch-invariance
//! probes, and the amortization probes.
//!
//! # WHAT THIS FILE IS, AND WHAT IT IS NOT
//!
//! The question L-G4 asks is whether this device decodes more tokens per
//! second when N sequences are decoded AT ONCE (one weight read amortized
//! over N sequences) than when they are decoded one at a time.
//!
//! ## Is a true batched forward reachable without editing `qwen.rs`?
//!
//! **No.** The trunk's forward path is batch-1 by construction. What I
//! verified by reading `qwen.rs`:
//!
//!   * `Qwen3::forward_step` / `forward_hidden` take `tokens` shaped
//!     `[1, L]` and the plan builder reshapes every activation to
//!     `[1, l, heads, d]` and every attention output to `[1, l, n_h * d]`;
//!   * the embedding gather reshapes the ids to `[1, l, 1]`, so a `[B, L]`
//!     token array cannot even be gathered;
//!   * `KvCache::reserve` allocates the KV buffers with the batch dim
//!     hardcoded to `1` (`(1, kv_heads, head_dim)`), and the plan's cache
//!     write stops at index `1` on the batch axis;
//!   * `Qwen3::embed` (the trunk's own tied embedding) is a PRIVATE field,
//!     so even the projection's weights are not reachable from outside
//!     `qwen.rs`.
//!
//! The **plan ops themselves are batch-capable** (`Op::Reshape`,
//! `Op::SliceUpdate`, `Op::Sdp`, `Op::QuantizedMatmul` all take explicit
//! shapes, and MLX's own kernels are batched), so the blocker is the plan
//! BUILDER's hardcoded `1`s plus the cache's batch dim and its single
//! offset — not the op set. The minimal `qwen.rs` change is written out
//! at the bottom of this file.
//!
//! ## What this file therefore delivers
//!
//!   1. [`generate_greedy_batched`] — the batch API with LOCKSTEP
//!      semantics: every sequence advances one token per step and each
//!      sequence keeps its OWN `KvCache`, so a sequence's output never
//!      depends on its neighbours.
//!
//!      **This is a CONTROL, not the lever.** One `forward_step` is
//!      submitted per sequence per step, so the weight read is NOT
//!      amortized over the batch — the aggregate tok/s it reports is the
//!      "no fusion" baseline. It is **not** the L-G4 gate number and must
//!      never be reported as one.
//!   2. [`check_batch_invariance`] — the decode-level invariance check: the
//!      same prompts decoded sequentially and in the batch, compared token
//!      for token, with the first divergence index.
//!   3. [`probe_batch_numerics`] — the FUSION precondition: does a
//!      BATCHED matmul produce the same numbers, bit for bit, as the same
//!      row computed alone? If it does not, a fused batched decode would
//!      not reproduce a sequential one, and every number measured through
//!      it is a function of the batch size — a function of a choice, not
//!      a measurement. The probe measures the real thing (the checkpoint's
//!      real quantized weights, through the trunk's own plan ops and
//!      binding table) and REPORTS the divergence instead of papering over
//!      it.
//!   4. [`probe_batch_amortization`] — the lever probe: the cost of the
//!      tied vocabulary projection and of a body layer's quantized GEMM
//!      stack at `[B, 1, H]`, forced-evaluated, through the same plan ops
//!      and the same binding table. The derived amortization factor is
//!      what says whether buying a fused batch is worth it.
//!
//! # THE LAWS THIS FILE OBEYS
//!
//! * MLX IS LAZY: every probe forces the ACTUAL output it is timing
//!   (`Array::eval()` + a stream sync), never an unrelated dummy array.
//! * The probes go through `bindings::eval` with the TRUNK'S binding
//!   table, so the SHAPE CLASS (GEMV vs skinny-GEMM vs wide-GEMM) and the
//!   backend are the ones the product would actually use — a probe that
//!   called MLX directly would measure a different kernel.
//! * A number without its baseline is not a number: every probe reports
//!   the batch-1 point next to the batched ones.
//! * Absence of a number is reported as absence, never as a zero or a
//!   guess.

use std::path::Path;

use crate::bindings::{self, BindingTable};
use crate::mlx::{Array, Dtype, MlxError, MlxResult, Stream};
use crate::plan::{Node, Op};
use crate::qwen::{KvCache, Qwen3};
use crate::safetensors::{QuantizedTensor, SafetensorsFile};

/// Whether a FUSED batched forward (one forward over `[B, L]`) is reachable
/// from this crate today.
///
/// It is **not**: `qwen.rs`'s plan builder hardcodes the batch dim to `1`
/// in every reshape and in the KV cache's write bounds, `KvCache::reserve`
/// allocates the buffers with a batch dim of `1`, and the trunk's tied
/// embedding is a private field. The plan OPS are batch-capable; the
/// BUILDER is not. See the module docs for the minimal change.
pub const FUSED_BATCH_FORWARD_AVAILABLE: bool = false;

/// The reason [`FUSED_BATCH_FORWARD_AVAILABLE`] is false, and what the
/// minimal `qwen.rs` change would be.
pub const FUSED_BATCH_FORWARD_NOTE: &str = "\
qwen.rs builds every forward with the batch dim hardcoded to 1 (the plan's \
reshapes are [1, l, heads, d] / [1, l, n_h*d], the KV cache write stops at \
index 1 on the batch axis, and KvCache::reserve allocates [1, Hkv, alloc, D]); \
the trunk's tied embedding is also a private field. The plan OPS are already \
batch-capable. The minimal change is: (a) take the batch dim from the token \
array's dim 0 in build_forward_plan's reshapes and in the cache write's \
stop; (b) allocate the KV buffers with that batch dim; (c) give the cache a \
per-sequence offset (or left-pad the prompts and pass a keep-mask to Op::Sdp, \
which already supports one); (d) expose the trunk's tied embedding (or the \
lm_head) so the batched projection can run on the same weights.";

/// One sequence in a batch request.
#[derive(Clone, Debug)]
pub struct BatchRequest {
    /// The prompt token ids (the sequence's own prefix; no padding).
    pub prompt_ids: Vec<i32>,
    /// How many tokens this sequence may generate.
    pub max_tokens: usize,
}

/// The outcome of a batched greedy decode — one entry per request, in the
/// request order.
#[derive(Clone, Debug)]
pub struct BatchOutcome {
    /// The GENERATED tokens per request. The prompt is NOT repeated here
    /// (it is the caller's, and it is in `BatchRequest::prompt_ids`).
    pub completions: Vec<Vec<i32>>,
    /// Why each sequence stopped: `"stop"` (a stop id was emitted) or
    /// `"max_tokens"`.
    pub stop_reasons: Vec<String>,
}

/// The clock split of one batched decode: prefill (prompt ingestion) and
/// decode (the generated tokens), separated so a throughput number can be
/// quoted on the decode side only — the same clock placement the lane's
/// other benches use.
#[derive(Clone, Copy, Debug, Default)]
pub struct BatchTiming {
    pub prefill_s: f64,
    pub decode_s: f64,
    /// The tokens GENERATED across the whole batch (one per sequence per
    /// step, summed).
    pub tokens: usize,
}

/// Greedy decode of a batch of sequences in LOCKSTEP.
///
/// Every sequence advances one token per step and each sequence keeps its
/// OWN [`KvCache`], so a sequence's output does not depend on its
/// neighbours. **This is a control, not the lever**: one `forward_step` is
/// submitted per sequence per step, so the weight read is NOT amortized
/// over the batch. The lever's numbers come from
/// [`probe_batch_amortization`] (would a fused batch amortize?) and the
/// fused path's own precondition from [`probe_batch_numerics`] (would a
/// fused batch even reproduce the sequential tokens?).
///
/// The per-sequence decode is token-for-token the same computation as
/// `Qwen3::generate_greedy` (same chunked prefill, same forward + argmax +
/// f32 readback), which is what makes [`check_batch_invariance`] a real
/// check rather than a tautology.
pub fn generate_greedy_batched(
    model: &Qwen3,
    reqs: &[BatchRequest],
    stop: Option<&[i32]>,
    s: Stream,
) -> MlxResult<BatchOutcome> {
    Ok(generate_greedy_batched_timed(model, reqs, stop, s)?.0)
}

/// [`generate_greedy_batched`] plus the prefill/decode clock split.
pub fn generate_greedy_batched_timed(
    model: &Qwen3,
    reqs: &[BatchRequest],
    stop: Option<&[i32]>,
    s: Stream,
) -> MlxResult<(BatchOutcome, BatchTiming)> {
    if reqs.is_empty() {
        return Err(MlxError(-978));
    }
    let n = reqs.len();
    let mut caches: Vec<KvCache> = (0..n).map(|_| KvCache::new(model.cfg.layers)).collect();
    let mut current: Vec<i32> = vec![0; n];
    let mut generated: Vec<Vec<i32>> = vec![Vec::new(); n];
    let mut reasons: Vec<String> = vec!["max_tokens".to_string(); n];
    let mut finished: Vec<bool> = vec![false; n];

    // ---- prefill: every prompt but its last token (the same split the
    // single-sequence greedy uses, so the two agree token for token) ----
    let prefill_clock = std::time::Instant::now();
    for (i, req) in reqs.iter().enumerate() {
        if req.prompt_ids.is_empty() {
            return Err(MlxError(-978));
        }
        if req.max_tokens == 0 {
            // Nothing to generate: the sequence is finished before it starts.
            finished[i] = true;
            continue;
        }
        caches[i].reserve(
            model.table(),
            1, // batch
            model.cfg.kv_heads,
            model.cfg.head_dim,
            req.prompt_ids.len() + req.max_tokens,
            s,
        )?;
        let mut rest: &[i32] = &req.prompt_ids;
        const CHUNK: usize = 2048;
        while rest.len() > 1 {
            let n = CHUNK.min(rest.len() - 1);
            let tokens = Array::from_data_i32(&rest[..n], &[1, n])?;
            model.forward_hidden(&tokens, &mut caches[i], s)?;
            rest = &rest[n..];
        }
        current[i] = rest[0];
    }
    let prefill_s = prefill_clock.elapsed().as_secs_f64();

    // ---- decode: one token per sequence per step ----
    let decode_clock = std::time::Instant::now();
    let max_steps = reqs.iter().map(|r| r.max_tokens).max().unwrap_or(0);
    let mut tokens = 0usize;
    for _ in 0..max_steps {
        let mut pending: Vec<(usize, Array)> = Vec::with_capacity(n);
        for i in 0..n {
            if finished[i] {
                continue;
            }
            let tokens = Array::from_data_i32(&[current[i]], &[1, 1])?;
            let logits = model.forward_step(&tokens, &mut caches[i], s)?;
            let argmax = logits.argmax_axis(-1, false, s)?;
            pending.push((i, argmax));
        }
        if pending.is_empty() {
            break;
        }
        for (i, argmax) in pending {
            // The readback forces the ACTUAL output of this sequence's
            // forward (MLX is lazy); nothing here measures graph building.
            let values = argmax.astype(Dtype::Float32, s)?.to_f32_vec(s)?;
            let token = values.first().copied().ok_or(MlxError(-978))? as i32;
            generated[i].push(token);
            current[i] = token;
            tokens += 1;
            if stop.is_some_and(|ids| ids.contains(&token)) {
                finished[i] = true;
                reasons[i] = "stop".to_string();
            } else if generated[i].len() >= reqs[i].max_tokens {
                finished[i] = true;
                reasons[i] = "max_tokens".to_string();
            }
        }
    }
    let decode_s = decode_clock.elapsed().as_secs_f64();

    Ok((
        BatchOutcome {
            completions: generated,
            stop_reasons: reasons,
        },
        BatchTiming {
            prefill_s,
            decode_s,
            tokens,
        },
    ))
}

/// The result of the decode-level batch-invariance check.
#[derive(Clone, Debug)]
pub struct InvarianceReport {
    /// True when every sequence produced exactly the sequential tokens.
    pub invariant: bool,
    /// The first divergence: `(sequence index, token index)`.
    pub first_divergence: Option<(usize, usize)>,
    /// Tokens compared (summed over the sequences that matched in length).
    pub compared_tokens: usize,
    /// Per-sequence verdict (same order as the requests).
    pub per_sequence: Vec<bool>,
}

/// Decode the same prompts SEQUENTIALLY and IN THE BATCH, and report
/// whether the token sequences match exactly.
///
/// This is the batch bookkeeping check: a shared cache, a shared offset or
/// a leaked stop token would make a sequence's output depend on its
/// neighbours, and this is where that shows up.
///
/// It is NOT the fused-batch precondition — a fused batch changes the
/// numerics of the matmuls, and that is measured separately by
/// [`probe_batch_numerics`].
pub fn check_batch_invariance(
    model: &Qwen3,
    reqs: &[BatchRequest],
    stop: Option<&[i32]>,
    s: Stream,
) -> MlxResult<InvarianceReport> {
    let batched = generate_greedy_batched(model, reqs, stop, s)?;
    let mut per_sequence = Vec::with_capacity(reqs.len());
    let mut first_divergence: Option<(usize, usize)> = None;
    let mut compared_tokens = 0usize;
    for (i, req) in reqs.iter().enumerate() {
        let sequential = model.generate_greedy(&req.prompt_ids, req.max_tokens, stop, s)?;
        // `generate_greedy` returns prompt ++ generated.
        let sequential_generated = &sequential[req.prompt_ids.len()..];
        let batched_generated = &batched.completions[i];
        let mut identical = sequential_generated.len() == batched_generated.len();
        if identical {
            for (j, (a, b)) in sequential_generated
                .iter()
                .zip(batched_generated.iter())
                .enumerate()
            {
                compared_tokens += 1;
                if a != b {
                    identical = false;
                    if first_divergence.is_none() {
                        first_divergence = Some((i, j));
                    }
                    break;
                }
            }
        } else if first_divergence.is_none() {
            first_divergence = Some((i, sequential_generated.len().min(batched_generated.len())));
        }
        per_sequence.push(identical);
    }
    Ok(InvarianceReport {
        invariant: first_divergence.is_none() && per_sequence.iter().all(|ok| *ok),
        first_divergence,
        compared_tokens,
        per_sequence,
    })
}

/// One row of a batch-numerics probe.
#[derive(Clone, Copy, Debug)]
pub struct NumericsProbe {
    /// How many rows the batched call carried.
    pub rows: usize,
    /// True when every batched row is BIT-identical to the single-row call.
    pub bit_identical: bool,
    /// The first differing element index (in the flattened output).
    pub first_divergence: Option<usize>,
    /// The largest absolute difference between the batched and the single
    /// row output.
    pub max_abs_diff: f32,
    /// The shape class the SINGLE-row call was dispatched under (the
    /// product's decode class).
    pub single_shape_class: &'static str,
    /// The shape class the BATCHED call was dispatched under.
    pub batched_shape_class: &'static str,
    /// The CONTROL for the kernel confound: two batch sizes that fall in the
    /// SAME shape class (so the same backend ran), compared row for row.
    /// `Some(true)` means the batch DIMENSION alone does not change the
    /// numbers, and any difference in `bit_identical` above is the KERNEL
    /// CLASS changing (e.g. the fused dequant-GEMV for m == 1 against the
    /// mlx-c path for m > 1), not batching per se.
    pub same_class_bit_identical: Option<bool>,
    /// The first differing element index of the same-class control.
    pub same_class_first_divergence: Option<usize>,
}

/// The two numerics probes that decide whether a fused batch could
/// reproduce a sequential decode.
#[derive(Clone, Debug, Default)]
pub struct BatchNumericsReport {
    /// The tied vocabulary projection (the checkpoint's `embed_tokens`).
    pub tied_projection: Option<NumericsProbe>,
    /// A real body layer's quantized GEMM (layer 0's `q_proj`).
    pub body_gemm: Option<NumericsProbe>,
}

/// Measure whether a BATCHED matmul changes the numbers relative to the
/// same row computed alone.
///
/// The single-row call is what a sequential decode does; the batched call
/// is what a fused batch would do. If the two disagree, a fused batched
/// decode is NOT token-identical to a sequential one, and every number
/// measured through it is a function of the batch size — a function of a
/// choice, not a measurement. That is why this probe exists.
///
/// The weights are the checkpoint's real quantized tensors and the calls go
/// through the TRUNK's binding table, so the dispatch (shape class and
/// backend) is the one the product would use. The activation is a
/// deterministic synthetic one: the probe measures NUMERICS, so the
/// activation's content does not matter, only its shape and dtype.
pub fn probe_batch_numerics(
    model: &Qwen3,
    model_dir: &Path,
    rows: usize,
    positions: usize,
    s: Stream,
) -> MlxResult<BatchNumericsReport> {
    let mut report = BatchNumericsReport::default();
    if rows < 1 || positions < 1 {
        return Ok(report);
    }
    let table = model.table();
    let st = SafetensorsFile::open(&model_dir.join("model.safetensors"))?;

    // ---- the tied vocabulary projection ----
    if let Some(embed) = load_probe_weight(&st, "model.embed_tokens") {
        let hidden = model.cfg.hidden_size;
        let row = synthetic_f32(hidden * positions, 0x51A7_0002);
        let x1 = Array::from_data_f32(&row, &[1, positions, hidden])?.astype(Dtype::BFloat16, s)?;
        let xb = Array::from_data_f32(&row.repeat(rows), &[rows, positions, hidden])?
            .astype(Dtype::BFloat16, s)?;
        let (o1, c1) = probe_matmul(table, &x1, &embed, model, s)?;
        let (ob, cb) = probe_matmul(table, &xb, &embed, model, s)?;
        let v1 = o1.astype(Dtype::Float32, s)?.to_f32_vec(s)?;
        let vb = ob.astype(Dtype::Float32, s)?.to_f32_vec(s)?;
        let cols = v1.len();
        let mut probe = compare_rows(&v1, &vb, rows, cols, c1, cb);
        // The same-class control: two batch sizes inside ONE shape class,
        // so the same backend ran for both.
        let (c2r, same) = same_class_control(table, &embed, model, hidden, positions, rows, s)?;
        probe.same_class_bit_identical = Some(c2r);
        probe.same_class_first_divergence = same;
        report.tied_projection = Some(probe);
    }

    // ---- a real body layer's quantized GEMM ----
    if let Some(q) = load_probe_weight(&st, "model.layers.0.self_attn.q_proj") {
        let k = model.cfg.hidden_size;
        let row = synthetic_f32(k * positions, 0x51A7_0001);
        let x1 = Array::from_data_f32(&row, &[1, positions, k])?.astype(Dtype::BFloat16, s)?;
        let xb = Array::from_data_f32(&row.repeat(rows), &[rows, positions, k])?
            .astype(Dtype::BFloat16, s)?;
        let (o1, c1) = probe_matmul(table, &x1, &q, model, s)?;
        let (ob, cb) = probe_matmul(table, &xb, &q, model, s)?;
        let v1 = o1.astype(Dtype::Float32, s)?.to_f32_vec(s)?;
        let vb = ob.astype(Dtype::Float32, s)?.to_f32_vec(s)?;
        let cols = v1.len();
        let mut probe = compare_rows(&v1, &vb, rows, cols, c1, cb);
        let (c2r, same) = same_class_control(table, &q, model, k, positions, rows, s)?;
        probe.same_class_bit_identical = Some(c2r);
        probe.same_class_first_divergence = same;
        report.body_gemm = Some(probe);
    }

    Ok(report)
}

/// The amortization probe's result: the cost of the tied projection and of
/// a body layer's GEMM stack, per batch dimension.
#[derive(Clone, Debug, Default)]
pub struct AmortizationReport {
    /// The batch dimensions probed, in the order requested.
    pub batches: Vec<usize>,
    /// Milliseconds for the tied vocabulary projection at each batch dim.
    pub projection_ms: Vec<f64>,
    /// Milliseconds for ONE body layer's quantized GEMM stack (q, k, v, o,
    /// gate, up, down) at each batch dim.
    pub body_layer_gemm_ms: Vec<f64>,
    /// The body's linear cost ESTIMATE at each batch dim (one layer's stack
    /// times the layer count). Attention and the norms are NOT included —
    /// they are not the weight-read term this probe is about.
    pub body_linear_estimate_ms: Vec<f64>,
    /// The amortization factor of the projection at each batch dim:
    /// `B * cost(1) / cost(B)`. `B` would be a perfect amortization; a
    /// number near `1` means the batch bought nothing.
    pub projection_amortization: Vec<f64>,
    /// The same factor for the body's linear estimate.
    pub body_linear_amortization: Vec<f64>,
    /// The WHOLE decode step's dominant cost at each batch dim (the body's
    /// linear estimate plus the tied projection). This is the number the
    /// lever turns on: it is what one decode step would cost if the batch
    /// were FUSED. Attention and the norms are excluded.
    pub whole_step_estimate_ms: Vec<f64>,
    /// The whole step's amortization factor: `B * step(1) / step(B)`. This
    /// is the PROJECTED aggregate throughput ratio a fused batch would buy
    /// (a projection from measured per-op costs, NOT a measured decode).
    pub whole_step_amortization: Vec<f64>,
    /// How many of the seven body GEMMs were measurable (a non-quantized
    /// tensor is skipped and reported here, never silently counted).
    pub measured_body_gems: usize,
    /// How many body GEMMs the layer stack is supposed to have.
    pub expected_body_gems: usize,
    /// The number of transformer layers.
    pub layers: usize,
    /// Whether the checkpoint's embedding table is quantized.
    pub embed_is_quantized: bool,
    /// The bytes one decode step reads for the tied embedding table — the
    /// memory a batch would have to amortize.
    pub projection_weight_bytes: u64,
    /// Rows of the tied embedding table (the vocabulary size).
    pub table_rows: usize,
}

/// Measure the cost of the tied vocabulary projection and of a body layer's
/// GEMM stack as a function of the batch dimension, at `[B, 1, H]`.
///
/// This is the LEVER probe: it answers "would a fused batch amortize the
/// weight read?" without pretending that a fused batch exists. Every timed
/// point forces the ACTUAL output (`eval()` + a stream sync) through the
/// trunk's own plan ops and binding table, so what is timed is execution,
/// not graph construction.
///
/// The body GEMM stack uses the checkpoint's real quantized weights for
/// layer 0; attention and the norms are NOT included.
pub fn probe_batch_amortization(
    model: &Qwen3,
    model_dir: &Path,
    batches: &[usize],
    positions: usize,
    reps: usize,
    s: Stream,
) -> MlxResult<AmortizationReport> {
    let table = model.table();
    let st = SafetensorsFile::open(&model_dir.join("model.safetensors"))?;
    let hidden = model.cfg.hidden_size;
    let positions = positions.max(1);
    let attn_dim = model.cfg.heads * model.cfg.head_dim;
    let inter = model.cfg.intermediate;
    let gemm_specs: Vec<(String, usize)> = vec![
        ("model.layers.0.self_attn.q_proj".to_string(), hidden),
        ("model.layers.0.self_attn.k_proj".to_string(), hidden),
        ("model.layers.0.self_attn.v_proj".to_string(), hidden),
        ("model.layers.0.self_attn.o_proj".to_string(), attn_dim),
        ("model.layers.0.mlp.gate_proj".to_string(), hidden),
        ("model.layers.0.mlp.up_proj".to_string(), hidden),
        ("model.layers.0.mlp.down_proj".to_string(), inter),
    ];
    let mut weights: Vec<(ProbeWeight, usize)> = Vec::new();
    for (name, in_dim) in &gemm_specs {
        if let Some(q) = load_probe_weight(&st, name) {
            weights.push((q, *in_dim));
        }
    }
    let embed = load_probe_weight(&st, "model.embed_tokens");

    let mut report = AmortizationReport {
        batches: batches.to_vec(),
        measured_body_gems: weights.len(),
        expected_body_gems: gemm_specs.len(),
        layers: model.cfg.layers,
        embed_is_quantized: matches!(embed, Some(ProbeWeight::Quant(_))),
        table_rows: model.cfg.vocab,
        ..AmortizationReport::default()
    };
    if let Some(e) = embed.as_ref() {
        report.projection_weight_bytes = e.bytes();
    }

    for &batch in batches {
        if batch == 0 {
            report.projection_ms.push(f64::NAN);
            report.body_layer_gemm_ms.push(f64::NAN);
            report.body_linear_estimate_ms.push(f64::NAN);
            report.projection_amortization.push(f64::NAN);
            report.body_linear_amortization.push(f64::NAN);
            report.whole_step_estimate_ms.push(f64::NAN);
            report.whole_step_amortization.push(f64::NAN);
            continue;
        }
        // ---- the tied vocabulary projection ----
        let projection_ms = match embed.as_ref() {
            Some(embed) => {
                let row = synthetic_f32(hidden * positions * batch, 0x51A7_0003);
                let x = Array::from_data_f32(&row, &[batch, positions, hidden])?
                    .astype(Dtype::BFloat16, s)?;
                timed_ms(
                    reps,
                    || probe_matmul(table, &x, embed, model, s).map(|(o, _)| o),
                    s,
                )?
            }
            None => f64::NAN,
        };
        report.projection_ms.push(projection_ms);

        // ---- one body layer's GEMM stack ----
        let mut layer_ms = 0.0f64;
        for (idx, (q, in_dim)) in weights.iter().enumerate() {
            let row = synthetic_f32(in_dim * positions * batch, 0x51A7_0100 + idx as u64);
            let x = Array::from_data_f32(&row, &[batch, positions, *in_dim])?
                .astype(Dtype::BFloat16, s)?;
            let ms = timed_ms(
                reps,
                || probe_matmul(table, &x, q, model, s).map(|(o, _)| o),
                s,
            )?;
            layer_ms += ms;
        }
        report.body_layer_gemm_ms.push(layer_ms);
        report
            .body_linear_estimate_ms
            .push(layer_ms * model.cfg.layers as f64);
        report
            .whole_step_estimate_ms
            .push(layer_ms * model.cfg.layers as f64 + projection_ms);
    }

    // The amortization factors, against the batch-1 baseline.
    if let Some(base_proj) = report.projection_ms.first().copied() {
        for (i, &batch) in report.batches.iter().enumerate() {
            let cost = report.projection_ms[i];
            report
                .projection_amortization
                .push(if cost > 0.0 && base_proj > 0.0 {
                    batch as f64 * base_proj / cost
                } else {
                    f64::NAN
                });
        }
    }
    if let Some(base_body) = report.body_linear_estimate_ms.first().copied() {
        for (i, &batch) in report.batches.iter().enumerate() {
            let cost = report.body_linear_estimate_ms[i];
            report
                .body_linear_amortization
                .push(if cost > 0.0 && base_body > 0.0 {
                    batch as f64 * base_body / cost
                } else {
                    f64::NAN
                });
        }
    }
    if let Some(base_step) = report.whole_step_estimate_ms.first().copied() {
        for (i, &batch) in report.batches.iter().enumerate() {
            let cost = report.whole_step_estimate_ms[i];
            report
                .whole_step_amortization
                .push(if cost > 0.0 && base_step > 0.0 {
                    batch as f64 * base_step / cost
                } else {
                    f64::NAN
                });
        }
    }
    Ok(report)
}

/// One projection/GEMM weight: affine-quantized (the 4-bit exports) or a
/// plain checkpoint tensor (the bf16 exports). The trunk's own `Weight`
/// enum is private to `qwen.rs`, so the probe carries its own.
enum ProbeWeight {
    Quant(QuantizedTensor),
    Plain(Array),
}

impl ProbeWeight {
    /// The weight's element count (packed u32 for the quantized case) and
    /// the bytes one decode step reads for it — the memory the batch would
    /// have to amortize.
    fn bytes(&self) -> u64 {
        match self {
            ProbeWeight::Quant(q) => {
                let count: usize = (0..q.w.ndim())
                    .map(|d| q.w.dim(d as i32) as usize)
                    .product();
                (count * 4) as u64
            }
            ProbeWeight::Plain(w) => {
                let count: usize = (0..w.ndim()).map(|d| w.dim(d as i32) as usize).product();
                (count * 2) as u64
            }
        }
    }
}

/// Load one weight as a probe weight: quantized when the checkpoint has
/// `.scales`/`.biases` siblings, plain otherwise (the same rule the trunk's
/// loader uses).
fn load_probe_weight(st: &SafetensorsFile, name: &str) -> Option<ProbeWeight> {
    if st.dtype_of(&format!("{name}.scales")).is_some() {
        st.take_quantized(name).ok().map(ProbeWeight::Quant)
    } else {
        st.take_any(&format!("{name}.weight"))
            .ok()
            .map(ProbeWeight::Plain)
    }
}

/// The same-shape-class control for the numerics probe.
///
/// Compares a batch of `rows` against a batch of 2 (or `rows`, whichever is
/// smaller but at least 2) — two batch sizes that land in the SAME shape
/// class, so the SAME backend ran for both. A `true` answer means the batch
/// DIMENSION alone does not change the numbers; it isolates the kernel
/// class as the only possible source of a difference in the main probe.
///
/// Returns `(identical, first_divergence)`.
fn same_class_control(
    table: &BindingTable,
    w: &ProbeWeight,
    model: &Qwen3,
    in_dim: usize,
    positions: usize,
    rows: usize,
    s: Stream,
) -> MlxResult<(bool, Option<usize>)> {
    let small = 2usize.min(rows.max(2));
    if rows <= small {
        return Ok((true, None));
    }
    let row = synthetic_f32(in_dim * positions, 0x51A7_0003);
    let xa = Array::from_data_f32(&row.repeat(rows), &[rows, positions, in_dim])?
        .astype(Dtype::BFloat16, s)?;
    let xb = Array::from_data_f32(&row.repeat(small), &[small, positions, in_dim])?
        .astype(Dtype::BFloat16, s)?;
    let (oa, _) = probe_matmul(table, &xa, w, model, s)?;
    let (ob, _) = probe_matmul(table, &xb, w, model, s)?;
    let va = oa.astype(Dtype::Float32, s)?.to_f32_vec(s)?;
    let vb = ob.astype(Dtype::Float32, s)?.to_f32_vec(s)?;
    let cols = vb.len() / small.max(1);
    if va.len() < small * cols {
        return Ok((false, Some(0)));
    }
    let mut identical = true;
    let mut first = None;
    for r in 0..small {
        for c in 0..cols {
            let a = va[r * cols + c];
            let b = vb[r * cols + c];
            if a.to_bits() != b.to_bits() {
                identical = false;
                if first.is_none() {
                    first = Some(r * cols + c);
                }
            }
        }
    }
    Ok((identical, first))
}

/// One quantized-or-plain matmul through the TRUNK's plan op and binding
/// table.
///
/// Returns the output array and the shape class the call was dispatched
/// under (the shape class decides the backend, so a probe that ignored it
/// would measure a different kernel than the product uses).
fn probe_matmul(
    table: &BindingTable,
    x: &Array,
    w: &ProbeWeight,
    model: &Qwen3,
    s: Stream,
) -> MlxResult<(Array, &'static str)> {
    match w {
        ProbeWeight::Quant(q) => {
            let op = Op::QuantizedMatmul {
                group_size: model.cfg.group_size,
                bits: model.cfg.bits,
                transpose: true,
            };
            let class = bindings::ShapeClass::classify(&op, &[x]);
            let node = Node {
                name: "q.batch.qmm".to_string(),
                group: "q.batch".to_string(),
                op,
                inputs: Vec::new(),
                dump: None,
            };
            let outs = bindings::eval(&node, &[x, &q.w, &q.scales, &q.biases], table, s)?;
            let out = outs.into_iter().next().ok_or(MlxError(-978))?;
            Ok((out, shape_class_name(class)))
        }
        ProbeWeight::Plain(w) => {
            // The trunk's plain path: transpose the weight, then a matmul.
            let op = Op::Matmul;
            let wt = w.transpose_axes(&[1, 0], s)?;
            let class = bindings::ShapeClass::classify(&op, &[x]);
            let node = Node {
                name: "q.batch.matmul".to_string(),
                group: "q.batch".to_string(),
                op,
                inputs: Vec::new(),
                dump: None,
            };
            let outs = bindings::eval(&node, &[x, &wt], table, s)?;
            let out = outs.into_iter().next().ok_or(MlxError(-978))?;
            Ok((out, shape_class_name(class)))
        }
    }
}

fn shape_class_name(class: bindings::ShapeClass) -> &'static str {
    use bindings::ShapeClass::*;
    match class {
        Constant => "constant",
        SkinnyGemm => "skinny_gemm",
        Gemv => "gemv",
        WideGemm => "wide_gemm",
        Attention => "attention",
        Elementwise => "elementwise",
        Reduction => "reduction",
        Shape => "shape",
        Gather => "gather",
        Generic => "generic",
    }
}

/// Time `f` `reps` times and keep the FASTEST run (the least thermally
/// contaminated estimate). The graph is rebuilt every rep so that `eval()`
/// cannot return a cached value, and the timer covers the op submission
/// plus the forced evaluation plus a stream sync.
fn timed_ms<F>(reps: usize, mut f: F, s: Stream) -> MlxResult<f64>
where
    F: FnMut() -> MlxResult<Array>,
{
    let mut best = f64::MAX;
    for _ in 0..reps.max(1) {
        let clock = std::time::Instant::now();
        let out = f()?;
        out.eval()?;
        crate::mlx::synchronize_stream(s)?;
        best = best.min(clock.elapsed().as_secs_f64() * 1000.0);
    }
    Ok(best)
}

/// Compare a single-row output against the same rows computed in a batch.
/// `single` holds `cols` values; `batched` holds `rows * cols` values.
fn compare_rows(
    single: &[f32],
    batched: &[f32],
    rows: usize,
    cols: usize,
    single_class: &'static str,
    batched_class: &'static str,
) -> NumericsProbe {
    let mut bit_identical = batched.len() >= rows * cols;
    let mut first_divergence: Option<usize> = None;
    let mut max_abs_diff = 0.0f32;
    if !bit_identical {
        return NumericsProbe {
            rows,
            bit_identical: false,
            first_divergence: Some(0),
            max_abs_diff,
            single_shape_class: single_class,
            batched_shape_class: batched_class,
            same_class_bit_identical: None,
            same_class_first_divergence: None,
        };
    }
    for r in 0..rows {
        for c in 0..cols {
            let a = single[c];
            let b = batched[r * cols + c];
            let diff = (a - b).abs();
            if diff > max_abs_diff {
                max_abs_diff = diff;
            }
            if a.to_bits() != b.to_bits() {
                bit_identical = false;
                if first_divergence.is_none() {
                    first_divergence = Some(r * cols + c);
                }
            }
        }
    }
    NumericsProbe {
        rows,
        bit_identical,
        first_divergence,
        max_abs_diff,
        single_shape_class: single_class,
        batched_shape_class: batched_class,
        same_class_bit_identical: None,
        same_class_first_divergence: None,
    }
}

/// A deterministic synthetic activation (values in [-1, 1)).
fn synthetic_f32(n: usize, seed: u64) -> Vec<f32> {
    let mut state = seed | 1;
    let mut out = Vec::with_capacity(n);
    for _ in 0..n {
        state = state
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        let unit = ((state >> 33) as f32) / (u32::MAX as f32);
        out.push(unit * 2.0 - 1.0);
    }
    out
}
