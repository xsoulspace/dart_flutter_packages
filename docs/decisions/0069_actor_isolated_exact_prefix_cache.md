# ADR 0069: opt-in actor-isolated Qwen prefix cache

Date: 2026-10-13. Status: experimental. North-star impact: applies.

The caller reconstructs disposable context cuts from authoritative history.
Caching is computational reuse, not memory, history editing, sharing, or authority.

The native Qwen handle owns a bounded in-memory LRU of four actor/epoch scopes.
The host supplies a realm-qualified actor identity and authorization epoch; these
strings are not authentication, and must never come from model-authored arguments.
Clients sharing weights bind separate scopes. Omitted scope retains fresh behavior.
No disk persistence. Engine unload drops all entries. A changed epoch or reset on
an actor's next request discards that actor's old entry; failure drops its entry.
An absent actor does not cause authority changes. Explicit revocation uses `clearCache(actor)`: it waits for in-flight generation
to finish and removes every epoch for that actor.

Only exact token prefixes qualify. Reuse additionally preserves the fresh path's
2048-token prefill boundaries, or the full prefill of an identical prompt. Arbitrary
partial-prefix reuse failed greedy-token parity in the initial native experiment;
we retain that failure and fall back to recomputation for such prefixes. Generated
reasoning tokens are not reused as prompt prefix state. No approximate stale KV,
RoPE relocation, suffix reuse or recurrent-state substitution is admitted.

Entries are retained only when prompt plus requested output is at most 8192 tokens.
Increasing an entry's requested allocation window starts fresh, avoiding growth
of rewound padded buffers. Generation stays serialized by the existing native forward lock. Cache metadata
exposes only reused token count, not another actor's tokens or state. An actor's
cache is not a substitute for host-enforced private experience and selective sharing.

Validation: same-process fresh/cached token equality, different actors, epochs,
reset, eviction, changed and shortened prompts, errors, reasoning-on native runs;
Laya workflow selection and Qwen answer correctness remain separate measurements.
Full model qualification, asynchronous cancellation and production pump adoption
are not claimed. Shared fresh-hook cache deletion is avoided during concurrent work;
isolated builds pair the dylib with its metallib and explicit asset map instead.

Host composition (after authority checks):

```dart
final actorClient = MlxNativeTextClient.qwen(sharedEngine,
  thinking: true,
  cacheScope: QwenCacheScope(actor: '$worldId/$actorId', epoch: grantRevision));
// On revocation, before admitting subsequent work:
sharedEngine.clearCache('$worldId/$actorId');
```

The current opt-in binding is the eager Qwen factory and raw native completion
API. Lazy palette clients retain their existing uncached default. Hosts must not
claim automatic cache adoption from this experimental composition.
