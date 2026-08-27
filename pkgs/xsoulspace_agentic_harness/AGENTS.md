# pkgs/xsoulspace_agentic_harness: Agent Working Agreement

Pure-Dart, VM-only cinematic multi-actor agent harness. Sub-star of the
workspace North Star (ADR 0012): *a small local model (2–4k context) is
genuinely useful because the harness does the heavy lifting* — the model is a
replaceable reasoning primitive.

## Sub-star boundary

Cannot override repo center: workspace charter, Skill Steward adoption, and
ADRs live at root `docs/decisions/`. Standing rules travel with the claims
(benchmark columns state backend/decision-path/tokens/tool-surface;
failures remain data; escalation rate ships next to pass-rate tables).

## Layout

| Path | Role |
| --- | --- |
| `lib/src/` | Engine: loop, schedules, systems, narrative, snapshot(+store), model_router |
| `lib/src/composition/` | Declarative composition surface (ADR 0014): `FlowSpec`, `DatasetSpec`, tiered eval, `renderFlow` |
| `lib/src/tools/` | Tool bodies: `fs_tools` (read/write/list_dir + `grep`/`glob` discovery), `tool_call_parser` \|
| `lib/src/cli/` | CLI SDK (`AgentCli`) — provider-agnostic everyday REPL host |
| `lib/src/benchmark/` | Coding suite, ADR 0009 experiment arms, phase benchmarks |
| `lib/src/tooling/` | World builders, decorators, token estimator |
| `bin/xsoulspace_agent.dart` | Real agent entrypoint (mock backend built in) |
| `benchmark/runs/` | Tracked evidence artifacts |
| `example/headless/`, `example/agents/` | Golden examples + runnable agents |

Providers inject backends via `AgentCliConfig.buildHandler`; no provider code
belongs in this package. fs_tools uses `dart:io` and stays unexported from
the barrel (web footgun).

## Validation

```bash
cd pkgs/xsoulspace_agentic_harness
flutter pub get && flutter analyze && flutter test
just demo   # headless golden examples
```

Steward-scoped: `steward action xsoulspace_agentic_harness.analyze|.test`.

## Plan & history

[PLAN.md](docs/agent/PLAN.md) (forward/frontier only — landed work lives in docs/agent/history.md) · [ADR 0013](../../../docs/decisions/0013_native_tool_calling_first.md) ·
[north star](docs/north_star_agentic_harness.mdx) ·
[architecture](docs/agent/architecture.mdx)
