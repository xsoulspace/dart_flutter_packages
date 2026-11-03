//! Opt-in request-level sampling for the solo text generate entries (Qwen3
//! and LFM2.5). Additive rung next to greedy decode — the laws:
//!
//! - ABSENT = GREEDY. A request without sampling fields never enters this
//!   module; the decode loop takes the exact argmax path the 64/64 parity
//!   fixtures pin (byte-identical by construction).
//! - Only the SOLO generate entries accept sampling. The fused batch and
//!   the streaming wire stay greedy (their gates pin decision invariance,
//!   not sampling).
//! - `temperature <= 0` decodes greedily over the (penalized) logits, so
//!   `repetition_penalty` alone is meaningful at temperature 0.
//! - Repetition penalty is HF/CTRL semantics applied once per DISTINCT
//!   token seen (prompt + generated so far): positive logits divide by
//!   the penalty, non-positive multiply — like mlx-lm.
//! - Nothing here claims determinism: the draw comes from a process-local
//!   xorshift seeded from the clock, and the seed carrier stays a carrier
//!   (ADR 0059). Sampling requests answer with a greedy-equivalent when
//!   temperature is 0, never a fabricated distribution.

/// One request's sampling knobs (validated at the FFI boundary: finite,
/// `temperature >= 0`, `repetition_penalty >= 1`).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct SamplingParams {
    pub temperature: f32,
    pub repetition_penalty: f32,
}

/// Process-local non-crypto RNG (xorshift64*). Sampling makes no
/// determinism claim, so a clock-seeded generator is enough and keeps the
/// dependency tree unchanged.
pub struct XorShift64 {
    state: u64,
}

impl XorShift64 {
    /// Seeds from the monotonic-ish wall clock plus a per-process counter,
    /// so two requests landing in the same nanosecond still diverge.
    pub fn seeded_from_clock() -> Self {
        use std::sync::atomic::{AtomicU64, Ordering};
        static CALLS: AtomicU64 = AtomicU64::new(0);
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos() as u64)
            .unwrap_or(0x9E3779B97F4A7C15);
        let calls = CALLS.fetch_add(1, Ordering::Relaxed);
        let mut state = nanos ^ (calls.wrapping_mul(0x9E3779B97F4A7C15));
        if state == 0 {
            state = 0x9E3779B97F4A7C15;
        }
        Self { state }
    }

    /// xorshift64* — never zero (zero is reseeded at construction).
    pub fn next_u64(&mut self) -> u64 {
        let mut x = self.state;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.state = x;
        x.wrapping_mul(0x2545F4914F6CDD1D)
    }

    /// Uniform in (0, 1]: the inverse-CDF walk starts at a strictly
    /// positive mass so a zero draw cannot skip the first token.
    pub fn next_unit(&mut self) -> f64 {
        let u = (self.next_u64() >> 11) as f64 / (1u64 << 53) as f64;
        if u <= 0.0 {
            f64::MIN_POSITIVE
        } else {
            u
        }
    }
}

/// HF/CTRL repetition penalty over DISTINCT seen token ids. Ids beyond the
/// vocab bound are ignored (the BPE never emits them; belt for callers).
pub fn apply_repetition_penalty(logits: &mut [f32], seen: &[i32], penalty: f32) {
    if !penalty.is_finite() || penalty == 1.0 || seen.is_empty() {
        return;
    }
    let mut distinct = std::collections::HashSet::with_capacity(seen.len());
    for &token in seen {
        if token < 0 {
            continue;
        }
        if distinct.insert(token) {
            if let Some(logit) = logits.get_mut(token as usize) {
                *logit = if *logit > 0.0 {
                    *logit / penalty
                } else {
                    *logit * penalty
                };
            }
        }
    }
}

/// Greedy argmax over (already penalized) logits.
fn argmax(logits: &[f32]) -> i32 {
    let mut best = 0usize;
    let mut best_value = f32::NEG_INFINITY;
    for (i, &v) in logits.iter().enumerate() {
        if v > best_value {
            best_value = v;
            best = i;
        }
    }
    best as i32
}

/// One sampled decode step over host-read logits: penalty → temperature
/// scale → stable softmax → inverse-CDF draw. Temperature 0 stays greedy
/// over the penalized logits (penalty-only requests keep meaning).
pub fn sample_next(
    logits: &mut [f32],
    seen: &[i32],
    params: &SamplingParams,
    rng: &mut XorShift64,
) -> i32 {
    apply_repetition_penalty(logits, seen, params.repetition_penalty);
    if params.temperature <= 0.0 {
        return argmax(logits);
    }
    // Stable softmax over logits / T: shift by the max before exp.
    let inv_t = 1.0 / params.temperature;
    let mut max = f32::NEG_INFINITY;
    for &v in logits.iter() {
        if v > max {
            max = v;
        }
    }
    let mut total = 0f64;
    let mut probs = Vec::with_capacity(logits.len());
    for &v in logits.iter() {
        let p = ((v - max) * inv_t).exp() as f64;
        probs.push(p);
        total += p;
    }
    if !total.is_finite() || total <= 0.0 {
        return argmax(logits);
    }
    // Inverse-CDF draw: one pass, no allocation beyond the probs vector.
    let draw = rng.next_unit() * total;
    let mut cumulative = 0f64;
    for (i, &p) in probs.iter().enumerate() {
        cumulative += p;
        if draw <= cumulative {
            return i as i32;
        }
    }
    (probs.len() - 1) as i32
}

#[cfg(test)]
mod tests {
    use super::*;

    fn deterministic_rng(seed: u64) -> XorShift64 {
        XorShift64 { state: seed }
    }

    #[test]
    fn penalty_is_hf_semantics_per_distinct_token() {
        let mut logits = vec![2.0, -2.0, 1.0, 0.0];
        apply_repetition_penalty(&mut logits, &[0, 0, 1, 999], 2.0);
        assert_eq!(logits, vec![1.0, -4.0, 1.0, 0.0]);
        // Penalty 1.0 is a no-op even with repeats.
        let mut logits = vec![2.0, -2.0];
        apply_repetition_penalty(&mut logits, &[0, 0, 1], 1.0);
        assert_eq!(logits, vec![2.0, -2.0]);
    }

    #[test]
    fn zero_temperature_is_greedy_over_penalized_logits() {
        let params = SamplingParams {
            temperature: 0.0,
            repetition_penalty: 2.0,
        };
        let mut logits = vec![2.0, 1.0, 0.5];
        let mut rng = deterministic_rng(7);
        // Token 0 already seen: its 2.0 halves to 1.0, tying token 1 — the
        // strict > argmax keeps the FIRST max (token 0).
        assert_eq!(sample_next(&mut logits, &[0], &params, &mut rng), 0);
        let mut logits = vec![2.2, 1.0, 0.5];
        assert_eq!(sample_next(&mut logits, &[0], &params, &mut rng), 0);
    }

    #[test]
    fn sampling_favors_high_logits_but_stays_in_bounds() {
        let params = SamplingParams {
            temperature: 0.7,
            repetition_penalty: 1.0,
        };
        let mut rng = deterministic_rng(0xDEADBEEF);
        let mut peaks = 0;
        for _ in 0..200 {
            let mut logits = vec![0.0, 10.0, 0.0];
            let t = sample_next(&mut logits, &[], &params, &mut rng);
            assert!((0..3).contains(&t));
            if t == 1 {
                peaks += 1;
            }
        }
        assert!(
            peaks > 150,
            "a 10-logit peak at T=0.7 should dominate the draw (got {peaks}/200)"
        );
    }

    #[test]
    fn rng_is_uniform_enough_and_never_zero() {
        let mut rng = deterministic_rng(42);
        let mut inside = 0;
        for _ in 0..1000 {
            let u = rng.next_unit();
            assert!(u > 0.0 && u <= 1.0);
            if u < 0.5 {
                inside += 1;
            }
        }
        assert!(
            (350..650).contains(&inside),
            "a broken generator skews the CDF draw (got {inside}/1000 below 0.5)"
        );
    }
}
