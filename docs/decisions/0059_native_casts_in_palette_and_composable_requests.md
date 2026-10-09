# ADR 0059: The native casts join the harness palette and the request surface composes

Date: 2026-10-10
Status: Accepted
Related: 0056 (landscape; cast verdicts), 0057 (engine host; bench),
0058 (InferenceClient binding); harness-side context: ADR 0043 (model
palette), ADR 0025/0036 (composition root), oka ADR-0006/0010 (typed
declarative composition — style reference, not a dependency)

## Context

Owner directive (2026-10-10): (1) integrate qwen, laya and lfm into the
ecsai_harness palette and add them as options in Last Answer, with a
correct testing strategy including dogfooding; (2) analyze and improve
`xsoulspace_inference_core` so its syntax composes — oka-like — and
makes it convenient to pass the parameters each cast actually needs.

Verified state before this ADR:

- The harness palette (ADR 0043) declares `laya` (decision, natively
  served by the daemon since the python retirement) and `mlx_local` (a
  bounded-generative declaration **with no daemon binding** — the
  `mlxTextBinding` wire lane exists but `harnessd.dart` never registers
  it, so the entry is a dead declaration for actor casts).
- ADR 0058 gave the engine host a real `InferenceClient`
  (`MlxNativeTextClient`), but it is EAGER: the engine must be loaded
  before construction. Every composition point that wants a native cast
  must therefore load weights at startup — wrong for a bounded
  last-in-order lane that is used only on explicit cast, and wrong for
  a GUI app whose startup must not block on a 1 GB weight load.
- `InferenceRequest` carries `maxTokens`/`temperature`/`stopSequences`
  as flat fields, but has no `thinking` carrier, no conversation
  surface (`messages`), and no derivation (`copyWith`); the two factory
  bodies (`text`/`structured`) duplicate the field list. Per-cast knobs
  (Qwen's `enable_thinking`, the LFM2.5 2.6B reasoning-budget law)
  could only ride client CONSTRUCTION, so flipping one required
  rebuilding the client.

## Decision

### 1. Palette: two named native casts replace the dead declaration

`model_palette.dart`: `mlx_local` is RETIRED (it never had a daemon
binding; the wire-lane client `MlxTextBinding`/`mlxTextBinding` stays
exported for the optmem drafting lane and explicit attach consumers —
they do not reference the palette id). Two bounded-generative entries
replace it, ordered after `apple_foundation_afm` (the generative order
IS the mover preference; local bounded casts stay LAST — never an
implicit mover):

- `lfm` — LFM2.5-1.2B-4bit in-process (the production cast, ADR 0056
  verdict).
- `qwen` — Qwen3-0.6B-4bit in-process (the fast small cast).

`laya` is unchanged (decision kind, first in the decision tier). The
daily-cast floor logic, `entryIdForRole`, and rebind law are untouched:
two more generative members raise the computed floor by construction.

`daemon_palette_selection.dart`: the known-entry set and the no-key
admit list gain `lfm` and `qwen` and lose `mlx_local`.

`harnessd.dart`: registers real bindings for both entries (lazy
clients; a stderr line declares them — load happens on first cast) and
gives each its own generation resource key (`lfm`, `qwen`) so the local
lanes never ride the hosted transport budget.

### 2. The native client learns to load lazily and to converse

`MlxNativeTextClient` gains lazy constructors (`lazyQwen`, `lazyLfm2`)
over the same private core: `load()` performs the engine load exactly
once (memoized, never throws — a failed load is recorded); before a
successful load `isAvailable` is false and `infer` returns the typed
`unavailable` failure (`retryable: true`), never a socket error or a
hang — the palette's declared law for detached local runtimes. The
eager factories stay (bench, tests, serve_text).

The client also consumes two request-level fields (Decision 3):
non-empty `messages` render as the full conversation (multi-turn chat
through `renderQwenChatPrompt`/`renderLfm2ChatPrompt`); a request-level
`thinking` overrides the constructor default on the Qwen cast and
produces an honest warning on the LFM2.5 cast (no thinking switch).

### 3. Core: the request surface composes (oka-style value objects)

Additive, non-breaking — the `InferenceClient` interface itself does
not change, so no implementer breaks:

- `GenerationOptions`: a const-constructible, immutable value object
  (`maxTokens`, `temperature`, `stopSequences`, `thinking`) with
  `copyWith` — the small typed bag a consumer composes once and
  attaches anywhere. `InferenceRequest.generationOptions` views the
  flat fields through it (single storage: the map; no parallel truth).
- `InferenceRequest` gains `thinking` (a request-level reasoning
  switch — Qwen renders `enable_thinking`, hosted providers map it to
  their reasoning controls), `messages` (`List<ChatMessage>` — the
  conversation surface native chat renders directly), and `copyWith`
  for derivation. The duplicated `text`/`structured` factory bodies
  collapse into one private builder.
- `ChatMessage` (`ChatRole` system/user/assistant/tool + content): the
  minimal conversation value; JSON round-trips for wire transports.

Non-claims: `ProvisionableInferenceClient` stays non-adopted (ADR 0058
reason stands); no breaking change to any existing factory or to the
`InferenceClient` interface; model-specific vocabulary (LFM2.5 template
variants) stays in the provider package — core carries only casts every
provider can mean (thinking, budget, stop, tools).

### 4. Last Answer: the casts become RUNTIME options

`HarnessHostConfig.buildBackend` gains `lfm` and `qwen` backends bound
through the afm composition root's new `lfmTextBinding()` /
`qwenTextBinding()` factories (afm is the composition root per ADR
0036; LA imports afm). The agent-doc RUNTIME row gains two chips —
`LFM · local` and `Qwen · local`, shown on macOS only (the native
engines are Metal/Apple-Silicon; other platforms keep today's five
options). No consent gate: local casts are loopback/in-process with no
egress, same policy as `laya`.

### 5. Testing: contract tests plus dogfooding at two depths

- Core: unit tests for `GenerationOptions`/`ChatMessage`/`copyWith`/
  `thinking` round-trips (no engine).
- Engine host: lazy-client contract with the REAL engine behind the
  existing skip gates — unavailable-before-load, load-once, typed
  fail on a missing snapshot, multi-turn render, request-level
  thinking override and the LFM2.5 warning.
- Harness: palette construction (order, kinds, floors), selection
  known-set/no-key admits, binding registration in the composition
  root.
- Dogfood depth 1 (in-process, the LA path verbatim): `HarnessEmbed`
  started with the REAL lfm binding over a throwaway workspace;
  `newSession` + one `delegateTask` turn must return text generated by
  the native engine — the same embed seam the Last Answer app runs.
- Dogfood depth 2 (the real daemon): `harnessd.dart` boots with the
  full palette; the stderr lane lines name the declared casts. The
  depth-1 embed run plus the depth-2 boot together cover the two
  consumption paths ADR 0058 declared; a full GUI walkthrough stays a
  manual operator step (recorded, not claimed).

## Consequences

- Actor casts can name `lfm`/`qwen` in the daemon and Last Answer; the
  bounded-local law holds (last in order, explicit cast only).
- Composition roots stop paying startup weight for lanes nobody cast.
- Per-cast knobs ride the request; clients stop being rebuilt to flip
  one switch.
- The `mlx_local` palette id disappears from selection surfaces; the
  wire lane remains as a library capability (optmem unaffected — its
  `providerId: 'mlx_local'` label is its own record vocabulary).

## Evidence

All measured 2026-10-10.

- Core: `xsoulspace_inference_core` suite **73/73** (new
  `inference_request_compose_test.dart` covers options/chat/copyWith/
  thinking round-trips and factory agreement); `dart analyze` clean.
- Engine host: `xsoulspace_inference_mlx_native` suite **21 pass /
  2 skip** plus the new lazy-client suite **4/4** — unavailable-before-
  load, typed retryable fail with the recorded load error on a missing
  snapshot, real lazy load → infer, real multi-turn conversation
  (assistant 'blue' recalled through `messages`), thinking=true honored
  on qwen with no warning and warned on lfm2 (`no thinking switch`).
- Harness: `daemon_palette_selection` 26/26 (entry lists now end
  lfm, qwen; no-key admits the local casts), `native_text_binding`
  3/3 (lazy composition, named router keys, `HARNESS_*_ENGINE=off` →
  null router), `actor_autonomy` 4/4 (the two-cast palette lifts the
  computed floor to 7; the first overflow fits, the second bounces
  `actor_budget_exhausted`), `model_palette` + `palette_invocation`
  green.
- Last Answer: `harness_host_native_text_test` **5/5** (buildBackend
  registers both casts, local = key-free, copyWith swap/clear, stop()
  disposes config-held bindings); `flutter analyze` coding_agent + doc:
  0 errors/warnings (24 pre-existing infos in untouched files).
- Dogfood depth 1 (in-process, the LA path verbatim): REAL
  `HarnessEmbed` bound to `lfmTextBinding()`, throwaway workspace,
  `newSession` + one `delegateTask` turn — native LFM2.5-1.2B loaded
  lazily on first cast and the turn completed
  **`AcpStopReason.endTurn` with model text on the surface (~34-41 s
  wall including the weight load)**, battery power. First runs of this
  test surfaced the metallib crossed-pair incident — see ADR 0060.
- Dogfood depth 2 (the real daemon): `harnessd.dart` boot lines —
  `[harnessd] laya decision lane: native model serving at
  http://127.0.0.1:63881 (loaded in 3673ms)` / `[harnessd] local text
  casts declared: lfm, qwen (lazy native engines; load on first cast)` /
  `[harnessd] palette: laya:decision, open_router:generative,
  jev:decision, apple_foundation_afm:generative, lfm:generative,
  qwen:generative maxActors=7`. The full GUI walkthrough remains a
  manual operator step (recorded, not claimed).
