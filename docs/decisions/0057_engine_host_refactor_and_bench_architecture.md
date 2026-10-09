# ADR 0057: Engine-host refactor (dependency inversion), production-line palette, and the model bench architecture

Date: 2026-10-09
Status: Proposed (analysis + rung plan); the cheap-gap and bench increments of this ADR land immediately, the physical package move is rung-gated
Related: 0051 (engine), 0054 (composition API), 0055 (qwen-on-plan, hard laws), 0056 (landscape)

## Context

The user's directive: (1) analyse the correct refactor — everything
(qwen, laya, lfm) now lives in one `xsoulspace_inference_laya` package,
which breaks dependency inversion; (2) swap napbench to the native
production line, retire python to benchmark + goldens roles, switch the
harness to the new line, and design the model palette + benches for the
real questions (chat, decompression, SWE) — small and fast; (3) resolve
the owned bottlenecks in order.

## Part 1 — the dependency-inversion break, and the target shape

### What is wrong (verified)

- `xsoulspace_inference_laya` ("Local Laya decision-model runtime
  composition", per its pubspec) hosts: the MLX FFI layer
  (`native/laya_rust/src/mlx.rs`), the composition API (`plan.rs`,
  `bindings.rs`), the byte-level BPE tokenizer (`bpe.rs`), TWO generic
  text-model drivers (`qwen.rs`, `lfm2.rs`) with their Dart FFI clients
  and chat server, the consolidated bench (`model_bench.rs`), and the
  native-assets build hook. The dependency arrow is inverted: the
  product package became the platform host, so every generic-engine
  change rides the laya product's gates, and no other package can
  consume a text engine without depending on a product named "laya".
- The monorepo now runs THREE text engines for the same job
  (load checkpoint → greedy/temperature generate):
  `laya_native` (Rust, mlx-c, this ladder), `mlx_text_native` (Swift
  via SPM, `xsoulspace_inference_mlx`), and python `mlx_lm.server`
  (retirement in flight, ADR 0056). Duplicated responsibility: two
  native dylibs, two Dart FFI client layers, two chat-server
  implementations.
- Convention evidence: this monorepo's inference family is
  provider-per-package (`xsoulspace_inference_whisper_cpp_flutter`,
  `xsoulspace_inference_vosk_raw`, `xsoulspace_inference_gemma_flutter`,
  …) over `xsoulspace_inference_core` ("Provider-agnostic inference
  interfaces"). The engine violates the convention it sits inside.
- Consumers (pubspec path deps): `laya` ← harness `afm` +
  `experiments`; `mlx` ← harness `afm` + `optmem`. The blast radius of
  any package move is exactly two harness packages, both funneling
  through afm.

### Verified inventory (explored 2026-10-09)

- The laya package carries a SECOND, dead-on-macOS native tree:
  `native/laya_native/` (Swift/SPM, iOS reference) alongside the active
  Rust crate — the same engine responsibility in two languages inside
  one package. Disposition at R1: delete (the Swift engine line is
  owned by `xsoulspace_inference_mlx`; a stale reference tree is drift,
  not an asset).
- The wire-server responsibility is duplicated generically:
  `LayaQwenChatServer` (laya, engine-bound) vs `MlxChatWireServer`
  (mlx, endpoint-agnostic) — both loopback `/health` +
  `/v1/chat/completions` over the shared `LoopbackJsonServer`. Target:
  the ENDPOINT abstraction wins; engine packages expose chat endpoints,
  one generic wire server composes them (consolidation lands with the
  engine package's Dart surface).
- The tokenizer is duplicated too: `LayaByteLevelTokenizer` (pure-Dart)
  vs `bpe.rs` (Rust). The Dart one predates the native path; post-R1 it
  shrinks to a test/prompt-encoding helper, recorded honestly.
- Two parallel FFI engine stacks (Rust/mlx-c `laya_native` vs
  Swift/mlx-swift `mlx_text_native`) target the SAME checkpoints —
  this is R4's consolidation decision, confirmed real.
- Python's remaining roles today are already bench/goldens
  (`py_decode_scaling.py`, `gen_qwen3_parity_fixture.py`,
  `lfm2.rs`'s venv reference) plus `MlxServeRuntime`'s python spawn
  DEFAULT executable (attach-only, spawn opt-in) — the serving-role
  defaults are being retired alongside this ADR.

### Target shape

One engine host, products depend on it:

- **NEW `xsoulspace_inference_mlx_native`** (name provisional) — the
  engine host package: the Rust cdylib (moves wholesale, gates with
  it), MLX FFI, composition API, tokenizer, MODEL DRIVERS (qwen, lfm2,
  and the laya fw13 op-chain as a driver), Dart FFI clients, the bench
  bins, and the native-assets build hook. Knows no product. The assetId
  changes with the package (`package:xsoulspace_inference_mlx_native/…`)
  — a one-cycle mechanical break, versioned.
- **`xsoulspace_inference_laya` shrinks to the laya product**: decision
  server/provider/async engine, prompts, serve runtime composition —
  depends on the engine package like any consumer. The laya decision
  model keeps its parity gates; they run in the engine package where
  the driver lives.
- **`xsoulspace_inference_mlx`** keeps its product surface (the
  harness's text-lane client, `MlxLocalTextClient`) as the Swift-lane
  provider. Consolidation decision (rung-gated, ADR then): port the
  Swift driver into the engine host as a second backend behind the
  binding table (`ChipFamily`/`Backend` is exactly that seam), or keep
  the provider split and accept the duplication. The composition API
  exists to make this a driver port, not a rewrite — but it is not this
  ADR's decision.
- **Python**: retired to (a) benchmark reference legs and (b) golden
  fixture recording only — never a serving path (the swap itself is
  delivered alongside this ADR; see the py-retirement doc).

### Migration rungs (each gated, each shippable)

- **R1 — create the engine package by moving.** `git mv`
  `native/laya_rust` + the build hook + the generic Dart FFI clients;
  DELETE the dead `native/laya_native` Swift reference tree (the Swift
  engine line lives in the mlx package); update assetIds and imports
  mechanically; the entire parity battery (7/7 rust, dart suite,
  test_fresh 63/63) re-runs green in its new home before anything else
  moves. laya re-exports the moved symbols for one deprecation cycle.
- **R2 — flip laya to a consumer.** laya's pubspec takes the engine
  package; its lib keeps only product surface; harness afm/experiments
  keep compiling untouched (re-exports absorb them).
- **R3 — drop the shims; consumers import the engine package
  directly.** (afm, experiments, optmem-side consumers as applicable.)
- **R4 — mlx Swift-lane consolidation decision** (separate ADR, driver
  port vs provider split).

Non-goal: merging `xsoulspace_inference_core` (interfaces stay where
they are; the engine package implements against them where applicable).

## Part 2 — production line, palette, and the bench architecture

### Production line (delivered with this ADR)

Serving = the native in-process engines behind the loopback wire;
napbench and the model bench measure that line; python is the
reference/golden tool only. The harness's `mlx_local` binding is
attach-only by default (verified: `mlx_binding.dart`), so the switch is
"the native server owns the endpoint", not a harness rewrite.

### Palette upgrade (design)

The palette's laws stay (laya decision lane leads; `mlx_local` bounded
generative rides LAST — order is the mover preference). Three additions,
kept small:

1. **Named casts per lane**: the palette entry's doc names which local
   engine serves which role — `lfm25` (instruct, chat-template + EOS) for
   conversational and compression casts, `qwen` (raw completion) for
   mechanical/drafting casts. Both are the same wire; only defaults
   differ.
2. **Bench reference on the entry**: a one-line pointer from the palette
   entry to the current bench scorecard (see below), so a casting
   decision cites measured pass rates, not vibes. Static pointer in
   palette docs — the scorecard itself is a build artifact, never
   world data.
3. **Chat-template awareness at the server layer** (not the palette):
   the OpenAI-compatible route renders the model's chat template
   (LFM2.5's, gated against the venv reference) so wire consumers get
   instruct-model quality without knowing the template exists.

### The bench architecture (small and fast)

One runner, three lanes, wire-level (model-agnostic — it benches
whatever endpoint the palette casts, native or otherwise). Design
constraints from the directive: concise, small, fast — the whole suite
runs in minutes on the 1.2B class, zero LLM judges, deterministic
checkers.

- **Lanes and checks** (cases live as data, `testdata/bench/*.json`):
  - `chat` (~10 cases): short factual QA + 2–3-turn retention; checker =
    key-term/answer containment + wall-time budget. This is the
    "questions like in this chat" lane.
  - `decompression` (~10 cases): the harness's middle-out role —
    realistic memory/beat records in, ≤280-byte one-line summary out;
    checker = length cap + entity recall (the nap-prompt shape napbench
    already uses, generalized).
  - `swe` (~5 cases): tiny executable code tasks; checker = compile +
    run against hidden asserts in a sandboxed process with a timeout.
    The strongest "can the local model do mechanical SWE" signal.
- **Runner**: `tool/model_bench_suite.dart` in the engine package —
  takes `--endpoint` (default: the native line), runs lanes, emits
  `bench/scorecard-<date>.json` + a markdown table (per-lane pass rate,
  p50 wall, tok/s).
- **Gate law**: thresholds are advisory until two runs are recorded
  (unmeasured numbers are non-claims), then pinned here. The scorecard
  is the palette's cited evidence.

## Part 3 — the bottleneck ladder (resolutions, in order)

1. **Decode = weight-read bandwidth → speculative decoding, draft-model
   lane.** The self-draft lane is dead (ADR 0055 napbench:
   LFM2.5 16-block self-draft fails faithfulness). The lane here is a
   SMALL DIFFERENT draft: Qwen3-0.6B drafts k tokens, Qwen3-1.7B
   verifies in one batched forward — greedy verify is token-EXACT, so
   the gate is self-consistency (draft+verify output == target-only
   output) plus the tok/s A/B, no new fixture needed. KV rollback is
   cheap because caches are functional (save the array handles + offset
   before verify, restore on rejection). Lands as its own rung.
2. **Prefill = compute-bound → resolved by policy, not kernels.** q4 is
   already the default (2× bf16 decode, measured), prefill already
   chunks (2048), and the compute wall is silicon — the resolution is
   the recorded policy: keep prompts ≤2k on dense models or cast the
   hybrid (see 3); revisit only when prefillTTFT becomes a product
   complaint with a named prompt size.
3. **Dense long-context falloff → architectural answer already shipped.**
   LFM2.5's flat curve (70→64 tok/s fresh→2k, measured, ADR 0055) IS
   the resolution; the policy row: long-context casts name the hybrid.
4. **Cheap product gaps → landed with this ADR** (subagent run):
   opt-in EOS stop (natives; default off so every oracle stays
   byte-identical), LFM2.5 chat template + chat server (fixture-gated
   against the reference render), async generate (isolate escape for
   the blocking FFI call).
5. **Every new architecture = Rust port with a parity fixture → standing
   process law** (the LFM2 rung is the template: venv reference →
   fixture with provenance → bit gate). Restated here so the refactor
   doesn't lose it: the fixture lives with the driver in the engine
   package.

## Non-claims

- The physical package move (R1–R3) is NOT done in this ADR — the
  analysis and gates are the deliverable; the move is rung-gated and
  lands after this session's increments (which touch the packages
  being moved).
- The mlx Swift-lane consolidation is explicitly undecided here (R4).
- No speculative-decoding numbers yet — the rung is named, not
  measured.
- Bench thresholds are unmeasured until two scorecards exist.
