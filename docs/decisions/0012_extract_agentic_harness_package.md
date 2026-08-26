# ADR 0012: Extract the agentic harness into `xsoulspace_agentic_harness`

- Status: Accepted
- Date: 2026-08-26
- North Star impact: `sub_star`
- Builds on: [0007](0007_extensibility_seams_and_conformance.md), [0009](0009_goals_as_vectors_plans_as_projections.md), [0012 extraction supersedes no ADR — it relocates their subject matter]

## Context

`xsoulspace_inference_core` hosts two unrelated concerns: (a) its charter —
provider-agnostic inference contracts and validation for text/STT/TTS task
flows, and (b) the entire cinematic multi-actor agent harness (~10k LOC:
engine, CLI host, snapshot persistence, benchmark suites, experiment arms,
their tests, docs, and tracked evidence). Consequences observed in practice:

- Provider packages that only implement `InferenceClient` transitively
  carry the harness.
- Benchmark machinery is reachable from provider `bin/` code only via
  fragile cross-package relative imports
  (`../../xsoulspace_inference_core/benchmark/...`) because it belongs to no
  public barrel.
- The harness North Star lives as a subsection of core's working agreement,
  blurring which package's validation gates protect which claims.

Workspace survey: only `xsoulspace_inference_apple_foundation` and
`xsoulspace_inference_openrouter` consume the agent surface (bins/examples).
All other core dependents use inference contracts exclusively.

## Decision

Create `pkgs/xsoulspace_agentic_harness` (pure Dart, VM-only) and relocate:

| Moved | New home |
| --- | --- |
| `core/lib/src/agent/**` | `harness/lib/src/**` (flattened one level) |
| harness + suite tests, `test/support` | `harness/test/**` |
| coding_suite, experiment arms, phase benchmarks | `harness/lib/src/benchmark/` |
| world builders, scripted handlers, decorators, estimators | `harness/lib/src/tooling/` |
| `pi_driver/`, `runs/` evidence artifacts | `harness/benchmark/` |
| `docs/north_star_agentic_harness.mdx`, `docs/agent/**`, results docs | `harness/docs/` |
| headless golden examples + agent demo app | `harness/example/` |

`core` returns to its charter: inference contracts, env config, their tests.
Provider packages keep thin launchers/probes and gain a regular dependency on
the harness; all cross-package relative imports are replaced by
`package:xsoulspace_agentic_harness/...` imports. The everyday REPL becomes a
provider-agnostic SDK (`harness/lib/src/cli`) with a real entrypoint
(`bin/xsoulspace_agent.dart`); providers ship ≤40-line launchers.

### Sub-star boundary

The harness North Star ("a small local model is genuinely useful because the
harness does the heavy lifting") moves to the new package's AGENTS.md as a
declared **sub-star** of the workspace North Star. The sub-star cannot:

- change repo center (workspace charter, Skill Steward adoption, ADR home at
  root `docs/decisions/`);
- weaken the standing rules that keep its claims honest (published columns
  state backend/decision-path/tokens/tool-surface; failures remain data);
- pull Flutter or any single provider into the harness package itself.

Gravity checks (tiny model useful / fewer calls / bounded derived context /
LLM-free testable) continue to gate structural work inside the sub-star.

## Consequences

- `core` slims to contracts; its version bumps with an import-breaking note.
- Providers add `xsoulspace_agentic_harness` dependency for bins/examples.
- Steward actions, CI path filters, and the workspace skill file gain the new
  package.
- Apple Foundation de-flutterization (FFI-only transport) is planned
  separately so the AFM backend serves the CLI without the Flutter engine.
