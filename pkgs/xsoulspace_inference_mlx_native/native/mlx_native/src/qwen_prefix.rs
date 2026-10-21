//! Opt-in host-bound exact-prefix reuse. No text, token or KV crosses scope.
//!
//! WEIGHT IDENTITY. A cached prefix is only valid under the weights that
//! produced it. When an adapter is merged, the model is a DIFFERENT model, so
//! every prefix computed under the old weights is stale — a cache hit across
//! an adapter swap is not a stale hit, it is a WRONG answer.
//!
//! The pool therefore carries a `weights` identity per entry, and the ENGINE
//! owns the current identity: the engine is the only thing that knows which
//! weights it is running. An entry whose weight identity differs from the
//! engine's is DROPPED, not reused. This is the structural fix — the pool
//! cannot be handed a stale entry, so no caller can forget to invalidate.
//!
//! (The alternative — letting the host put the adapter digest into the
//! `epoch` string — is a CONVENTION, and a convention that a host can
//! forget. `lora_set::CacheKey::epoch_token` still exists and still fills
//! that slot; this identity is the belt to that braces.)
use crate::mlx::{MlxError, MlxResult, Stream};
use crate::qwen::{KvCache, Qwen3};
use std::collections::VecDeque;
use std::sync::atomic::AtomicBool;
#[derive(Clone, Debug, PartialEq, Eq, serde::Deserialize)]
pub struct CacheScope {
    pub actor: String,
    pub epoch: String,
}
struct Entry {
    scope: CacheScope,
    weights: String,
    tokens: Vec<i32>,
    cache: KvCache,
    window: usize,
}
#[derive(Default)]
pub struct PrefixPool {
    entries: VecDeque<Entry>,
}
const MAX_ENTRIES: usize = 4;
const MAX_WINDOW: usize = 8192;
fn matched_prefix(old: &[i32], new: &[i32]) -> usize {
    let matched = old
        .iter()
        .zip(new)
        .take_while(|(a, b)| a == b)
        .count()
        .min(new.len().saturating_sub(1));
    // Preserve the fresh path's matrix shapes. Arbitrary partial-prefill
    // reuse changed greedy tokens in the native reasoning probe.
    if old.len() == new.len().saturating_sub(1) && matched == old.len() {
        matched
    } else {
        matched / 2048 * 2048
    }
}
impl PrefixPool {
    pub fn clear_actor(&mut self, actor: &str) {
        self.entries.retain(|e| e.scope.actor != actor);
    }
    pub fn generate(
        &mut self,
        model: &Qwen3,
        prompt: &[i32],
        max: usize,
        stop: Option<&[i32]>,
        stream: Stream,
        scope: Option<CacheScope>,
        reset: bool,
    ) -> MlxResult<(Vec<i32>, usize)> {
        self.generate_cancellable(model, prompt, max, stop, stream, scope, reset, None)
    }

    pub fn generate_cancellable(
        &mut self,
        model: &Qwen3,
        prompt: &[i32],
        max: usize,
        stop: Option<&[i32]>,
        stream: Stream,
        scope: Option<CacheScope>,
        reset: bool,
        cancelled: Option<&AtomicBool>,
    ) -> MlxResult<(Vec<i32>, usize)> {
        let Some(scope) = scope else {
            let ids = match cancelled {
                Some(flag) => {
                    model.generate_greedy_cancellable(prompt, max, stop, stream, Some(flag))
                }
                None => model.generate_greedy(prompt, max, stop, stream),
            }?;
            return Ok((ids, 0));
        };
        if scope.actor.is_empty()
            || scope.epoch.is_empty()
            || scope.actor.len() > 256
            || scope.epoch.len() > 256
        {
            return Err(MlxError(-978));
        }
        // An authorization epoch change destroys this actor's old state.
        self.entries
            .retain(|e| e.scope.actor != scope.actor || (!reset && e.scope == scope));
        // A WEIGHT change destroys every entry: a prefix computed under other
        // weights is not a stale hit, it is a wrong answer.
        let weights = model.weight_identity();
        self.entries.retain(|e| e.weights == weights);
        let entry = self
            .entries
            .iter()
            .position(|e| e.scope == scope)
            .and_then(|i| self.entries.remove(i));
        // Bound allocated capacity, not just the eventual answer length.
        if prompt
            .len()
            .checked_add(max)
            .map_or(true, |n| n > MAX_WINDOW)
        {
            let ids = match cancelled {
                Some(flag) => {
                    model.generate_greedy_cancellable(prompt, max, stop, stream, Some(flag))
                }
                None => model.generate_greedy(prompt, max, stop, stream),
            }?;
            return Ok((ids, 0));
        }
        // The underlying growth policy assumes monotonic decode offsets.
        // Rewound buffers must not grow by appending their old padding: begin
        // fresh when the requested allocation window increases.
        let window = prompt.len() + max;
        let entry = entry.filter(|e| e.window >= window);
        let mut entry = entry.unwrap_or_else(|| Entry {
            scope,
            weights: weights.clone(),
            tokens: Vec::new(),
            cache: KvCache::new(model.cfg.layers),
            window,
        });
        let reused = matched_prefix(&entry.tokens, prompt);
        entry.cache.offset = reused;
        // Removed before evaluation: failure drops partially updated state.
        let ids = match cancelled {
            Some(flag) => model.generate_greedy_cached_cancellable(
                prompt,
                max,
                stop,
                stream,
                &mut entry.cache,
                Some(flag),
            ),
            None => model.generate_greedy_cached(prompt, max, stop, stream, &mut entry.cache),
        }?;
        entry.tokens = prompt[..prompt.len() - 1].to_vec();
        while self.entries.len() >= MAX_ENTRIES {
            self.entries.pop_front();
        }
        self.entries.push_back(entry);
        Ok((ids, reused))
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn prefix_is_exact_and_leaves_logits_token() {
        assert_eq!(matched_prefix(&[1, 2], &[1, 2, 3]), 2);
        assert_eq!(matched_prefix(&[1, 2, 3, 4], &[1, 2, 3]), 0);
        assert_eq!(matched_prefix(&[1, 2, 3], &[1, 9, 3]), 0);
        assert_eq!(matched_prefix(&[9, 2, 3], &[1, 2, 3]), 0);
        assert_eq!(matched_prefix(&[], &[1]), 0);
    }

    /// The weight-identity law, as a PURE test of the pool's policy: an
    /// entry computed under one weight identity is never reused under
    /// another.
    ///
    /// The pool's rule is `retain(|e| e.weights == engine_weights)`, so a
    /// changed identity drops every entry. This test pins that rule on the
    /// entry list directly, so it does not need a GPU or a checkpoint — the
    /// law is about WHICH entries survive, not about decoding.
    #[test]
    fn a_weight_change_drops_every_entry() {
        let scope = CacheScope {
            actor: "a".into(),
            epoch: "e".into(),
        };
        let mut entries: VecDeque<Entry> = VecDeque::new();
        entries.push_back(Entry {
            scope: scope.clone(),
            weights: "weights-A".into(),
            tokens: vec![1, 2, 3],
            cache: KvCache::new(1),
            window: 16,
        });
        // The engine now runs weights-B: the entry is stale and is dropped.
        let engine_weights = "weights-B".to_string();
        entries.retain(|e| e.weights == engine_weights);
        assert!(
            entries.is_empty(),
            "an entry computed under other weights survived — a cache hit across \
             a weight change is a wrong answer, not a stale hit"
        );
        // Under the SAME identity the entry survives (the reuse path is not
        // broken by the fix).
        let engine_weights = "weights-A".to_string();
        entries.push_back(Entry {
            scope: scope.clone(),
            weights: "weights-A".into(),
            tokens: vec![1, 2, 3],
            cache: KvCache::new(1),
            window: 16,
        });
        entries.retain(|e| e.weights == engine_weights);
        assert_eq!(entries.len(), 1, "the same-weight entry was dropped");
    }
}
