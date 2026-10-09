# ADR 0057: Engine-host refactor (dependency inversion), production-line palette, and the model bench architecture

Date: 2026-10-09
Status: R1+R2 Accepted and executed (2026-10-09); R3 (shim drop) and R4
(mlx Swift-lane consolidation) remain rung-gated. The cheap-gap and bench
increments of this ADR landed with the original proposal.
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

### Why not one package per model (owner question, 2026-10-09)

Splitting qwen/lfm2/laya into three packages would re-create the
problem it fixes. Native assets are built and registered PER PACKAGE:
one package per model means either N dylibs loaded in one process
(duplicated mlx, duplicated weight loaders, N registries) or a shared
package pretending to hold them — the engine-host shape. The drivers
(qwen.rs, lfm2.rs, the laya op-chain) share one crate, one dylib, one
binding table and one composition API; that sharing IS the engine, so
the drivers live together and the PRODUCTS split. "Rename laya" alone
is insufficient for the same reason: renaming to "engine" leaves the
laya decision product homeless — the split is engine-host + laya
product (two packages), with the mlx Swift lane's consolidation as the
separate R4 decision.

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

## Evidence (2026-10-09, this session)

- **R1+R2 executed — the engine host is its own package.** The new
  `pkgs/xsoulspace_inference_mlx_native` received (git mv, history
  preserved): the whole `native/laya_rust` crate, the build hook, the
  engine lib surface (`laya_native_decision_engine`, qwen/lfm2 FFI clients
  + chat templates, byte-level tokenizer, async decision engine,
  `laya_prompt`), the seven native test files + golden fixtures, the
  engine tools (`test_fresh.sh`, `build_msl.sh`, `q8_bench.dart`,
  `model_bench_suite.dart`, `gen_qwen3_parity_fixture.py`,
  `probe_swift_fw13.dart`, `frame_gate.swift`, `regenerate_golden.dart`),
  `testdata/bench`, and `benchmark/laya_native_benchmark.dart`. One
  inventory deviation from the proposal, ADR-consistent: the dead Swift
  reference tree `native/laya_native` was DELETED per the R1 disposition
  above (not moved), together with `tool/build_laya_native.sh` whose only
  target it was. A second deviation, forced by acyclicity: the decision
  seam (`laya_decision_server.dart` — query/result types, engine
  interfaces, scripted engine, wire server) moved engine-side too, because
  the moved engine files import it and the engine must not depend on the
  product (the proposal listed it as staying; pub forbids the cycle the
  shim would create). Every `assetId` moved: 11
  `package:xsoulspace_inference_laya/laya_native` →
  `package:xsoulspace_inference_mlx_native/laya_native` (5 decision
  engine, 3 qwen client, 3 lfm2 client), the three package-uri
  resolutions re-pointed, `test_fresh.sh`'s hook-cache paths re-keyed to
  the new package name; the crate/dylib base name `laya_native` stays this
  rung (recorded debt). R2 shim: laya's barrel re-exports the engine
  barrel (with the R3 drop note), laya's pubspec takes the engine path dep
  and sheds `ffi`/`code_assets`/`data_assets`/`hooks`; harness afm +
  experiments compile unchanged. Gates (all green, M1): cargo test
  --release 22 passed / 0 failed (11 ignored by pre-existing probe
  attributes; lib 11, lfm2 4 incl. 700M, qwen3 3, plan 2, spec 1, drift
  1); dart test in the engine package 12 passed / 2 skipped and in the
  shrunk laya product 20 passed / 1 skipped — the pre-split set (32/3)
  exactly, split across the two homes; `tool/test_fresh.sh` 63/63 on both
  eager (prob error 0.0) and `LAYA_COMPILE=1` legs (1.5e-8); `dart
  analyze` clean in both packages;
  `dart analyze pkgs/xsoulspace_agentic_afm
  pkgs/xsoulspace_agentic_experiments` in the harness — no new issues (9
  pre-existing style infos in afm's own `laya_permission_policy` files);
  `model_bench_suite.dart --in-process laya` 16/16 (the moved decision
  engine end-to-end). New `tool/serve_text.dart` is the production-line
  serve binary (`--engine qwen|lfm2`, `--raw`, `--port`). One latent bug
  the move exposed and this rung fixed: several engine tests called
  `gpu()` before pinning the metallib — the pinning is process-global but
  device/stream init is lazy, so a `gpu()`-first process died at stream
  setup (mlx-c exits via its default error handler); ordering now pins
  first (lfm2_parity ×3, qwen3_parity, qwen_plan_parity ×2,
  qwen3_drift_probe), making the cargo suite deterministic at any
  checkout path.

- **Bench scorecards (first two runs, both casts, Apple M1, AC):**
  qwen-0.6B raw-completion cast: chat 3/10, decompression 0/10
  (byte-cap/one-line violations), swe 0/5 (format breaks) at ~94–100
  tok/s p50 — speed present, instruction-following absent.
  LFM2.5-Instruct cast (fixture-gated chat template + EOS stop [7,2]):
  chat **7/10**, decompression **9/10**, swe **3/5** at 22–40 tok/s.
  The template+EOS discipline IS the quality lever; the instruct cast is
  the production line for conversational/compression/SWE lanes.
  Thresholds remain advisory until two same-cast runs exist.
- **Cheap gaps landed (commit 3ed54164):** opt-in EOS stop (native
  default OFF — every parity fixture byte-identical; new FFI-driven EOS
  gate), LFM2.5 chat template (venv-recorded reference renders, byte-
  exact; ChatML subset non-claims recorded), `LayaLfm2ChatServer`
  (template + EOS on the loopback wire), async generate (isolate escape;
  no decode parallelism — recorded). Gates: dart suite 31 pass/3 skip,
  rust 8/8, test_fresh 63/63 @ 0.0/1.5e-8.
- **Speculative decoding (bottleneck 1) — mechanism landed, pair
  measured UNPROFITABLE.** `generate_greedy_speculative` (draft k-token
  propose + ONE batched target verify; offset-arithmetic rollback —
  slice-update buffers make it exact): token-EXACT vs plain greedy on
  every leg (the gate). Interleaved same-process speed, Qwen3-0.6B
  draft → 1.7B target, k sweep: k=2 0.42×, k=3 0.45×, k=4 0.63× (clean
  two-leg mean), k=6 0.75× — all < 1×. Why: greedy acceptance beyond
  the first token is low AND a 0.6B draft step costs ~40–45% of a 1.7B
  target step. Verdict: bottleneck 1's resolution remains "smaller
  weights" (q4 default, shipped); the speculative lane REOPENS only
  with a target:draft size ratio ≥ ~4:1 (e.g. an 8B-class local model
  with a 1.2B draft) AND a draft-acceptance probe run first. Cross-run
  comparisons are thermal-contaminated (plain leg 27→6 tok/s across
  consecutive runs) — interleaved law holds.
- Prefill (bottleneck 2) and long-context (bottleneck 3): resolved by
  the policy rows above (q4 default + 2k chunks; the hybrid for long
  context), no new work.
- **Python retirement (commit ebe3e63e + harness 6a1d438; the role
  table lives in `docs/py_retirement_2026-10-09.md`):** serving-role
  defaults flipped native-first (attach-only law untouched; explicit
  `*_MLX_SPAWN=1` escape hatches remain, labeled); napbench confirmed
  native-only; live wire proof — native chat endpoint → loopback wire
  server → `MlxLocalTextClient` completion with ZERO `mlx_lm`
  processes. Python keeps exactly two roles: benchmark reference legs
  and golden fixture recording.

- **Bench-methodology correction (owner review) — the 2×2 matrix.** The
  first comparison crossed two variables (model AND serving shape) — a
  confounded diagonal. Corrected design: same lane files, same checkers,
  four cells — {qwen, lfm2} × {raw, template+EOS}. Results (M1, AC):
  chat | decompression | swe — qwen raw 3/10 | 0/10 | 0/5; qwen
  template+EOS 4/10 | 8/10 | 1/5; lfm2 raw 4/10 | 0/10 | 1/5; lfm2
  template+EOS 7/10 | 9/10 | 3/5. Attribution: TEMPLATE+EOS IS THE
  DOMINANT FACTOR — within-model raw→template moves decompression
  0→8 and 0→9 respectively (the byte-cap/one-line/stop-at-turn-end
  discipline is serving shape, not model quality); the model adds the
  rest (lfm2-template 7/9/3 vs qwen-template 4/8/1 — that cell still
  mixes size 1.2B vs 0.6B, so it is the product choice, not a
  controlled variable). The bench carries `--raw` to reproduce any
  cell; the qwen3 template renderer is fixture-gated byte-exactly like
  the lfm2 one (venv `apply_chat_template`, enable_thinking=false).
- **Base-name debt resolved (2026-10-09, later the same session):** the
  crate/dylib/asset base name `laya_native` recorded as debt above is
  renamed to `mlx_native` — crate dir `native/laya_rust` →
  `native/mlx_native`, dylib `libmlx_native.dylib`, assetId
  `package:xsoulspace_inference_mlx_native/mlx_native`, all 11 C ABI
  symbols `laya_native_*` → `mlx_native_*`. The Dart FILE/class names
  (`laya_native_decision_engine.dart`, `NativeLayaDecisionEngine`, …)
  are KEPT — they name the laya decision MODEL driver, which is
  semantically correct, not shared infrastructure.
### The Swift line: benchmark/reference layer only (owner decision, 2026-10-09)

The Swift engine (`xsoulspace_inference_mlx`'s `mlx_text_native`) is
NOT a production serving path. Production serving = the Rust engine
host (in-process clients or `tool/serve_text.dart` in the engine
package, which serves the same loopback wire the harness `mlx_local`
attaches to). The Swift engine survives as a benchmark/reference leg
(napbench's in-process engine, comparison rows) and no new capability
lands in it; its full retirement folds into R4 — either the driver
ports behind the binding table or the dylib is dropped. Rationale: two
production engines for the same checkpoints double every gate, and the
Rust host is the one with the parity fixtures, the composition API,
and the chat-template serving layer.

## Non-claims

- R3 (shim drop) and R4 (mlx Swift-lane consolidation) are NOT done —
  consumers still import `xsoulspace_inference_laya` and are absorbed by
  the R2 shim.
- The mlx Swift-lane consolidation is explicitly undecided here (R4).
- The speculative mechanism is landed and token-exact, but no
  profitable pair exists on this machine — the 0.6B→1.7B lane is
  measured 0.42–0.75×; no production route uses it.
- Bench thresholds are unmeasured until two scorecards exist.
