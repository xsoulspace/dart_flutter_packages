# Multi-actor workers — the rung-1 contract (extension clients)

> Status: CONTRACT — build order item 5, operational half (2026-09-08 wave).
> The wiring (spawn integration into the wave driver) belongs to other
> lanes; this doc is the contract they wire against. Read first:
> [pipeline_coding.md](pipeline_coding.md) (the law + the mechanical tier),
> [PLAN.md](PLAN.md) (multi-actor + topology rows),
> [surface_gaps.md](surface_gaps.md) (daemon idle-exit + double-spawn
> resilience rows — what already exists),
> [NORTH_STAR](../../../../docs/NORTH_STAR.mdx).
>
> The problem: today, spawned pi agents (wave lanes, subagent delegations)
> are ABANDONED PROCESSES — bare, no extension, no daemon, raw tools,
> private context. Every one of them re-does the drift the harness closed:
> raw reads over pkgs/**/*.dart, raw writes, private unshared trees, no
> consent audit, escapes nobody logs. Rung 1 makes them mechanical-surface
> CLIENTS of the SAME per-workspace daemon.

## Rung 1 — a worker is an extension client of the workspace daemon

A spawned worker attaches to the same per-workspace `harnessd` daemon the
orchestrator session uses. Concretely:

1. **Mount the pi extension.** The worker's pi process loads the harnessd
   extension (`pi -e benchmark/pi_driver/r7_harnessd_extension.ts`, cwd =
   the workspace, env `PI_HARNESSD=1`). The extension disables pi's
   built-in file tools (`setActiveTools(DAEMON_TOOL_NAMES)`) — the daemon
   surface is the ONLY file surface.
2. **Connect-if-live, spawn-if-absent.** The extension reads the socket
   pointer `<workspace>/.dart_tool/harnessd/harnessd.sock`; a live daemon
   answers the `initialize` health ping and the worker ATTACHES (warm
   tree, no re-scan — proven by `run_r7_warm_attach_gate.mjs`). No daemon
   → the extension spawns one (`--remote-mover` with pi's model as the
   session-actor brain, or `--scripted` for LLM-free gates). The
   spawn-or-attach is serialized behind ONE shared in-flight promise and
   dead-client detection re-attaches once — the idle-exit and
   double-spawn rows in surface_gaps.md are CLOSED behavior the worker
   inherits for free.
3. **One world, not N.** Per-workspace keying means every attached worker
   continues the SAME meaning tree, the same beats, the same consent log.
   A second daemon for the same workspace is REFUSED (exit 2,
   single-instance is mandatory — two daemons = two worlds = single-writer
   broken).
4. **The same paths, nothing else.** The worker gets exactly the daemon
   tool set: the ONE mechanical read program (`harness_meaning_program` —
   locate/zoom/impact/read ops, sub-100 ms, zero model tokens), `harness_edit`
   (the ONE class-routed edit verb — dart symbol moves, md sections,
   yaml/json keys), `harness_fs_write` (review-gated escape hatch, never
   Dart), `harness_run` (allowlisted commands), `harness_verify`
   (per-package derivation). Workers do not get, and must not ask for,
   `read`/`write`/`edit`/`bash` over covered work.
5. **Consent is inherited, not re-asked.** A workspace consent plan
   (`.harnessd/consent.json` — `{pathGlob, verbs, maxUses}`) or a session
   grant answers matching writes mechanically; the human is prompted only
   OUTSIDE the plan; no approver ⇒ deny-by-default (structural). Every
   decision lands in the shared consentLog — the audit is the daemon's,
   not the worker's private one.

### What a worker must NOT do

- **No raw tools over covered work.** A raw `read`/`edit`/`bash` on a
  `pkgs/**/*.dart` change the surface covers is the drift the surface
  routing law (root AGENTS.md; ADR 0027, measured 34–54 ms) forbids —
  for the spawned worker exactly as for the orchestrator.
- **No private tree, no private state.** Scanning into a second world,
  snapshotting, or working around the single-instance lock defeats the
  one-writer invariant.
- **Escapes are HONEST and LEDGERED.** When the surface genuinely does
  not cover the work (new-file bootstrap, cross-repo, structural Dart
  shapes — see the gap ledger), the worker takes the raw path AND appends
  a row to [surface_gaps.md](surface_gaps.md). The worker's escape is the
  tiny model's missing verb: a gap row is not a defeat, it is the next
  work item, because the same surface must later serve a 2–4k AFM model
  for whom raw bash does not exist. A silent escape starves that path.

## The three-rung gradient

Rung 1 is honestly a **TRANSITIONAL ADOPTION WEDGE**: pi is still the
orchestrator and each worker still carries its own pi loop and model; the
surface law holds (all file work rides the daemon), but co-presence is
NOT yet coordinated by the harness — the wave driver serializes workers
externally and scopes them to disjoint OWN lists to make that safe.

| rung | actors | coordination | status |
|---|---|---|---|
| **1 — extension clients** | N spawned pi agents, each an extension client of the SAME daemon | external (the spawn brief: disjoint OWN scopes; the driver serializes turns) | **THIS contract — transitional wedge** |
| **2 — co-present actors** | actors declared as data in `actor_topology` ({worlds, actors, roles, model-tiers, budgets}) | the daemon arbitrates: steps claimed through the plan frontier (`projectPlanFrontier` / `openFreshDecision`), one decision at a time, budgets enforced per role | named in PLAN.md (topology engine, speculative verify actor) — designed, not built |
| **3 — mechanical actors** | zero-token mechanical actors declared IN the topology | they work CONSENTED ready steps (`StepAction(toolName, arguments)` resolved in the frontier) ahead of the model actor — the ADR 0009 accelerate-and-predict half; unresolvable steps project tier-routed | landed as machinery (`step_resolver.dart`, `mechanical_actor.dart`); topology declaration pending rung 2 |

Absorption path: rung 1 needs NO new machinery — it exercises the exact
verbs rungs 2–3 coordinate (`actor_topology` declares what rung 1 does by
hand; step claiming replaces the disjoint-OWN-list convention). When the
topology engine lands (PLAN.md NOW row), a rung-1 worker becomes a rung-2
actor by DECLARATION, not by rewrite; its spawn brief (see
`benchmark/pi_driver/worker_spawn_brief_template.md`) is replaced by the
topology's role row.

## The replacement metric

Rung 1 exists to be measured out of existence. Published beside
pass-rate/escalation-rate (same discipline: state backend, decision path,
tokens source, tool surface, n):

- **harness-decision share** — the fraction of a worker session's file
  decisions served as harness decisions (mechanical read program, class-
  routed edit, consented fs write, allowlisted run) instead of raw-tool
  decisions. Rung 1 target: 100% of covered work; every raw decision is
  either a logged surface gap or a defect.
- **escape rate → 0** — surface-gap rows per task, trended across waves.
  The rate never reaches zero by force: mapless classes and out-of-root
  work route to the review gate or the ledger BY DESIGN. The metric is
  the slope, not a vanity zero.

## Driver

`benchmark/pi_driver/run_r7_multi_worker_gate.mjs` — two workers, one
daemon, disjoint targets, edits land, package suite green.
`--scripted` (default) is LLM-free (the daemon runs `--scripted` and the
workers are simulated extension clients over the same socket — the exact
attach path the pi extension takes); `--live` spawns two real `pi -e`
workers against a `--remote-mover` daemon and requires
`OPENROUTER_API_KEY`. Run `--scripted` before claiming anything.

## Non-claims

- Rung 1 does NOT make workers harness-coordinated: no step claiming, no
  shared actor topology, no cross-worker conflict detection beyond the
  one-daemon/single-writer invariant and the brief's OWN-list discipline.
- The daemon is one-actor-at-a-time in v1; concurrent worker turns
  serialize at the daemon. Rung-2 parallelism is unproven.
- The extension's per-workspace session keying means multiple attached pi
  clients share one session id; remote-mover proposal ROUTING between two
  simultaneously-attached clients is an open rung-1 edge (the `--live`
  mode sequences workers to sidestep it — measuring the concurrent case
  is rung-2 work).
- Nothing here changes package code; this is a contract + brief + driver
  lane.
