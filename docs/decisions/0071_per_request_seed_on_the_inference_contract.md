# ADR 0071: A per-request seed on the inference contract

- Status: Accepted. The carrier has landed; the honesty law binds every
  provider that implements it.
- Date: 2026-10-21
- North Star impact: `clarifies`
  [0059](0059_native_casts_in_palette_and_composable_requests.md) — the
  composable request surface gains one optional field and one provider duty.
  No existing decision's centre moves: the request/response contract, the
  provider seam, and the palette are unchanged, and the seed is a **carrier**,
  not a behaviour.
- Builds on: 0059 (composable request surface), 0058 (unified inference
  interface — one `InferenceClient` every provider answers to)
- Measured on: the seed contract as it stands in this repository's working
  tree (2026-10-21) — the carrier, the four provider paths and the honesty
  tests. The provider behaviours below are **read from the code and asserted
  by the tests**, not from a benchmark.

## Context

Two things were true at the same time in this repository, and the tension
between them is the reason this ADR exists.

1. **Reproducibility is requested per request, not per process.** A caller
   that wants "ask this again and get the same answer" needs a knob on the
   request. A process-global knob does not serve that: two requests in the
   same process with different intents need different behaviour, and a
   caller re-running one request must not have to re-run the ones before it.
2. **A provider that cannot honour a seed must not pretend to.** The
   honest failure of a seed is not silence — it is an answer that says "I
   cannot do this", delivered in the same channel as the answer, so the
   caller is never misled about whether two runs were comparable.

Before this, `GenerationOptions` and `InferenceRequest` had no seed at all:
there was no way to ask for one, and no way for a provider to say that it
could not honour one. The gap was invisible because both halves were
missing.

## Decision

### 1. The carrier: one optional integer seed on the request

`GenerationOptions.seed` and `InferenceRequest.seed` are an optional
integer, carried end to end:

- both `InferenceRequest` factories (`InferenceRequest` and
  `InferenceRequest.structured`),
- the request map and the JSON codec,
- `copyWith`,
- the flat `GenerationOptions` view and the options codec,
- the public `inferenceSeedMetaKey` (`inference_models.dart`) — the
  response-meta key under which a provider echoes the request seed.

**Zero is a real seed** and is carried as such; **an absent seed stays
absent** on the wire map and is not serialized. The carrier states no
determinism: what a provider does with the value is the provider's business.

### 2. The honesty constraint

> **A provider that cannot honour the seed MUST NOT pretend to.** It must
> echo the requested seed on the response meta under `inferenceSeedMetaKey`
> and state plainly that it cannot honour it. A provider that CAN honour it
> maps it to its own wire parameter and echoes it **without** a refusal
> warning. A seed is never silently dropped, and a seed is never silently
> ignored.

The echo is what makes the constraint checkable: a caller can always ask
"was my seed honoured?" from the response alone, without trusting the
provider's prose.

### 3. The per-provider reading (as implemented, 2026-10-21)

| provider                                | on the wire                                                                  | response meta | warning                                                                                       | honesty test                         |
| --------------------------------------- | ---------------------------------------------------------------------------- | ------------- | --------------------------------------------------------------------------------------------- | ------------------------------------ |
| `xsoulspace_inference_openrouter`       | `seed` in the body (the chat-completions API has a top-level integer `seed`) | echoed        | none                                                                                          | `test/seed_honesty_test.dart`        |
| `xsoulspace_inference_openai`           | `seed` in the body (the Responses API has a top-level integer `seed`)        | echoed        | none                                                                                          | `test/seed_honesty_test.dart`        |
| `xsoulspace_inference_anthropic`        | **not sent** (the Messages API has no `seed` parameter)                      | echoed        | one: "… has no seed parameter; the provider cannot honor the request seed N"                  | `test/seed_honesty_test.dart`        |
| `xsoulspace_inference_apple_foundation` | **not sent** (the native bridge request has no seed field)                   | echoed        | one: "… has no seed field in the native bridge; the provider cannot honor the request seed N" | — (no dedicated test in the package) |
| `xsoulspace_inference_mlx_native`       | **not sent, and not read**                                                   | not echoed    | none                                                                                          | — (see the gap below)                |

**The core contract** is tested in
`xsoulspace_inference_core/test/inference/inference_seed_test.dart`: an
unseeded request carries no seed anywhere; zero survives every hop; a
nonzero seed round-trips through JSON, `copyWith` and the options view; and
the meta key is a stable, non-empty name.

**The gap, as read (2026-10-21 21:31), and why it is stated as a reading
rather than a fact.** At that read, the `mlx_native` local path neither mapped
nor reported the seed: `MlxNativeTextClient` never read `request.seed`, so a
seeded request against the local engine was **silently ignored** — a
violation of §2 as written. **A concurrent change in the working tree
(2026-10-21 22:12) adds exactly the missing behaviour** — the seed is read,
recorded, echoed under `inferenceSeedMetaKey`, and reported with the honest
warning that a greedy decode is _deterministic-by-construction, not
seed-derived_ — so **this gap is expected to close, and this table row must
be re-read when that change lands.** The row is a reading of the code at a
named time, not a claim about the tree today.

Two mitigations make the un-honoured seed _less_ bad than it looks: the local
decode is **greedy**, so its output is already seed-independent; and the
client warns when a non-zero temperature is requested, because it cannot
honour one. The honest shape — echo the seed, say that a greedy decode does
not derive from it — is what the concurrent change adopts.

### 4. The sampler's RNG contract — counter-based, specified, and now IMPLEMENTED

This section was written as a **design constraint on a local sampler**, not a
description of shipped code. **At the time of the read (2026-10-21 21:31) no
counter-based RNG existed in this repository** and the local engine decoded
greedily. **An implementation landed in the working tree during this
session** (`xsoulspace_inference_core/lib/src/seeded_rng.dart`, exported from
the package's public library, with `test/seeded_rng_test.dart`), so this
section is now the **contract that implementation is read against** — the
naming differs in one place, and the difference is recorded rather than
smoothed: the implementation keys the reject stream by `(seed, position,
attempt)` where this contract names three streams (fresh / reject-residual /
accept-reject); the **accept-reject** stream belongs to a speculative sampler
and has no Dart consumer, so the Dart class covers the first two. The mixing
function is **SplitMix64**.

The seed must be reproduced **for a single request in isolation**, which a
global RNG state cannot do: a global state's value depends on every draw
made before it, so the same request reproduces only if every preceding draw
reproduces too. The design is therefore **counter-based**, keyed by
`(seed, position, stream)`:

- **seed** — a per-request `uint64` key. It is the request's own key, never
  a process-wide value, so two requests in one process never contend.
- **position** — the token position in the sequence. Position is part of the
  key, so a position's draw does not depend on how many positions came
  before it, and a sequence can be resumed, batched, or replayed without
  renumbering.
- **stream** — **three disjoint streams per position**, so that consuming
  one can never perturb another:
  - `fresh` — the candidate draw for that position,
  - `reject-residual` — the re-draw after a rejection, so a rejected
    position's residual does not depend on how many rejections occurred,
  - `accept-reject` — the draw that decides whether a proposed token is
    accepted.

**Why the streams are disjoint rather than one stream with an offset.** A
single stream plus an offset is reproducible only if the number of draws
consumed before the point of interest is known. That count is exactly what
the rejection path makes uncertain. Separate counters make each draw a
pure function of `(seed, position, stream)` and nothing else.

**The carrier's limits, stated honestly.** The carrier in this repository is
a signed Dart `int`, not a constrained `uint64`; the `uint64` framing above
is a constraint on the sampler, and the carrier does not yet enforce a range
or reject a negative value. The carrier's contract is only "an optional
integer survives the hop".

## Alternatives considered

- **A process-global seed (an engine-level knob).** Rejected: it cannot
  serve two different requests in one process, and it makes a single
  request unreproducible in isolation — the case the seed exists for.
- **A seed that the provider silently ignores when it cannot honour it.**
  Rejected: silence is indistinguishable from a provider that did honour it
  and produced a different answer. The echo-plus-warning shape is the only
  one a caller can act on.
- **Requiring every provider to support seeds (a hard contract).** Rejected:
  the Anthropic Messages API and this repository's Apple-foundation native
  bridge have no seed parameter at all. A contract every provider cannot
  meet is a contract nobody meets; the honesty constraint is the one that can
  be met everywhere.
- **A promise of reproducibility in the carrier's own documentation.**
  Rejected: the carrier cannot promise anything on behalf of a provider. The
  carrier promises to _carry_; the provider promises to _report_.

## Consequences

- A caller can ask for a seed, and can always tell from the response whether
  it was honoured — `meta[inferenceSeedMetaKey]` plus the presence or absence
  of a refusal warning.
- Two providers that honour the seed (OpenRouter, OpenAI) and two that do
  not (Anthropic, Apple-foundation) answer the **same** request shape, and
  the difference is visible in the response rather than hidden in the
  provider.
- The local `mlx_native` path was the **one implementation that violated §2** at
  the time of the read (2026-10-21 21:31); the gap and its concurrent closure
  are in §3. It is the first thing to fix if the local path ever needs to
  answer the same question as the remote ones.
- The honesty tests are ordinary package tests, and they are the only
  evidence the constraint holds. They are not run by CI — see the non-claims.

## Non-claims

- **No determinism claim.** Nothing in this repository asserts that the same
  seed yields the same output from a provider. The contract is about
  **reporting**, not about reproducibility. The counter-based source added
  during this session fixes a _draw_ given `(seed, position)`, which is a
  narrower claim than "the provider's answer reproduces" and is not the same
  thing.
- **No batch-invariance claim.** A counter-based sampler (§4) would be
  designed to make a position's draw independent of its neighbours, but no
  such sampler is implemented here, and no claim is made that any provider's
  output is invariant to batch size or to its position within a batch.
- **No cross-hardware determinism claim.** A seed is a key, not a promise
  that two machines, two runtimes, or two library versions produce the same
  bytes.
- **No CI enforcement.** This repository has **no `.github/workflows/`
  directory**; the three workflow files that exist live in
  `.github/archite_workflows/`, where GitHub Actions does not pick them up.
  The seed tests are therefore **not** enforced by CI as the repository
  stands — they are run by the package's own `just test-one` loop.
- **The parity test is a tolerance comparison, not bit-identity.** The
  native crate's golden fixture asserts argmax agreement on all 63
  questions and a **max probability error below 0.005**
  (`test/laya_native_golden_test.dart`; the same bar is restated in
  `native/mlx_native/src/model.rs`). That is a **tolerance** comparison, and
  it is about the **laya plan walk** — it says nothing whatsoever about
  seeds. (The MTP fixture in this family is a different artifact and is
  bit-exact; the two must not be conflated.)
- **No claim that the seed is honoured by any provider the table does not
  name.** The table is the reading of the code as of 2026-10-21, and a
  provider that changes its wire mapping must change the table with it.

## Routing — the sibling decision

The **DSpark / DeepInfer** work is the **sibling** decision, not this one: an
external inference engine's patterns were reviewed from source and the
verdict is recorded in the model-experiment lane's
[`MTP-GATES.md`](../../pkgs/xsoulspace_inference_mlx_native/MTP-GATES.md)
**Part 4** ("the DeepInfer transfer"), so it is not re-read as evidence here.
Two ideas from that review have a stake in this family and are explicitly
**not** adopted by this ADR:

- **Batch invariance** is a **precondition of the lane's L-G4 batching
  gate**, not a claim of the seed contract. If a batched decode's output
  depends on a sequence's position in the batch, every number measured
  through it is a function of a choice — and a function of a choice is not a
  measurement.
- **Prompt-shape / prefix-cache uniformity** is a **product** stake and
  belongs to the same lane's L-G5 cost gate, not to the seed contract.

No `DSpark` artifact exists in this repository's tree; the routing is to that
Part 4 note.
