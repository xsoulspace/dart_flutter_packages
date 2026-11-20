# AGENTS.md — Agent Entrypoint Map

Welcome. This project uses **Skill Steward** to make repository purpose, validation, docs, and agent handoff legible.

## Operational Desk

Run the following commands to interact with the project's agentic tools:

- **Show operational map**: `steward map`
- **Inspect Steward contract**: `steward doctor --json`
- **Validate workspace**: use the native validation command recorded in `steward.yaml`
- **Release intent**: `just changesets-add` (intent file in the PR), `just changesets-status`
- **Release gates + pub.dev census**: `just release-gate`
- **Publish dry-run**: `just publish-preflight <package>`
- **Publishing flow**: [PUBLISHING.md](PUBLISHING.md) — pub.dev primary via
  [dart_changesets](https://github.com/Arenukvern/dart_changesets)
  (ADR 0073); registry flow PAUSED

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

Probe scratch law (paid for 2026-11-04: `local-adoption`/`cancellation-native` left ~850 MB of binary copies in `.dart_tool`): probes and one-off experiments never write multi-MB binaries (metallibs, dylibs, dills, model snapshots) into `.dart_tool` or the repo tree — route those to `$TMPDIR` (auto-swept by `just sweep-machine`) and keep the durable evidence textual: counts, verdicts, paths. A `dart_tool` capture dir is scratch by definition; it is never the evidence artifact.

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
# GitNexus — UNINSTALLED (tombstone, ADR 0072 fleet act)

GitNexus was removed from this repo on 2026-11-05, extending the codemap repo's
uninstall ruling (ADR 0072: streak 5/5 on distinct revisions + signed divergence
contract) to the repos where the owner operates. Uninstalled here: `.gitnexus/`
and the gitnexus skill copies under `.claude/skills/`. The three-repo
head-to-head that motivated the act (2026-11-05, this repo included) lives in the
codemap checkout at `docs/evidence/nexus-gap-2026-11-04/comparison-2026-11-05.md`.

The workflows it used to serve are codemap's, and they remain mandatory (see the
codemap-index block above for the full surface):

- **MUST run impact before editing.** `map_index` `operation=query` `kind=impact`
  on the symbol; read `epistemic`, `causes`, and the unresolved-call-site floor —
  an empty resolved set with floor > 0 is a **lower bound**, never an all-clear.
- **MUST analyze graph changes before committing.** `map_index` `operation=changes`
  (drifted symbols + one-hop callers). A drifted file that answers nothing is not
  a clean check.
- **MUST read `freshness` and `meta.transport` on every answer.** Ordinary reads
  refresh; `freshness_policy=refuse` is the explicit stop. A stale answer served
  as exact is the failure mode this repo refuses.
- **NEVER rename symbols with find-and-replace** — use `map_rename` (mirror apply +
  edge-multiset oracle) or `move_proof` for moves.
- MUST treat an epistemic lower-bound as unresolved: confirm with a text search
  before deleting or renaming on the strength of a zero.

Resurrecting GitNexus here requires a new ADR naming a real consumer (ADR 0072
§4). The published calibration is the standing adversary:
`~/xs/codemap/docs/evidence/nexus-gap-2026-11-04/bench-verdict.json`, refreshed
per release; a published recall regression is a recorded decline.

<!-- gitnexus:end -->
