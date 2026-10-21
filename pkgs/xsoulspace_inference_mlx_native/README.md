# xsoulspace_inference_mlx_native

The MLX-native engine host for
[xsoulspace_inference_core](https://github.com/xsoulspace/dart_flutter_packages/tree/main/pkgs/xsoulspace_inference_core):
one Rust cdylib (statically linking the pinned MLX 0.32.2 + mlx-c sources),
one composition API, one binding table — and the model drivers that share it
(the laya decision op-chain, Qwen3, LFM2) with their Dart FFI clients,
OpenAI-compatible chat servers, and the unified `InferenceClient` binding.
Knows no product: products (`xsoulspace_inference_laya`, the harness text
lane) depend on this package; it depends on none of them ([ADR
0057](../../../docs/decisions/0057_engine_host_refactor_and_bench_architecture.md),
[ADR 0058](../../../docs/decisions/0058_native_engines_unified_inference_interface.md)).

**Running benches or perf gates? Read [POWER.md](POWER.md) first** — the
power laws (ADR 0061): sense/record/gate, never command; perf gates
assert only on AC..

## Model drivers

Flutter embeds resolve the registered `mlx_native` native asset directly.
Package-URI discovery is optional there: Flutter may reject
`Isolate.resolvePackageUri`. Keep the native library/Metal resources bundled and
the weights cached; successful Dart source discovery is not native readiness.

All drivers ride the same crate, dylib, and FFI surface
(`native/mlx_native`):

- **laya** — the `aac6fef/laya-mlx` decision op-chain (ModernBERT-large,
  typed `choice`/`score`/`noul` questions, calibrated probabilities in one
  forward pass), exposed through `NativeLayaDecisionEngine` and the
  `LayaDecisionEngine` seam.
- **qwen** — Qwen3 dense checkpoints (0.6B/1.7B, q4 default) with raw
  completion, parity fixtures against the python `mlx_lm` reference
  (`testdata/qwen3_06b_parity.json`), and `LayaQwenChatServer`.
- **lfm2** — LFM2/LFM2.5-Instruct (hybrid conv+attention, flat long-context
  curve) with the fixture-gated chat template + EOS discipline and
  `LayaLfm2ChatServer`. The 2.6B checkpoint rides the same driver
  (`Lfm2ChatTemplateVariant.lfm25_26b` — its template opens the think
  block at the generation prompt; special-token ids resolve from the
  checkpoint's own tokenizer, never guessed across checkpoints).

## Using the engines — three consumption paths

1. **In-process, unified interface** (ADR 0058): a loaded engine binds as
   an `InferenceClient` — the same interface every remote and local
   provider in the monorepo answers to:

   ```dart
   final client = await MlxNativeTextClient.loadLfm2(); // or loadQwen()
   final result = await client.infer(
     InferenceRequest(prompt: '…', systemPrompt: '…', maxTokens: 320),
     toolRegistry: registry, // both casts render tools into their template
   );
   ```

   The client IS the bench's winning cell: template render + EOS stop +
   clean answer text. No raw mode (raw cells are a bench reproduction);
   greedy decode only (a non-zero temperature lands in
   `InferenceResult.warnings`, never silently pretended). Requires a
   process that can load native assets (`dart run`/`dart test`; NOT
   `dart compile exe` — AOT drops them).

   **Seed.** The native engines decode greedily (argmax), so a request seed
   cannot move the draw: the answer is deterministic by construction, not
   seed-derived. The seed is never dropped silently — it is echoed in the
   response meta under `inferenceSeedMetaKey` and reported in
   `InferenceResult.warnings` (ADR 0071's honesty law). There is no
   counter-based sampler here, so no seed is consumed.

   **Structured output.** `request.outputSchema` is supported on
   `InferenceTask.implicitlyStructuredText`: the schema is rendered into the
   prompt (standard JSON Schema, via the core's shared conversion) and the
   model's answer is parsed back into `InferenceResponse.structuredOutput`.
   A markdown fence and surrounding prose are tolerated. This is
   PROMPT-RENDERED, not enforced: there is no server-side and no token-level
   grammar enforcement, so `InferenceTask.nativelyStructuredText` is NOT
   claimed, and an unparseable answer is the named
   `structured_output_unparseable` failure — never a success with an empty
   map.

2. **Wire** — `dart run tool/serve_text.dart [--engine lfm2|qwen]
[--port N] [--raw] [--thinking]` serves the OpenAI-compatible loopback
   (`GET /health`, `POST /v1/chat/completions`); any HTTP client attaches
   (curl, the harness `mlx_local` attach-only client, other languages).
   The default cast is the measured production one (LFM2.5, template+EOS).

3. **Harness / decision product** — the daemon's laya decision lane and
   the `MlxLocalTextClient` wire client; consumers import THIS package
   directly (the laya barrel re-export shim was dropped, ADR 0057 R3).

## The assetId

The cdylib registers as a code asset under
`package:xsoulspace_inference_mlx_native/mlx_native` (built by
`hook/build.dart`; crate, dylib, and C symbols share the `mlx_native` base
name). First build needs cargo, cmake, and the Metal Toolchain
(`xcodebuild -downloadComponent MetalToolchain`); without them the package
still analyzes, its scripted tests pass, and the golden test skips with
that reason. Weights: `LAYA_MODEL_DIR` or `~/.cache/xsoulspace/laya-mlx`;
text snapshots resolve from the HF hub cache (`QWEN3_SNAPSHOT` /
`LFM2_SNAPSHOT` env or explicit dir) — the runtime never downloads
anything by itself. The historical Swift + mlx-swift host remains
documented in git history and stays the reference route for iOS
(ml-explore/mlx#3915).

## Bench and gates

- `tool/serve_text.dart` — the production-line serve binary.
- `tool/model_bench_suite.dart` — the lane bench (chat, decompression,
  swe, tools, laya-decision) over any OpenAI-compatible endpoint or the
  in-process native line; scorecards land in `bench/` and are the palette's
  cited evidence (thresholds pinned in ADR 0057 once two runs exist).
- `tool/test_fresh.sh` — the golden parity cycle (63/63 @ 0.0 / 1.5e-8).

## MTP and the swappable adapter set

[`MTP-GATES.md`](MTP-GATES.md) holds the FROZEN gates for both lines (J-G1..
J-G4 for the MTP lane, K-G1..K-G4 for the adapter lane) and the
pre-registered failure readings. A threshold changes only by editing that
file BEFORE the first run of that arm — it is tracked, so the freeze binds.

**MTP (multi-token prediction, a shared-trunk draft head).** The native
port lives in `native/mlx_native/src/qwen_mtp.rs` (head + chain + decode
loop), with `tests/qwen_mtp_parity.rs` (pinned Python-recorded fixture, no
checkpoint needed) and `src/bin/qwen_mtp_bench.rs` (the interleaved A/B).
The python side is `tool/nursery/mtp_retarget.py` (the arm matrix) and
`tool/nursery/run_mtp_arms.sh`.

Measured 2026-10-21 (`bench/nursery/experiments/RESULTS-mtp-2026-10-21.md`):
acceptance 0.124 decode-consistently (gate 0.60 — FAILS), MTP count
closes at count 1, and the native port is **token-exact** but **0.42x** the
plain greedy decode (gate 1.5x — FAILS).

**The line is CLOSED on physics, and the recorded reason was corrected.**
`src/bin/qwen_marginal_cost.rs` measures the trunk body at 1/2/4/8 positions
with the tied projection timed separately: `body(8)/body(1) = 2.8–3.5` across
runs, so the batched forward is **NOT flat** in position count. The earlier
"nearly flat in k" series had no producing artifact in the tree and was
contradicted by the same document's own forced-execution table. The gate's
verdict is unchanged — MTP-as-speed does not pay on this device at ANY
acceptance — but the reason is now a measured hardware fact rather than a
guess. **No MTP head shape is bought**: attention raises per-head cost without
touching the marginal cost of a verified position, which is the killer. See
[`LINES.md`](LINES.md) Row J and `MTP-GATES.md` Part 2 (corrections C-1..C-10).

**Swappable adapter set.** `native/mlx_native/src/lora_set.rs` is the
runtime selection surface over the single-adapter merge in `lora.rs`:
several adapters for one base, selected at runtime, and provably reversible
(adapter-off == base byte-for-byte). `tests/lora_set_swap.rs` proves the
gates.

**The SET is the wrong shape, and the re-ask says which shape is right**
(`bench/nursery/experiments/RESULTS-adapter-conditioning-2026-10-21.md`,
`RESULTS-adapter-shared-2026-10-21.md`; ledger in [`LINES.md`](LINES.md)
Row K). One adapter trained on **all** the tasks a base will serve, untagged,
with each task keeping **its own option list**, carries both tasks
(+0.24 perm and +0.44 veto over the matched trivial baseline, strict
scoring) while a **single-task** adapter damages the unseen task below
trivial. So the surface stays over-built and is retained only as a
cheap-to-re-derive negative result; the product shape is one adapter per
base. `LoraAdapter::load_auto` detects the on-disk layout (mlx-lm vs PEFT)
and refuses a file in neither — or in both — instead of guessing.

**The answer space is per task by default.** The `shared` arm (one option
list for both tasks) still transfers — so the option list is a _refinement_,
not the mechanism — but it cost ~7–9 points AND leaked 6 % of the veto answers
into the perm family's vocabulary (`abstain` on gold `no_grant`: the same
decision, the wrong words). The rule, stated identically in both result
files: **a shared answer space is defensible only across a semantically
_dissimilar_ group of tasks**, and this lane has not established one — its
two tasks (perm, veto) are BOTH permission requests, so 6 % is an upper
bound. `MTP-GATES.md` Part 4 **L-G7** is the arm that would establish it.

## The acceleration program (Part 4) — and the Python boundary

The mechanism question is closed; what is left is cheap. **L-G1..L-G7** are
frozen in [`MTP-GATES.md`](MTP-GATES.md) Part 4, with their cost and
pre-registered order in [`EXPERIMENT-PLAN.md`](EXPERIMENT-PLAN.md) Part B and
their ledger row (**Row M**) in [`LINES.md`](LINES.md). **L-G1** (few-shot)
and **L-G6** (ranking) are inference-only, cost minutes each, and **either
passing closes the LoRA line** — they run first, and the training arms
(L-G2, L-G7) are bought only if they fail.

| file                                                                 | role                                                                                                                     | status                          |
| -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ | ------------------------------- |
| `native/mlx_native/src/qwen_batch.rs`, `src/bin/qwen_batch_bench.rs` | the batched decode path and its bench (**L-G4**)                                                                         | in the tree (the gate is unrun) |
| `native/mlx_native/src/qwen_rank.rs`, `src/bin/qwen_rank_bench.rs`   | ranking the legal labels instead of generating them (**L-G6**)                                                           | in the tree (the gate is unrun) |
| `tool/nursery/scoring.py`                                            | the **single-definition** scoring module (strict + legacy extractors, matched trivial baseline, coverage, exact McNemar) | in the tree                     |
| `tool/nursery/rank_labels.py`                                        | the ranking arm's labels and scoring (**L-G6**)                                                                          | in the tree                     |
| `tool/nursery/third_task_dataset.py`                                 | the third, dissimilar task's corpus (**L-G7**)                                                                           | in the tree                     |
| `tool/nursery/adapter_conditioning.py`                               | the arm driver (`--only-arms` today)                                                                                     | in the tree                     |
| `tool/nursery/fast_score.py`                                         | the replay scorer — every gate question from the cache, no GPU                                                           | in the tree                     |
| `PYTHON-BOUNDARY.md`                                                 | which Python may move to Rust, and the rule for when                                                                     | in the tree                     |

**The Python boundary is priced, not asserted.**
[`PYTHON-BOUNDARY.md`](PYTHON-BOUNDARY.md) answers "which Python should move
to Rust to accelerate model experimentation" with the lane's own numbers: a
training arm is **≈ 18 min** and the replay scorer is **0.183 s** over the
same 10 cells; the scoring path does not import numpy at all; and the binding
constraint is **bytes per token**, not compute. Only three things are worth
porting — the **generation hot loop** (the batched path, the one unmeasured
lever), the **scorer** (not for speed: to delete a second copy of the gate
rules), and **nothing else yet**. A Rust port of the numerical stack is
**not bought**; the non-example is written down so it is not re-opened.

## The composition API (ADR 0054) — every forward is a declared plan

All three drivers ride the same declared-plan executor and binding table,
and the plan path is the DEFAULT for all of them (opt-outs are A/B switches,
not legacy paths): laya's decision op-chain (R1; `LAYA_COMPILE` additionally
fuses it — opt-in, default flip DECLINED 2026-10-11: the first traced call
per shape costs seconds and break-even is 150+ decisions/shape), Qwen3
decode + prefill (R2/R5, `LAYA_QWEN_PLAN=0` opt-out), and LFM2's hybrid
short-conv/GQA forward (R6, `LAYA_LFM2_PLAN=0` opt-out) — attention KV
buffers and the sliding conv state are both functional plan outputs.

Parity law, mechanically enforced:

- `tests/lfm2_plan_parity.rs` / `tests/qwen_plan_parity.rs` — the plan path
  is bit-identical to the imperative walk on the live model (decode logit
  bits; prefill caches including conv states across a cache-growth boundary),
  and the fixtures pass under BOTH routing modes. R6's gate caught a real
  store-back divergence (full buffers vs trimmed views) before it shipped.
- `tests/plan_op_sweep.rs` — every op kind the drivers submit is
  bit-identical between the direct binding dispatch and the plan executor
  (23 cells, model-realistic shapes/dtypes). A new Op variant adds a cell.
- Plan reviews read JSON: `LAYA_LFM2_PLAN_DUMP` / `LAYA_QWEN_PLAN_DUMP`
  write the per-call plan; `LAYA_DEBUG_DUMP` keeps stage dumps aligned
  between the paths.

Recorded serving non-claims (open items, not regressions): no cross-request
KV common-prefix reuse (fresh cache per generate — the retired Swift engine
had it) and no token streaming.

## Native tool-call transport

Qwen clients default to `ToolCallSyntax.qwenJson`: complete checkpoint JSON
envelopes normalize into `InferenceResponse.toolCalls`, with raw output and
source spans retained in metadata. Missing registries, unknown tool names,
malformed/truncated calls and fenced examples produce named failures.
Constructors accept an explicit `toolSyntax` for a qualified finetune; this
selects the decoder, not a new tokenizer/chat template. The LFM default has
no qualified production decoder for its Python-like signature format and
refuses those envelopes as `tool_syntax_unsupported`. The permissive bench
parser is not an execution parser.

Without explicit messages, native clients use the existing core
`SituationMessagesCodec` to render only the request's projected fragments.
Explicit messages remain authoritative. Qwen tool-result turns use its
fixture-gated renderer; LFM maps explicit tool turns to user turns and warns.
The deterministic transport tests prove normalization and observation
rendering, not useful model coding or real-model acceptance.

## Request-scoped Qwen cancellation

The native FFI exposes an additive request-cancellation API, versioned by
`mlx_native_qwen_cancel_api_version()` (currently `1`). Existing callers can
continue using `mlx_native_qwen_generate`; the new path is for clients that
dispatch blocking generation to a worker and need to cancel one request
without waiting for the model-wide forward lock.

Create the request synchronously with
`mlx_native_qwen_request_create(handle)` before dispatching
`mlx_native_qwen_generate_request(handle, requestId, requestJson)` to the
worker. Call `mlx_native_qwen_request_cancel(handle, requestId)` from the
owning isolate to set that request's cancellation flag, then await the worker
settling and call `mlx_native_qwen_request_finish(handle, requestId)` in
cleanup. Cancellation is observed after the current MLX operation and at
prefill-chunk/decode-step boundaries; an in-flight Metal kernel is not
preempted. A canceled generation returns
`{\"error\":\"cancelled\",\"cancelled\":true}` rather than partial token output.
Clients should probe the API version and retain the legacy generate path when
loading a dylib that does not export the cancellation API.

## Prepared native CLI closure

Developer preparation uses `tool/prepare_native_cli.dart` with four arguments:
compiler, an already prepared SDK package config, output directory, and Dart
entry point. It calls the existing SDK `build cli` and native build hook under
`runBounded`; it does not download weights or create another engine build loop.

Dart 3.13.2 CLI bundles the native code asset but omits the hook's Metal data
asset. The helper finds the producer receipt inside that exact SDK profile,
requires a complete image match, and packages only its colocated Metal file.
For macOS SDK relocation, it reproduces install-ID rewriting and ad-hoc signing
on a private copy and compares every transformed byte; a UUID or filename is
not sufficient. Missing, mismatched or conflicting producer closures refuse.
`bundle/native_closure.json` retains original and relocated image hashes,
producer receipt hash, and Metal hash.

`tool/native_runtime_preflight.dart` is a no-model diagnostic entry point:
it performs harmless NFC through the native asset, uses `dladdr` to report the
actual loaded image, and checks colocated Metal. This qualifies preparation
and identity only. It does not load weights, execute GPU model inference,
qualify other SDKs, or establish coding acceptance. Product integration should
prepare/bundle this closure automatically rather than expose setup commands.

Request-cancellable Qwen scopes share weights but isolate request IDs. A queued
cancelled request now leaves the shared forward-lock queue without waiting for
another model's GPU work. Cancellation during active prefill/decode remains
cooperative at existing boundaries; a caller deadline is not physical settlement.
Hosts must await settlement before unload, replay or fallback, and quarantine
uncertain requests. This admission fix changes no model math or chunk sizes.

## Bounded numeric ranker experiment

`native/mlx_native/src/bin/local_ranker.rs` is an opt-in consumer of the existing
MLX array API: `fit INPUT FRESH_OUTPUT METALLIB` or
`score INPUT FRESH_OUTPUT METALLIB`. It learns a small linear candidate scorer
with explicit per-row normalization and bounded analytic gradients. It has no
network, checkpoint download, process dispatch or product policy. Fit caps are
256 rows,16 candidates,256 features,200 epochs and30 seconds. The artifact
records its input and metallib hashes. Score requests carry features and sealed
weights, without labels. Existing dylib exports and providers are unchanged.

Qualify it with `cargo test --offline --release --bin local_ranker` in the native
crate. `testdata/linear_ranker_parity.json` pins Python-MLX reference logits and
one optimizer step, including its generator source and version. Corpus curation,
feature extraction, held-out evaluation and adoption policy belong to the
harness experiments package (ADR0103), not this numeric tool.

## What this package does NOT buy

The lane's negative results, so a reader does not re-derive them. The full
ledger with the evidence is in [`LINES.md`](LINES.md).

- **An MTP attention head**, and **more MTP acceptance arms** on the current
  head — the line is closed on physics (`body(8)/body(1)` = 2.0–3.5 against a
  1.50 NOT-FLAT gate), and the current head measured a memorizing head
  (in-sample 0.90 vs held-out 0.12).
- **A 4-bit dequant→merge→requant path** — no consumer, and the requantization
  error is the same order as the adapter delta.
- **A rank / target-module sweep on the adapter** — it optimizes an unknown
  before the product-shape question is closed.
- **A `Task:` tag as the conditioning mechanism** — not significant against
  the untagged control (perm p=0.185, veto p=1.000), both estimates negative.
- **A shared answer space across semantically dissimilar tasks — UNESTABLISHED.**
  The per-task list is the default; the exception has not been measured, and
  the 6 % leak on the (semantically close) perm/veto pair is an **upper
  bound** for it. **L-G7** is the arm that would establish it.
- **A Rust port of the numerical stack** — see
  [`PYTHON-BOUNDARY.md`](PYTHON-BOUNDARY.md): the scoring path is 0.183 s,
  numpy is not on it, scipy and pandas are absent from the lane, and a port
  would add a second copy of the rules.
