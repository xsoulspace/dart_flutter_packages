# AGENTS.md — Agent Entrypoint Map

Welcome. This project uses **Skill Steward** to make repository purpose, validation, docs, and agent handoff legible.

## Operational Desk

Run the following commands to interact with the project's agentic tools:

- **Show operational map**: `steward map`
- **Inspect Steward contract**: `steward doctor --json`
- **Validate workspace**: use the native validation command recorded in `steward.yaml`

## North Star Impact

Before durable structural changes, classify `north_star_impact`: `none`, `applies`, `clarifies`, `sub_star`, `amends`, or `conflicts`.

- `none` / `applies`: use the native workflow and validation gate.
- `clarifies`: update the smallest FAQ, docs map, skill, check, or validation message.
- `sub_star`: declare the local parent/child boundary and what the sub-North Star cannot override.
- `amends` / `conflicts`: stop and write or update an ADR before changing the repo center.

Ask whether the change serves real product pain, which North Star value path it serves, and whether a mechanism is becoming the mission.

## Claims and Evidence

Before claiming readiness, maturity, harness support, steward status, or adoption:

1. Name the exact claim.
2. Check the weakest proof that supports only that claim.
3. Route the durable artifact:
   - ADR for durable decisions and trade-offs.
   - FAQ/docs for standing why/how guidance.
   - Check/tool/test for repeated deterministic drift.
   - Current ledger for the weakest true current status.
   - Evidence for real proof or blocked proof.
   - Delete completed plans after extracting durable truth.
4. Record non-claims.

If the same friction loops twice, stop before making another packet. Name the pain signal, owner, native validation gate, smallest disposition, rerun route, and non-claims; then fix the owner, move repeated drift to a check/tool/skill/current ledger, leave the path native, or stop.

If this repo needs a current claim ledger, run `steward evidence init --minimal`.
Default to no harness: do not add actions, probes, benchmarks, or scenarios unless typed actions, probes, or benchmarks help real repo work.
Use `steward.yaml` and harness proof only when typed actions, probes, or benchmarks help real repo work.

## Harness product

The agentic harness (engine, host, workspace, AFM composition) lives in
`~/xs/ecsai_harness`. This monorepo keeps inference transports and the
shared contract packages. It does not route package maintenance through
the harness. See [ADR 0036](docs/decisions/0036_harness_product_relocated.md).

## Package Working Agreements

- `pkgs/xsoulspace_inference_core`: [AGENTS.md](pkgs/xsoulspace_inference_core/AGENTS.md)
- `pkgs/xsoulspace_inference_apple_foundation`: [AGENTS.md](pkgs/xsoulspace_inference_apple_foundation/AGENTS.md)
- `pkgs/xsoulspace_inference_mlx_native`: [AGENTS.md](pkgs/xsoulspace_inference_mlx_native/AGENTS.md) — the MLX-native engine host (ADR 0057/0058)
- `pkgs/xsoulspace_inference_laya`: [AGENTS.md](pkgs/xsoulspace_inference_laya/AGENTS.md) — the laya decision product (engine lives in mlx_native)

## Active Skills

Skills are installed locally under `.agents/skills/`. You can view them using:

- `steward list`

For more information on the project charter and decisions:

- Read [NORTH_STAR.mdx](docs/NORTH_STAR.mdx) (if present)
- Read [ADR Index](docs/decisions/README) (if present)

<!-- codemap-index:start -->
# Codemap — navigate this repo

Discover once per session: `resources/read` `codemap://surface/v1`, or `map_surface`.
Then call `map_index` with `operation=`. The transport refuses retired names
(`map_index_search`, `map_index_query`, `map_index_build`, and the other `map_index_*` tools).

Pass `"root": "/Users/antonio/xs/storage_problem/dart_flutter_packages"` when the client cwd is not this repo.

1. **Start** — `map_doctor`, then `map_index` `{"operation":"build","root":"/Users/antonio/xs/storage_problem/dart_flutter_packages","ignore_prefixes":["build/","dist/",".dart_tool/","target/"]}`, then `map_index` `{"operation":"context_map","root":"/Users/antonio/xs/storage_problem/dart_flutter_packages","limit":24}`.
2. **Find** — `operation=search` and `query`. Concept-shaped queries add `"mode":"bm25"`.
3. **Before an edit** — `operation=query`, `kind=impact`, `symbol` = `rel/path.ext::unit.name` from search. `kind=context` returns the node and its edges. `kind=trace` also needs `target`.
4. **One evidence packet** — `operation=evidence` with `purpose` (`understand`, `impact`, or `trace`) and `budget_bytes`. Open the exact original with `operation=expand` and the handle in `meta.expansion`.
5. **Before commit** — `operation=changes`.
6. **On every answer** — read `freshness` and `meta.transport`. Ordinary reads refresh a stale index. `freshness_policy=refuse` starts no repair. Navigation facts are review leads; they do not authorize adoption.

CLI, from the codemap checkout — same names as the MCP tools:

`~/xs/codemap/dist/codemap-cli exec map_index --args '{"operation":"search","root":"/Users/antonio/xs/storage_problem/dart_flutter_packages","query":"<substr>"}'`

Parser edges only. Unresolved calls stay in the payload.
<!-- codemap-index:end -->

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **dart_flutter_packages** (20299 symbols, 42527 relationships, 625 execution flows).

> Index stale? Run `node .gitnexus/run.cjs analyze --index-only` from the project root — it auto-selects an available runner. No `.gitnexus/run.cjs` yet? Bootstrap with `npx`, `bunx`, or `pnpm dlx` — e.g. `bunx gitnexus@latest analyze` (npm 11 npx crash; #1939).

## Always Do

- **MUST run impact before editing.** Use `impact({target: "symbolName", direction: "upstream"})` or `node .gitnexus/run.cjs impact "symbolName" --direction upstream --repo .`; report callers, processes, and risk. Never substitute grep for graph analysis.
- **MUST analyze graph changes before committing.** Use `detect_changes({scope: "all"})` (MCP) or `node .gitnexus/run.cjs detect-changes --scope all --repo .` (CLI fallback). `partial: true` or `truncated: true` is not a clean check — a zero means unseen, not unaffected; re-run it. For regression review: `detect_changes({scope: "compare", base_ref: "main"})` or `node .gitnexus/run.cjs detect-changes --scope compare --base-ref "main" --repo .`.
- MUST warn on HIGH/CRITICAL `risk` pre-edit; never use `riskSharedAxes` to waive a HIGH/CRITICAL `risk` warning. Compare File/symbol: MCP File omits axes; Graph-RAG expands File.
- **MUST treat `risk: UNKNOWN` as unresolved, not as low.** An empty caller set is not evidence the symbol is unused — it can also mean the callers are not resolvable by the index (plain-object property access, dynamic dispatch, cross-language calls). `impact` pairs `UNKNOWN` with a `riskNote` saying so. Confirm with a text search before treating the symbol as safe to change or delete; do not proceed on the strength of a zero.
- **MUST use `query({search_query: "concept"})` for concepts/flows, `context({name: "symbolName"})` for a named symbol, or `impact` for blast radius, on read-only callers, dependencies, imports, or execution flow.** Graph first; text search only for empty/`UNKNOWN`/literals.
- For security review, `explain({target: "fileOrSymbol"})` lists taint findings (source→sink flows; needs `analyze --pdg`).

## Never Do

- NEVER edit a function, class, or method before MCP/CLI impact analysis.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis, and never read `UNKNOWN` as an all-clear — it means the walk could not answer, which is the one verdict that requires confirming by other means.
- NEVER rename symbols with find-and-replace — use `rename` which understands the call graph.
- NEVER commit before MCP/CLI graph change analysis.

## Resources

| Resource | Use for |
| --- | --- |
| `gitnexus://repo/dart_flutter_packages/context` | Codebase overview, check index freshness |
| `gitnexus://repo/dart_flutter_packages/clusters` | All functional areas |
| `gitnexus://repo/dart_flutter_packages/processes` | All execution flows |
| `gitnexus://repo/dart_flutter_packages/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
| --- | --- |
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->
