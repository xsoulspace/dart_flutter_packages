//! L-G6 — RANK the legal labels instead of GENERATING free text.
//!
//! The lane's task is a CLOSED-VOCABULARY classification: the model must
//! answer with exactly one of N legal labels. Today it GENERATES free text
//! and the scorer then checks whether the stripped completion EQUALS a
//! label. The failure mode that follows ("outside the label set") is not a
//! scoring bug — it is a property of asking a language model to *spell* a
//! label instead of *choosing* one. Ranking removes it BY CONSTRUCTION: the
//! model never emits a label, so it cannot emit an illegal one.
//!
//! The frozen gate (MTP-GATES.md Part 4, L-G6) is
//! `ranked(base) >= untagged_adapter_accuracy - 0.05` on BOTH tasks.
//!
//! # What this module computes
//!
//! For a prompt and a legal label set, the CONTINUATION log-probability of
//! each label is
//!
//! ```text
//! log P(label | prompt) = sum over the label's tokens t of log P(t | prompt, t_<i)
//! ```
//!
//! and the answer is the argmax over the legal labels. Two normalizations
//! are reported for every candidate (see [`LengthNormalization`]):
//!
//! * `Sum`   — the raw sequence log-probability. It is systematically
//!   BIASED TOWARD SHORT LABELS: every extra token multiplies the score by
//!   a factor < 1, and this lane's label sets mix one-token labels
//!   (`abstain`) with three-token labels (`outside_workspace`).
//! * `Mean`  — the per-token (length-normalized) log-probability. It removes
//!   the token-count bias, and it is what the gate's phrase "length
//!   normalized" means. It is the DEFAULT here.
//!
//! RECOMMENDATION: `Mean` for the gate, with `Sum` reported beside it, and
//! the disagreement count between the two reported per run. The mean is the
//! right primary because the label sets here differ in length by design
//! (the veto task's four labels span 1–3 tokens), so a sum-weighted score
//! measures label LENGTH as much as it measures label FIT. The mean's own
//! bias is real and is NOT hidden: it rewards a label whose individual
//! tokens are individually predictable (a one-token label is scored by a
//! single, well-calibrated term). The unbiased alternative — a
//! domain-conditional PMI, i.e. subtracting the label's unconditional
//! log-probability — is NOT implemented here; it is named as the honest
//! next step rather than silently approximated.
//!
//! # The tokenization boundary (a real trap, handled explicitly)
//!
//! A label does not tokenize the same way after a space, after a newline,
//! and after nothing, and Qwen's byte-level BPE may absorb the leading
//! space into the label's first token. So the scored string is a PARAMETER
//! ([`ContinuationBoundary`]) and never an accident:
//!
//! * `NoSpace` (DEFAULT) — the continuation is the bare label. This is the
//!   boundary the lane's own evidence supports: the cached completions of
//!   the base and adapter arms (`bench/nursery/experiments/
//!   adapter-conditioning-2026-10-21/completions/*.jsonl`) are BARE labels
//!   (`allow_once`, not ` allow_once`), and the eval prompt ends with
//!   `Answer:` — a pre-token boundary in its own right, so the bare label
//!   still splits cleanly out of the concatenation. Adding a space would
//!   score a string the model is never asked to produce.
//! * `LeadingSpace` — the continuation is `" " + label`. This is the
//!   "word-boundary space" convention `mlx_lm`'s `loglikelihood` recommends,
//!   and it is the right choice for a prompt that ends with a WORD. It is
//!   offered for comparison, not as the default, because it changes the
//!   label's first token.
//! * `Newline` — the continuation is `"\n" + label`.
//!
//! Whichever boundary is used, the scored string is the CONCATENATION
//! (`prompt + continuation`), not the label's own tokenization: the token
//! span that is scored is the tail of `tokenize(prompt + continuation)`. That
//! tail is only well defined if the concatenation's tokenization ends with
//! the continuation's tokenization. When it does not — which happens when
//! the prompt ends in a letter/digit and the continuation does not start
//! with a separator, so the last pre-token of the prompt MERGES with the
//! first pre-token of the continuation — the tail no longer decodes to the
//! label. This module does NOT hide that: the label's `boundary_mismatch`
//! flag is set, the string that was actually scored is reported in
//! `scored_text`, and the bench counts the mismatches. A candidate whose
//! scored string is not the label is a DIFFERENT measurement and must not
//! be read as the label's score.
//!
//! # The forward-pass structure (and why it is cheap)
//!
//! The candidates are NOT scored by N independent prefills of the whole
//! sequence. The prompt is prefilled ONCE (KV only, no vocabulary
//! projection) and each candidate is then scored by ONE short forward over
//! `[last prompt token] + label tokens` — the vocabulary projection runs
//! over the candidate's own few tokens, never over the prompt's hundreds.
//!
//! The KV cache is REUSED across candidates by rewinding `cache.offset` to
//! the end of the shared prefix: the next candidate's forward overwrites the
//! discarded rows before anything reads them (the KV buffers are written
//! with in-place slice updates at `[offset..offset+n]`, and reads view
//! `[..offset]` — the same rewind the speculative-decode path already
//! relies on, see `qwen.rs::generate_greedy_speculative`).
//!
//! TWO CAVEATS, both stated rather than hidden:
//!
//! * The shared prefix's LAST token is computed inside each candidate's
//!   chunk, not inside the prompt's prefill. The math is identical (the
//!   chunk is causal), but the attention kernel tiles a 2–5 position query
//!   differently from a whole-prompt prefill, so the last hidden — and
//!   therefore the first label token's log-probability — can differ in the
//!   last bf16 bits from a single whole-prompt prefill.
//! * The candidates are NOT batched. The native engine's forward hardcodes
//!   batch 1 (`reshape([1, l, heads, d])` in `qwen.rs`), so each candidate
//!   costs one short forward. Batching the candidates would need a change
//!   in `qwen.rs`, which is outside this unit's scope. The cost claim of
//!   L-G6 must therefore be read as "ranking WITHOUT batching", which is
//!   the pessimistic direction for the ranking arm.
//!
//! # MLX IS LAZY
//!
//! Every array here is lazy until it is forced. The log-probability readback
//! (`to_f32_vec`) forces the real logits, so a timed ranking call measures
//! EXECUTION, not graph construction. A dummy eval in this lane measured a
//! 28.7x error (2026-10-20).
//!
//! # EOS inside the label span
//!
//! The model may prefer to STOP where a label starts (the first scored
//! position may put more mass on EOS than on the label's first token). That
//! is a real failure mode of the GENERATION path, and it is reported rather
//! than hidden: `eos_prob_first` is the model's EOS probability at the
//! first scored position and `eos_dominates` says whether EOS beat the
//! label's first token there. Such candidates are NOT dropped: dropping
//! them would bias the comparison against generation, which also stops at
//! EOS. They are FLAGGED, and the bench counts them.

use crate::bpe::ByteLevelBpe;
use crate::mlx::{Array, Dtype, MlxError, MlxResult, Stream};
use crate::qwen::{KvCache, Qwen3};

/// How the label is joined to the prompt to form the scored continuation.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ContinuationBoundary {
    /// The bare label. DEFAULT: the lane's cached completions are bare
    /// labels, and the eval prompt ends on a pre-token boundary.
    NoSpace,
    /// `" " + label` — the "word-boundary space" convention.
    LeadingSpace,
    /// `"\n" + label`.
    Newline,
}

impl ContinuationBoundary {
    /// The exact string that is scored as the continuation of the prompt.
    pub fn continuation(&self, label: &str) -> String {
        match self {
            ContinuationBoundary::LeadingSpace => format!(" {label}"),
            ContinuationBoundary::NoSpace => label.to_string(),
            ContinuationBoundary::Newline => format!("\n{label}"),
        }
    }

    /// A stable short name for reports and JSON.
    pub fn as_str(&self) -> &'static str {
        match self {
            ContinuationBoundary::LeadingSpace => "space",
            ContinuationBoundary::NoSpace => "none",
            ContinuationBoundary::Newline => "newline",
        }
    }

    /// Parse the CLI spelling (`space` / `none` / `newline`).
    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "space" | "leading_space" => Some(ContinuationBoundary::LeadingSpace),
            "none" | "no_space" => Some(ContinuationBoundary::NoSpace),
            "newline" => Some(ContinuationBoundary::Newline),
            _ => None,
        }
    }
}

/// How the per-token log-probabilities are aggregated into a label score.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LengthNormalization {
    /// The raw sum of the label's token log-probabilities (biased toward
    /// short labels).
    Sum,
    /// The per-token mean of the label's token log-probabilities.
    Mean,
}

impl LengthNormalization {
    pub fn as_str(&self) -> &'static str {
        match self {
            LengthNormalization::Sum => "sum",
            LengthNormalization::Mean => "mean",
        }
    }

    /// Parse the CLI spelling (`sum` / `mean`).
    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "sum" => Some(LengthNormalization::Sum),
            "mean" => Some(LengthNormalization::Mean),
            _ => None,
        }
    }
}

/// The knobs of a ranking run. Both are reported in the outcome, so a run
/// is never read as a different measurement than it was.
#[derive(Clone, Copy, Debug)]
pub struct RankOptions {
    /// The normalization the argmax is taken under.
    pub normalization: LengthNormalization,
    /// The tokenization boundary of the scored continuation.
    pub boundary: ContinuationBoundary,
}

impl Default for RankOptions {
    fn default() -> Self {
        RankOptions {
            normalization: LengthNormalization::Mean,
            boundary: ContinuationBoundary::NoSpace,
        }
    }
}

/// One legal label's score, with everything needed to audit it.
#[derive(Clone, Debug)]
pub struct LabelScore {
    /// The legal label, verbatim.
    pub label: String,
    /// The continuation string that was requested (label + boundary).
    pub continuation: String,
    /// The string the scored token span actually decodes to. When this
    /// differs from `continuation`, the boundary merged and the score is
    /// NOT the score of `label` (see `boundary_mismatch`).
    pub scored_text: String,
    /// The token ids of the scored span.
    pub tokens: Vec<u32>,
    /// The per-token log-probabilities of the scored span.
    pub per_token_logprob: Vec<f32>,
    /// The summed log-probability.
    pub sum_logprob: f32,
    /// The per-token mean log-probability.
    pub mean_logprob: f32,
    /// True when the scored span does not decode to the requested
    /// continuation (a tokenization-boundary merge).
    pub boundary_mismatch: bool,
    /// True when the label tokenized to nothing (an empty legal label).
    pub empty: bool,
    /// The model's EOS probability at the FIRST scored position, when the
    /// checkpoint's EOS id is known.
    pub eos_prob_first: Option<f32>,
    /// True when EOS beat the label's first token at the first scored
    /// position — the model wanted to stop where the label starts.
    pub eos_dominates: bool,
}

/// The result of ranking a legal label set.
#[derive(Clone, Debug)]
pub struct RankOutcome {
    /// The argmax label under the run's normalization. `None` when the
    /// legal label set is empty.
    pub label: Option<String>,
    /// Per candidate label, in the order the labels were given, with the
    /// score under the run's PRIMARY normalization.
    pub logprobs: Vec<(String, f32)>,
    /// The labels ordered by descending primary score.
    pub ranked: Vec<String>,
    /// Every candidate's full audit record.
    pub scores: Vec<LabelScore>,
    /// The normalization the argmax was taken under.
    pub normalization: LengthNormalization,
    /// The boundary the continuation was formed with.
    pub boundary: ContinuationBoundary,
    /// How many tokens the shared prefix had.
    pub prefix_tokens: usize,
    /// How many candidates hit a tokenization-boundary mismatch.
    pub boundary_mismatches: usize,
}

/// The EOS-ish added tokens of the Qwen3 checkpoint, in probe order.
pub const EOS_CANDIDATES: [&str; 2] = ["<|endoftext|>", "<|im_end|>"];

/// The first EOS-ish token id the tokenizer knows, if any.
pub fn eos_id(tokenizer: &ByteLevelBpe) -> Option<u32> {
    EOS_CANDIDATES.iter().find_map(|c| tokenizer.added_id(c))
}

/// Rank the legal labels for `prompt` with the default options
/// (`Mean` normalization, `NoSpace` boundary).
pub fn rank_labels(
    model: &Qwen3,
    tokenizer: &ByteLevelBpe,
    prompt: &str,
    labels: &[&str],
    s: Stream,
) -> MlxResult<RankOutcome> {
    rank_labels_with(model, tokenizer, prompt, labels, RankOptions::default(), s)
}

/// Rank the legal labels for `prompt`.
///
/// The prompt is prefilled once; every legal label is then scored as a
/// continuation of that shared prefix. Both the sum and the mean
/// log-probability are reported for every candidate, and the argmax is
/// taken under `opts.normalization`.
pub fn rank_labels_with(
    model: &Qwen3,
    tokenizer: &ByteLevelBpe,
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

    // ---- 1. tokenize the prompt and every (prompt + label) concatenation ----
    let mut plans: Vec<Plan> = Vec::with_capacity(labels.len());
    for &label in labels {
        let continuation = opts.boundary.continuation(label);
        let joined = format!("{prompt}{continuation}");
        let full = tokenizer.encode(&joined).map_err(|_| MlxError(-990))?;
        if full.is_empty() {
            plans.push(Plan {
                label: label.to_string(),
                continuation,
                full: Vec::new(),
            });
            continue;
        }
        plans.push(Plan {
            label: label.to_string(),
            continuation,
            full,
        });
    }

    // ---- 2. the shared prefix: the longest common prefix of all candidates ----
    // Every candidate carries the same prompt tokens, so any non-empty
    // candidate's token sequence is the reference.
    let base_full: Vec<u32> = plans
        .iter()
        .find(|p| !p.full.is_empty())
        .map(|p| p.full.clone())
        .unwrap_or_default();
    let mut shared = base_full.len();
    for p in plans.iter() {
        if p.full.is_empty() {
            continue;
        }
        shared = shared.min(common_prefix_len(&base_full, &p.full));
    }
    if shared == 0 {
        // Nothing to condition on: every candidate's tokenization disagrees
        // with every other one from the very first token.
        return Err(MlxError(-991));
    }
    outcome.prefix_tokens = shared;

    // ---- 3. the scored span per candidate, and the honesty checks ----
    let mut scores: Vec<LabelScore> = Vec::with_capacity(plans.len());
    for plan in &plans {
        if plan.full.is_empty() {
            scores.push(LabelScore {
                label: plan.label.clone(),
                continuation: plan.continuation.clone(),
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
        let tokens: Vec<u32> = plan.full[shared..].to_vec();
        let scored_text = tokenizer.decode(&tokens).unwrap_or_default();
        let boundary_mismatch = scored_text != plan.continuation;
        if boundary_mismatch {
            outcome.boundary_mismatches += 1;
        }
        scores.push(LabelScore {
            label: plan.label.clone(),
            continuation: plan.continuation.clone(),
            scored_text,
            tokens,
            per_token_logprob: Vec::new(),
            sum_logprob: 0.0,
            mean_logprob: 0.0,
            boundary_mismatch,
            empty: false,
            eos_prob_first: None,
            eos_dominates: false,
        });
    }

    // ---- 4. the shared prefix prefill (KV only: no vocabulary projection) ----
    let mut cache = KvCache::new(model.cfg.layers);
    let max_tail = plans
        .iter()
        .map(|p| p.full.len().saturating_sub(shared))
        .max()
        .unwrap_or(0);
    cache.reserve(
        model.table(),
        1, // batch
        model.cfg.kv_heads,
        model.cfg.head_dim,
        shared + max_tail + 1,
        s,
    )?;
    // The last shared token is scored INSIDE each candidate's chunk (it is
    // the position that predicts the candidate's first token), so the
    // prefill covers every shared token but that one.
    let prefill_len = shared - 1;
    if prefill_len > 0 {
        let ids: Vec<i32> = base_full[..prefill_len].iter().map(|&t| t as i32).collect();
        let arr = Array::from_data_i32(&ids, &[1, prefill_len])?;
        let hidden = model.forward_hidden(&arr, &mut cache, s)?;
        // MLX IS LAZY: force the real prefill now, so the candidate timings
        // measure the candidates and not the prompt's deferred work.
        hidden.eval()?;
    }
    let last_shared: i32 = base_full[shared - 1] as i32;

    // ---- 5. score each candidate with ONE short forward ----
    let eos = eos_id(tokenizer);
    for (plan, score) in plans.iter_mut().zip(scores.iter_mut()) {
        if plan.full.is_empty() {
            continue;
        }
        let tail: Vec<u32> = plan.full[shared..].to_vec();
        let m = tail.len();
        // The chunk is [last shared token] + the candidate's tokens but the
        // last one: chunk position i predicts the candidate's token i, so
        // the chunk needs exactly m positions to score m tokens.
        let mut chunk: Vec<i32> = Vec::with_capacity(m);
        chunk.push(last_shared);
        for &t in &tail[..m - 1] {
            chunk.push(t as i32);
        }
        let arr = Array::from_data_i32(&chunk, &[1, m])?;
        let logits = model.forward_step(&arr, &mut cache, s)?;
        let (per_token, eos_prob_first) = position_logprobs(&logits, &tail, eos, s)?;

        let sum: f32 = per_token.iter().sum();
        let mean = if per_token.is_empty() {
            f32::NEG_INFINITY
        } else {
            sum / per_token.len() as f32
        };
        // SAME UNITS: `p` is a probability, `per_token` entries are natural
        // LOG-probabilities. The original `p > first` compared across units
        // and fired on every row (any positive probability beats any
        // negative logprob) — the recorded 293/293 eos_dominant pattern was
        // this, not a model fact. Found in the same 2026-10-26 localization
        // as the missing max add-back.
        let eos_dominates = match (eos_prob_first, per_token.first()) {
            (Some(p), Some(&first)) => p > first.exp(),
            _ => false,
        };
        score.tokens = tail;
        score.per_token_logprob = per_token;
        score.sum_logprob = sum;
        score.mean_logprob = mean;
        score.eos_prob_first = eos_prob_first;
        score.eos_dominates = eos_dominates;

        // Rewind: the next candidate overwrites the rows this one wrote.
        // The shared prefix rows are never touched (they live below
        // `prefill_len`), so the next candidate sees the same prefix.
        cache.offset = prefill_len;
    }

    // ---- 6. rank ----
    for s in &scores {
        let primary = primary_score(s, opts.normalization);
        outcome.logprobs.push((s.label.clone(), primary));
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

/// The score of one candidate under one normalization.
pub fn primary_score(score: &LabelScore, normalization: LengthNormalization) -> f32 {
    match normalization {
        LengthNormalization::Sum => score.sum_logprob,
        LengthNormalization::Mean => score.mean_logprob,
    }
}

/// One candidate's tokenization plan.
struct Plan {
    label: String,
    continuation: String,
    /// `tokenize(prompt + continuation)`.
    full: Vec<u32>,
}

/// The length of the longest common prefix of two token sequences.
pub(crate) fn common_prefix_len(a: &[u32], b: &[u32]) -> usize {
    let n = a.len().min(b.len());
    let mut i = 0;
    while i < n && a[i] == b[i] {
        i += 1;
    }
    i
}

/// The per-position log-probability of each target token, plus the EOS
/// probability at the first position.
///
/// `logits` is `[1, m, V]` — one row per scored position. The log-softmax is
/// computed on the GPU (max-subtract, exp, sum, log) and read back as `m`
/// floats; the readback forces the real logits (MLX IS LAZY).
pub(crate) fn position_logprobs(
    logits: &Array,
    targets: &[u32],
    eos: Option<u32>,
    s: Stream,
) -> MlxResult<(Vec<f32>, Option<f32>)> {
    let m = targets.len();
    if m == 0 {
        return Ok((Vec::new(), None));
    }
    let lg = logits.astype(Dtype::Float32, s)?;
    // logsumexp over the vocabulary, computed stably: subtract the row max.
    let am = lg.argmax_axis(-1, false, s)?;
    let am3 = am.expand_dims(&[2], s)?;
    let maxv = lg.take_along_axis(&am3, 2, s)?;
    let shifted = lg.sub(&maxv, s)?;
    let ex = shifted.exp(s)?;
    let lse_shifted = ex.sum_axes(&[2], false, s)?.log(s)?; // [1, m]
    // THE MAX MUST GO BACK: `lse_shifted` is logsumexp(logits) - max, the
    // stable form's remainder. The 2026-10-26 localization (the L-G6
    // cross-engine disagreement, V-r) found this line scored every native
    // rank as logprob + sum(max logits) — an unnormalized eos "probability"
    // above 1 on every row (the recorded 293/293 eos_dominant), and a
    // ranking distortion that moved winners. maxv is [1, m, 1]; read it
    // beside lse and subtract it too: lp = tgt - max - log(sum exp(t-max)).
    let maxv_v = maxv.to_f32_vec(s)?;
    let tgt: Vec<i32> = targets.iter().map(|&t| t as i32).collect();
    let tgt_arr = Array::from_data_i32(&tgt, &[1, m, 1])?;
    let tg = lg.take_along_axis(&tgt_arr, 2, s)?; // [1, m, 1]
    let lse_v = lse_shifted.to_f32_vec(s)?;
    let tg_v = tg.to_f32_vec(s)?;
    if lse_v.len() < m || tg_v.len() < m || maxv_v.len() < m {
        return Err(MlxError(-992));
    }
    let per_token: Vec<f32> = (0..m).map(|i| tg_v[i] - maxv_v[i] - lse_v[i]).collect();
    // The EOS probability at the FIRST scored position: would the model stop
    // where the label starts?
    let eos_prob_first = match eos {
        Some(eid) => {
            let e_arr = Array::from_data_i32(&vec![eid as i32; m], &[1, m, 1])?;
            let el = lg.take_along_axis(&e_arr, 2, s)?.to_f32_vec(s)?;
            if el.is_empty() {
                None
            } else {
                let p = (el[0] - maxv_v[0] - lse_v[0]) as f64;
                Some(p.exp() as f32)
            }
        }
        None => None,
    };
    Ok((per_token, eos_prob_first))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn common_prefix_is_exact() {
        assert_eq!(common_prefix_len(&[1, 2, 3], &[1, 2, 9]), 2);
        assert_eq!(common_prefix_len(&[1], &[2]), 0);
        assert_eq!(common_prefix_len(&[], &[1]), 0);
    }

    #[test]
    fn boundary_forms_the_scored_continuation() {
        assert_eq!(
            ContinuationBoundary::LeadingSpace.continuation("abstain"),
            " abstain"
        );
        assert_eq!(
            ContinuationBoundary::NoSpace.continuation("abstain"),
            "abstain"
        );
        assert_eq!(
            ContinuationBoundary::Newline.continuation("abstain"),
            "\nabstain"
        );
    }

    #[test]
    fn boundary_names_round_trip() {
        for b in [
            ContinuationBoundary::LeadingSpace,
            ContinuationBoundary::NoSpace,
            ContinuationBoundary::Newline,
        ] {
            assert_eq!(ContinuationBoundary::parse(b.as_str()), Some(b));
        }
        assert_eq!(ContinuationBoundary::parse("nonsense"), None);
    }
}
