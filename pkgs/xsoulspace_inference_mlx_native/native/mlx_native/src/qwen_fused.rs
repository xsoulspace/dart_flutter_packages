//! The FUSED batch — the acceleration program's Tier A (the acceleration
//! RESULTS §1.5/1.6 reformulation of L-G4's precondition).
//!
//! `qwen.rs` used to pin the batch dim to `1` in every reshape, the KV
//! allocation and the cache write, and the tied embedding was private. The
//! four-part change (recorded 2026-10-21, built here):
//!   (a) the batch dim comes from `tokens.dim(0)` — reshapes, KV buffers,
//!       cache write and read views are batch-generic;
//!   (b) the KV buffers are allocated with that batch dim
//!       (`KvCache::reserve(batch, ..)`);
//!   (c) heterogeneous prompts are LEFT-PADDED to a common length and a
//!       BOOL keep-mask is passed to `Op::Sdp` (the mask path already
//!       existed for laya). Left-padding is mathematically exact for a
//!       RoPE transformer — attention reads only RELATIVE positions
//!       (q_i·k_j depends on i-j), and a uniform shift preserves every
//!       relative distance — so the only correctness requirement is that
//!       pad positions are never attended, which is what the keep-mask
//!       enforces at prefill (causal ∩ keep) and at every decode step;
//!   (d) the tied embedding is exposed (`Qwen3::lm_head`) so batched
//!       hidden states project on the same weights.
//!
//! THE BAR (reformulated L-G4 precondition, not the retired bit-identity
//! bar): (1) decision-level invariance — the label does not move with the
//! batch size or the row's position in it; (2) no short-row defect on the
//! heterogeneous (left-padded) path. Bit-level divergence across a batch
//! dimension is a MEASURED, BOUNDED low-precision artifact (0.0625 body /
//! 0.0239 projection on the real quantized weights) and is reported beside
//! every fused number, never hidden. The gate that proves both is
//! `tests/qwen_fused_batch_gate.rs`.

use crate::mlx::{Array, Dtype, Stream};
use crate::qwen::{KvCache, Qwen3};
use crate::qwen_batch::{BatchOutcome, BatchRequest, BatchTiming};
use crate::qwen_rank::{eos_id, primary_score, LabelScore, RankOptions, RankOutcome};
use crate::mlx::{MlxError, MlxResult};

/// The pad token id used for left-padding. Any in-vocabulary id works —
/// the keep-mask makes pads un-attendable, so the value never reaches a
/// real query — but it must be a legal id (0 is every vocab's first row).
pub const PAD_ID: i32 = 0;

/// The per-sequence geometry of one fused batch.
pub struct FusedBatchPlan {
    /// Left-padded token rows [B, Lmax].
    pub tokens: Vec<i32>,
    /// keep[b][j]: position j of row b is a REAL token (not pad).
    pub keep: Vec<Vec<bool>>,
    pub l_max: usize,
    pub batch: usize,
    /// False when every row is already Lmax long — no pads, so the batch
    /// can run the UNMASKED native-causal path (numerically the same
    /// kernels the sequential path uses; the explicit-mask sdp is a
    /// different kernel and carries its own low-precision floor).
    pub has_padding: bool,
}

/// Build the left-padded rows and the keep rows for `reqs`.
pub fn plan_fused_batch(reqs: &[BatchRequest]) -> MlxResult<FusedBatchPlan> {
    if reqs.is_empty() {
        return Err(MlxError(-978));
    }
    for r in reqs {
        // A 1-token prompt would have NO real position in the all-but-last
        // prefill (its only token rides the decode loop), leaving that row's
        // prefill keep-mask all-false. Degenerate — refuse loudly.
        if r.prompt_ids.len() < 2 {
            return Err(MlxError(-978));
        }
    }
    let batch = reqs.len();
    let l_max = reqs
        .iter()
        .map(|r| r.prompt_ids.len())
        .max()
        .expect("checked non-empty");
    let mut tokens = vec![PAD_ID; batch * l_max];
    let mut keep = vec![vec![false; l_max]; batch];
    for (b, r) in reqs.iter().enumerate() {
        let pad = l_max - r.prompt_ids.len();
        tokens[b * l_max + pad..b * l_max + l_max].copy_from_slice(&r.prompt_ids);
        for j in pad..l_max {
            keep[b][j] = true;
        }
    }
    let has_padding = reqs.iter().any(|r| r.prompt_ids.len() < l_max);
    Ok(FusedBatchPlan {
        tokens,
        keep,
        l_max,
        batch,
        has_padding,
    })
}

/// The prefill attention mask [B, 1, Lmax, Lmax]: entry (b, 0, i, j) is
/// true iff position j of row b is REAL and j <= i (causal ∩ keep). The
/// 4-input `Op::Sdp` path applies the bool array INSTEAD of the causal
/// mode, so causality must be baked in here.
pub fn prefill_mask(plan: &FusedBatchPlan, s: Stream) -> MlxResult<Array> {
    let (b, l) = (plan.batch, plan.l_max);
    let mut data = vec![0u8; b * l * l];
    for (bi, row) in plan.keep.iter().enumerate() {
        for i in 0..l {
            for j in 0..l {
                if j <= i && row[j] {
                    data[bi * l * l + i * l + j] = 1;
                }
            }
        }
    }
    let _ = s;
    Array::from_data_bool(&data, &[b, 1, l, l])
}

/// The decode keep-mask window [B, 1, 1, window]: position j of row b is
/// attendable iff j >= its pad start. Positions beyond the current offset
/// are sliced away before the mask reaches the kernel, so their value is
/// irrelevant — `true` keeps the slices trivial.
pub fn decode_mask_window(plan: &FusedBatchPlan, window: usize, s: Stream) -> MlxResult<Array> {
    let (b, l) = (plan.batch, plan.l_max);
    let mut data = vec![1u8; b * window];
    for (bi, row) in plan.keep.iter().enumerate() {
        let pad = row.iter().position(|&k| k).unwrap_or(l);
        for j in 0..pad.min(window) {
            data[bi * window + j] = 0;
        }
    }
    let _ = s;
    Array::from_data_bool(&data, &[b, 1, 1, window])
}

/// Greedy decode of a batch through the FUSED path: ONE left-padded
/// batched prefill, then ONE [B, 1] forward per decode step with the
/// sliced keep-mask. The weight read IS amortized across the batch — this
/// is the lever the lockstep control in `qwen_batch` deliberately is not.
///
/// Finished sequences keep their slot (their last token is re-fed; their
/// outputs are dropped) — a static batch, the same policy the product's
/// batch-isolation test assumes.
pub fn generate_greedy_fused_timed(
    model: &Qwen3,
    reqs: &[BatchRequest],
    stop: Option<&[i32]>,
    s: Stream,
) -> MlxResult<(BatchOutcome, BatchTiming)> {
    if reqs.is_empty() {
        return Err(MlxError(-978));
    }
    let n = reqs.len();
    let plan = plan_fused_batch(reqs)?;
    let max_steps = reqs.iter().map(|r| r.max_tokens).max().unwrap_or(0);
    let window = plan.l_max + max_steps;

    let mut cache = KvCache::new(model.cfg.layers);
    cache.reserve(
        model.table(),
        plan.batch,
        model.cfg.kv_heads,
        model.cfg.head_dim,
        window,
        s,
    )?;

    // ---- prefill: ONE batched forward over all-but-the-last token — the
    // SAME split the sequential greedy uses (the last prompt token rides
    // the decode loop; feeding it twice would duplicate it in the attention
    // window). Unpadded batches run the UNMASKED native-causal path — the
    // same kernels the sequential path uses — and only padded batches pay
    // for the explicit keep-mask (a different sdp kernel, own floor).
    let prefill_clock = std::time::Instant::now();
    let prefill_len = plan.l_max - 1;
    let mut prefill_tokens = Vec::with_capacity(plan.batch * prefill_len);
    for b in 0..plan.batch {
        prefill_tokens.extend_from_slice(&plan.tokens[b * plan.l_max..b * plan.l_max + prefill_len]);
    }
    let tokens = Array::from_data_i32(&prefill_tokens, &[plan.batch, prefill_len])?;
    let hidden = if plan.has_padding {
        let mut trimmed = FusedBatchPlan {
            tokens: prefill_tokens.clone(),
            keep: plan.keep.iter().map(|r| r[..prefill_len].to_vec()).collect(),
            l_max: prefill_len,
            batch: plan.batch,
            has_padding: true,
        };
        // Keep rows may now be all-false ONLY for rows whose every real
        // token is the prompt's last — impossible: prompts are >= 2 tokens
        // and the last is excluded, so every row has >= 1 real position
        // here (its first real token).
        let pmask = prefill_mask(&trimmed, s)?;
        trimmed.has_padding = plan.has_padding;
        model.forward_masked(&tokens, &mut cache, &pmask, false, s)?
    } else {
        model.forward_hidden(&tokens, &mut cache, s)?
    };
    // MLX is lazy: force the real prefill so the decode clock is decode.
    hidden.eval()?;
    let prefill_s = prefill_clock.elapsed().as_secs_f64();

    // ---- decode: one [B, 1] forward per step, keep-mask sliced to the
    // current attended length ----
    let decode_clock = std::time::Instant::now();
    let dmask = if plan.has_padding {
        Some(decode_mask_window(&plan, window, s)?)
    } else {
        None
    };
    let mut current: Vec<i32> = reqs
        .iter()
        .map(|r| r.prompt_ids[r.prompt_ids.len() - 1])
        .collect();
    let mut generated: Vec<Vec<i32>> = vec![Vec::new(); n];
    let mut reasons: Vec<String> = vec!["max_tokens".to_string(); n];
    let mut finished: Vec<bool> = reqs.iter().map(|r| r.max_tokens == 0).collect();
    let mut tokens_counter = 0usize;

    for _ in 0..max_steps {
        let step = Array::from_data_i32(&current, &[n, 1])?;
        let logits = match &dmask {
            Some(dm) => {
                // The sdp window is offset + l: the step's OWN key is
                // written and attended in the same forward, so the mask
                // must cover it too.
                let mask_len = cache.offset + 1;
                let mask_view =
                    dm.slice(&[0, 0, 0, 0], &[n as i32, 1, 1, mask_len as i32], &[1, 1, 1, 1], s)?;
                model.forward_masked(&step, &mut cache, &mask_view, true, s)?
            }
            None => model.step_logits(&step, &mut cache, crate::qwen::qwen_plan_mode(), s)?,
        };
        // [B, 1, V] -> argmax -> one readback for the WHOLE batch (the
        // forced readback is what makes the timing real, PYTHON-BOUNDARY
        // §1 and the 28.7x lesson).
        let next = logits.argmax_axis(-1, false, s)?;
        let values = next.astype(Dtype::Float32, s)?.to_f32_vec(s)?;
        if values.len() < n {
            return Err(MlxError(-978));
        }
        for i in 0..n {
            if finished[i] {
                // Frozen slot: keep feeding its last token so the batch's
                // shapes stay rectangular; nothing downstream reads it.
                continue;
            }
            let token = values[i] as i32;
            generated[i].push(token);
            current[i] = token;
            tokens_counter += 1;
            if stop.is_some_and(|ids| ids.contains(&token)) {
                finished[i] = true;
                reasons[i] = "stop".to_string();
            } else if generated[i].len() >= reqs[i].max_tokens {
                finished[i] = true;
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
            tokens: tokens_counter,
        },
    ))
}

pub fn generate_greedy_fused(
    model: &Qwen3,
    reqs: &[BatchRequest],
    stop: Option<&[i32]>,
    s: Stream,
) -> MlxResult<BatchOutcome> {
    Ok(generate_greedy_fused_timed(model, reqs, stop, s)?.0)
}

// ---- the fused ranker: the K candidate chunks in ONE forward ----

/// Rank the legal labels for `prompt` with the candidate scorings FUSED:
/// every (prompt + boundary + label) continuation is one row of a single
/// right-padded batch (chunks share the same start offset, so RIGHT
/// padding keeps every real token at its true position and the kernel's
/// native causal mask already protects each row's real queries from
/// another row's pad tail). Same tokenization law as the sequential
/// ranker (qwen_rank): the scored span is the (prompt+label)-minus-prefix
/// continuation, sum- and mean-normalized.
pub fn rank_labels_fused(
    model: &Qwen3,
    tokenizer: &crate::bpe::ByteLevelBpe,
    prompt: &str,
    labels: &[&str],
    opts: RankOptions,
    s: Stream,
) -> MlxResult<RankOutcome> {
    let mut outcome = RankOutcome {
        label: None,
        logprobs: Vec::new(),
        ranked: Vec::new(),
        scores: Vec::new(),
        normalization: opts.normalization,
        boundary: opts.boundary,
        prefix_tokens: 0,
        boundary_mismatches: 0,
    };
    if labels.is_empty() {
        return Ok(outcome);
    }

    // 1. tokenize every (prompt + boundary + label) concatenation.
    struct Row {
        label: String,
        continuation: String,
        full: Vec<u32>,
    }
    let mut rows: Vec<Row> = Vec::with_capacity(labels.len());
    for &label in labels {
        let continuation = opts.boundary.continuation(label);
        let joined = format!("{prompt}{continuation}");
        let full = tokenizer.encode(&joined).map_err(|_| MlxError(-990))?;
        rows.push(Row {
            label: label.to_string(),
            continuation,
            full,
        });
    }

    // 2. the shared prefix (any non-empty candidate is the reference).
    let base_full: Vec<u32> = rows
        .iter()
        .find(|r| !r.full.is_empty())
        .map(|r| r.full.clone())
        .unwrap_or_default();
    let mut shared = base_full.len();
    for r in &rows {
        if r.full.is_empty() {
            continue;
        }
        shared = shared.min(crate::qwen_rank::common_prefix_len(&base_full, &r.full));
    }
    if shared == 0 {
        return Err(MlxError(-991));
    }
    outcome.prefix_tokens = shared;

    // 3. the scored span + honesty checks (per row).
    let mut scores: Vec<LabelScore> = Vec::with_capacity(rows.len());
    for r in &rows {
        if r.full.is_empty() {
            scores.push(LabelScore {
                label: r.label.clone(),
                continuation: r.continuation.clone(),
                scored_text: String::new(),
                tokens: Vec::new(),
                per_token_logprob: Vec::new(),
                sum_logprob: f32::NEG_INFINITY,
                mean_logprob: f32::NEG_INFINITY,
                boundary_mismatch: true,
                empty: true,
                eos_prob_first: None,
                eos_dominates: false,
            });
            outcome.boundary_mismatches += 1;
            continue;
        }
        let tokens: Vec<u32> = r.full[shared..].to_vec();
        let scored_text = tokenizer.decode(&tokens).unwrap_or_default();
        let boundary_mismatch = scored_text != r.continuation;
        if boundary_mismatch {
            outcome.boundary_mismatches += 1;
        }
        scores.push(LabelScore {
            label: r.label.clone(),
            continuation: r.continuation.clone(),
            scored_text,
            tokens: tokens.clone(),
            per_token_logprob: Vec::new(),
            sum_logprob: 0.0,
            mean_logprob: 0.0,
            boundary_mismatch,
            empty: false,
            eos_prob_first: None,
            eos_dominates: false,
        });
    }

    let k = rows.iter().filter(|r| !r.full.is_empty()).count();
    if k == 0 {
        outcome.scores = scores;
        return Ok(outcome);
    }
    let max_tail = rows
        .iter()
        .map(|r| r.full.len().saturating_sub(shared))
        .max()
        .unwrap_or(0);
    let last_shared: i32 = base_full[shared - 1] as i32;

    // 4. the shared prefix, computed ONCE at [1, prefill_len] (the SAME
    // numerics and cost as the sequential ranker's prefix), then FANNED
    // OUT to k identical batch rows (one concat per layer) so the batched
    // candidate forward amortizes the weight read without re-paying the
    // prefix k times. (The first build repeated the prefix on every row of
    // a [K, prefill_len] prefill and LOST 1.26-1.29x to the sequential
    // ranker — measured, recorded.)
    let mut cache = KvCache::new(model.cfg.layers);
    let prefill_len = shared - 1;
    if prefill_len > 0 {
        cache.reserve(
            model.table(),
            1,
            model.cfg.kv_heads,
            model.cfg.head_dim,
            prefill_len + max_tail + 1,
            s,
        )?;
        let prefix: Vec<i32> = base_full[..prefill_len].iter().map(|&t| t as i32).collect();
        let arr = Array::from_data_i32(&prefix, &[1, prefill_len])?;
        let hidden = model.forward_hidden(&arr, &mut cache, s)?;
        hidden.eval()?; // force: the batch forward measures, not defers
    }
    let mut cache = cache.expanded_to_batch(k, model.table(), s)?;

    // 5. ONE right-padded candidate forward: row r = [last_shared] +
    // tail[..m-1], positions 0..m-1 of the batch window. Native causal
    // protects every real query from the pad tails (pads sit on the RIGHT,
    // and a real query at position j < m only attends keys <= j — its own
    // row's real keys).
    let mut batch_tokens = vec![0i32; k * max_tail];
    let mut live: Vec<usize> = Vec::with_capacity(k); // batch row -> score index
    {
        let mut ridx = 0usize;
        for (si, r) in rows.iter().enumerate() {
            if r.full.is_empty() {
                continue;
            }
            let tail: Vec<u32> = r.full[shared..].to_vec();
            let m = tail.len();
            let mut chunk = Vec::with_capacity(m);
            chunk.push(last_shared);
            for &t in &tail[..m - 1] {
                chunk.push(t as i32);
            }
            batch_tokens[ridx * max_tail..ridx * max_tail + m].copy_from_slice(&chunk);
            live.push(si);
            ridx += 1;
        }
    }
    let arr = Array::from_data_i32(&batch_tokens, &[k, max_tail])?;
    let logits = model.step_logits(&arr, &mut cache, crate::qwen::qwen_plan_mode(), s)?;
    logits.eval()?;
    let vocab = logits.dim(2);

    let eos = eos_id(tokenizer);
    for (row_i, &si) in live.iter().enumerate() {
        let r = &rows[si];
        let tail: Vec<u32> = r.full[shared..].to_vec();
        let m = tail.len();
        // Row slice → [1, m, V] view; position_logprobs reads it eagerly.
        let row_logits = logits.slice(
            &[row_i as i32, 0, 0],
            &[row_i as i32 + 1, m as i32, vocab as i32],
            &[1, 1, 1],
            s,
        )?;
        let (per_token, eos_prob_first) =
            crate::qwen_rank::position_logprobs(&row_logits, &tail, eos, s)?;
        let sum: f32 = per_token.iter().sum();
        let mean = if per_token.is_empty() {
            f32::NEG_INFINITY
        } else {
            sum / per_token.len() as f32
        };
        let eos_dominates = match (eos_prob_first, per_token.first()) {
            (Some(p), Some(&first)) => p > first,
            _ => false,
        };
        let score = &mut scores[si];
        score.per_token_logprob = per_token;
        score.sum_logprob = sum;
        score.mean_logprob = mean;
        score.eos_prob_first = eos_prob_first;
        score.eos_dominates = eos_dominates;
    }

    // 6. rank (the sequential ranker's own law).
    for sc in &scores {
        outcome.logprobs.push((sc.label.clone(), primary_score(sc, opts.normalization)));
    }
    let mut order: Vec<usize> = (0..scores.len()).collect();
    order.sort_by(|&a, &b| {
        primary_score(&scores[b], opts.normalization)
            .partial_cmp(&primary_score(&scores[a], opts.normalization))
            .unwrap_or(std::cmp::Ordering::Equal)
            .then(a.cmp(&b))
    });
    outcome.ranked = order.iter().map(|&i| scores[i].label.clone()).collect();
    outcome.label = outcome.ranked.first().cloned();
    outcome.scores = scores;
    Ok(outcome)
}
