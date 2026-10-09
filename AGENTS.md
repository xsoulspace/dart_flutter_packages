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
# Codemap Graph Index — Code Intelligence for this repo

This repo is indexed by codemap's persistent graph index (`.codemap/index/`, gitignored,
derivable — the same parser-backed payload all codemap surfaces use). Navigation is fast
and carries an honest freshness contract: a stale index refuses or degrades loudly, never
silently. MCP tools `map_index_search` / `map_index_query` / `map_index_status` /
`map_index_changes` / `map_index_build` are globally mounted; the CLI form runs from the
codemap checkout: `~/xs/codemap/.venv/bin/python ~/xs/codemap/codemap_cli.py --json exec <command> --args '{"root": "/Users/antonio/xs/storage_problem/dart_flutter_packages", ...}'`.

## Always Do

- **Find symbols by graph, not grep:** `map_index_search` with `{"root": "/Users/antonio/xs/storage_problem/dart_flutter_packages", "query": "<substr>"}` (regex via `"use_regex": true`).
- **Blast radius before editing a symbol:** `map_index_query` with `{"root": "/Users/antonio/xs/storage_problem/dart_flutter_packages", "kind": "impact", "symbol": "<rel/path.ext::unit.name>"}`; `{"kind": "context"}` for the node + inbound/outbound edges.
- **Freshness before trusting:** every payload carries `freshness`; a stale index REFUSES by default — pass `"require_fresh": false` only when a visible-stale answer is acceptable; `map_index_status` reports full drift.
- **Before committing:** `map_index_changes` maps file drift to changed symbols + one-hop affected callers.
- **Rebuild when stale:** `map_index_build` with `{"root": "/Users/antonio/xs/storage_problem/dart_flutter_packages", "ignore_prefixes": ["build/"]}` — incremental (unchanged files splice from cached contributions); a fresh tree answers in seconds.
- Symbol ids are `rel/path.ext::unit.name` — get exact ids from `index_search`. Never invent edges from grep; unresolved calls are in the payload, never guessed.

<!-- codemap-index:end -->
