# ADR 0025 — The host layer is a package: one canonical daemon/CLI surface, providers stay thin

- Status: Accepted
- Date: 2026-09-06
- North Star impact: `amends` — refines the layering of ADR 0015 (domains
  live in hosts) by naming the missing LAYER (the host/transport layer) and
  giving it a home. Does not conflict with any ADR; it completes 0012/0015.
  This ADR was forced by a structural audit: the host layer was homeless
  and had squatted in whichever package was the tip of the research spear.
- Builds on: [0012](0012_extract_agentic_harness_package.md),
  [0015](0015_domains_live_in_hosts_core_stays_generic.md),
  [0023](0023_filesystem_projection_target_edit_as_rederivation.md)

## Context

The agentic stack grew a structural inversion while landing research stages:

- `xsoulspace_inference_apple_foundation` — nominally a *provider* (an FFI
  bridge) — had become the de-facto application: 13 `bin/` stage-gate CLIs,
  the `harnessd` ACP daemon, the coding-agent runner core, the intent-closure
  driver, and 8 of its tests.
- `xsoulspace_inference_openrouter` — a pure HTTP client — imported the
  harness engine in its library code.
- The engine (`xsoulspace_agentic_harness`) shipped the benchmark rig
  (`lib/src/benchmark/`, `benchmark_api.dart`) as part of the engine barrel.
- There was NO package an app (e.g. `last_answer`) or a pi extension could
  embed: embedding meant importing a provider package, which dragged FFI,
  Swift, benchmark suites and experiment arms with it.

Root cause: **the host/application layer (transport + host policy) was
homeless**, so it accreted into whichever package was currently the tip of
the research spear — first the harness (`cli_host`, benchmark rig), then
apple_foundation (runner, daemon, 13 bins). Every backend re-duplicated the
same plumbing seam (arg parsing → backend load → loop → report), and every
stage gate added a new bin instead of data.

## Decision

1. **`xsoulspace_agentic_host` is the host layer** (new package). It owns
   TRANSPORT + HOST POLICY only (D5):
   - `HarnessAcpBackend` — the `harnessd` ACP agent (world-per-workspace,
     snapshot store, deny-by-default permissions, real cancellation,
     bounded monotonic escalation);
   - `runHarnessdCli` — the ONE canonical daemon CLI (stdio + unix-socket
     transports, single-instance lock, idle exit);
   - `runCodingAgentOnce` / `taskFromSentence` — the coding runner core;
   - `intent_closure_runner`.
   The host learns NO provider and NO app.

2. **Backends are injected as `HarnessBackendBinding` entries** — a
   composition root (a thin bin in a provider package, an app, or a test)
   binds a backend name to `{buildRouter, cancelActiveGeneration,
   defaultModel}`. The daemon refuses unresolvable backends with named
   data instead of hanging. No provider code in the host; no host code in
   providers.

3. **Embedding is one import, two shapes:**
   - **SDK (in-process):** an app creates `HarnessAcpBackend(bindings: …)`
     and drives `session/new` → `session/prompt` → streamed updates
     directly (last_answer's daemon lifecycle in-process, per its ADR 0003).
   - **ACP (out-of-process):** a CLI/extension runs the daemon (`runHarnessdCli`)
     and attaches over stdio or the unix socket — same surface, same
     vocabulary, no second protocol (ADR 0003 last_answer / N4 invariants).
   The provider-less `bin/harnessd.dart` in the host package works
   out of the box in `--scripted` and `--remote-mover` modes (no mover
   model needed); provider composition roots only add bindings.

4. **Providers go thin.** `xsoulspace_inference_apple_foundation` keeps only
   the FFI transport, the native-asset build, and its `harnessd`
   composition root. All stage-gate bins that had already published their
   rows (`gate_run_afm`, `r7e_afm_gate`, `coding_suite_*` probes,
   `act_with_project_afm`, `apple_foundation_cli`, `agent`, `intent_closure_afm`,
   `stress` REPL wiring) are DELETED — results docs preserve the evidence;
   the charter deletes completed scaffolding.

5. **Non-goals (follow-ups, recorded not done):**
   - The benchmark rig still lives in the harness (`lib/src/benchmark/`,
     `benchmark_api.dart`); extracting a `xsoulspace_agentic_benchmarks`
     package is deferred until a second backend-suite consumer exists
     (three-failures rule). The per-backend suite bins were deleted; a
     shared scenario-spec driver replaces them when the rig is next run.
   - `xsoulspace_inference_openrouter` still imported the harness for the
     situation→messages codec — RESOLVED by
     [ADR 0026](0026_workspace_domain_specs_as_data_wire_codec.md): the
     protocol + codec live in `inference_core`; openrouter is pure.

## Consequences

- `last_answer` embeds `package:xsoulspace_agentic_host` (+ the AFM client
  binding) instead of reaching into provider internals — the composition
  law (infrastructure never imports the product) now has a real seam.
- pi extensions target the daemon surface (stdio or unix socket); the pi
  driver gates keep working unchanged via the apple_foundation composition
  root.
- Adding a backend = one `HarnessBackendBinding` registration; no new CLI,
  no copied plumbing, no daemon re-implementation.
- Net package delta: apple_foundation −11 bins, −3 lib files, −8 tests;
  host +1 package (engine-agnostic, provider-free).
