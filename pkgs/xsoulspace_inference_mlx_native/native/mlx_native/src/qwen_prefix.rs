//! Opt-in host-bound exact-prefix reuse. No text, token or KV crosses scope.
use crate::mlx::{MlxError, MlxResult, Stream};
use crate::qwen::{KvCache, Qwen3};
use std::collections::VecDeque;
use std::sync::atomic::AtomicBool;
#[derive(Clone, Debug, PartialEq, Eq, serde::Deserialize)]
pub struct CacheScope { pub actor: String, pub epoch: String }
struct Entry { scope: CacheScope, tokens: Vec<i32>, cache: KvCache, window: usize }
#[derive(Default)]
pub struct PrefixPool { entries: VecDeque<Entry> }
const MAX_ENTRIES: usize = 4;
const MAX_WINDOW: usize = 8192;
fn matched_prefix(old: &[i32], new: &[i32]) -> usize {
    let matched = old.iter().zip(new).take_while(|(a,b)| a == b).count()
        .min(new.len().saturating_sub(1));
    // Preserve the fresh path's matrix shapes. Arbitrary partial-prefill
    // reuse changed greedy tokens in the native reasoning probe.
    if old.len() == new.len().saturating_sub(1) && matched == old.len() {
        matched
    } else { matched / 2048 * 2048 }
}
impl PrefixPool {
    pub fn clear_actor(&mut self, actor: &str) {
        self.entries.retain(|e| e.scope.actor != actor);
    }
    pub fn generate(&mut self, model: &Qwen3, prompt: &[i32], max: usize,
        stop: Option<&[i32]>, stream: Stream, scope: Option<CacheScope>, reset: bool,
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
                Some(flag) => model.generate_greedy_cancellable(
                    prompt,
                    max,
                    stop,
                    stream,
                    Some(flag),
                ),
                None => model.generate_greedy(prompt, max, stop, stream),
            }?;
            return Ok((ids, 0));
        };
        if scope.actor.is_empty() || scope.epoch.is_empty() || scope.actor.len() > 256 || scope.epoch.len() > 256 {
            return Err(MlxError(-978));
        }
        // An authorization epoch change destroys this actor's old state.
        self.entries.retain(|e| e.scope.actor != scope.actor || (!reset && e.scope == scope));
        let entry = self.entries.iter().position(|e| e.scope == scope)
            .and_then(|i| self.entries.remove(i));
        // Bound allocated capacity, not just the eventual answer length.
        if prompt.len().checked_add(max).map_or(true, |n| n > MAX_WINDOW) {
            let ids = match cancelled {
                Some(flag) => model.generate_greedy_cancellable(
                    prompt,
                    max,
                    stop,
                    stream,
                    Some(flag),
                ),
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
            scope, tokens: Vec::new(), cache: KvCache::new(model.cfg.layers), window,
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
        while self.entries.len() >= MAX_ENTRIES { self.entries.pop_front(); }
        self.entries.push_back(entry);
        Ok((ids, reused))
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn prefix_is_exact_and_leaves_logits_token() {
        assert_eq!(matched_prefix(&[1,2], &[1,2,3]), 2);
        assert_eq!(matched_prefix(&[1,2,3,4], &[1,2,3]), 0);
        assert_eq!(matched_prefix(&[1,2,3], &[1,9,3]), 0);
        assert_eq!(matched_prefix(&[9,2,3], &[1,2,3]), 0);
        assert_eq!(matched_prefix(&[], &[1]), 0);
    }
}
