# Resident plane via oka supervisor — 2026-10-12

Live cycle proving the ADR 0064 resident execution plane is kept by
**oka's supervisor convergence** (no launchd, no second daemon), with
the committed declarative plan suite driving a real desktop target
through it.

## The cycle

| Pass | Receipt |
| --- | --- |
| converge 1 | `1 to start` — lease spawned the serve, but under the wrong dart (homebrew 3.13.2 vs the workspace's fvm 3.13.4: the native-assets hook dill refuses on SDK hash) |
| converge 2 | `restart uatk-serve (prior service failed; within budget)` — budgeted restart fixed the launcher; endpoint reachable |
| converge 3 (unsandboxed) | `restart (observed stopped)` — the sandboxed Bash session had reaped the lease; the serve survived this time and answered `tools/list` on `http://127.0.0.1:8192/mcp` after the session ended |
| converge 4 | `no actions (state converged)` — idempotent steady state |

## Resident job proof

`automation_run_background` over the converged serve, submitted from a
separate shell:

- plan: `pkgs/universal_automation_toolkit/plans/desktop-smoke.yaml`
  (the committed declarative suite; target from the `app` handle)
- override: `set: {app: "ax://pid/98423"}` — a background-opened
  TextEdit
- result: `job-1791826929100-0.json` — `status: succeeded`,
  `report.ok: true`, steps observe (354 nodes) → verify (1 check) →
  screenshot (occluded window PNG under `run-out/`)
- receipt durable at `~/.uatk/jobs/` and re-readable after the fact
- the serve then validated `last_answer/e2e/automation/last-answer-desktop.yaml`
  over MCP: `ok: true, scenarios: [main]` (the config wiring works)

## Findings

- **Supervision works, spawn mechanics are environment-sensitive**:
  the launcher must resolve the same dart SDK the workspace hooks were
  built with (fvm default on this machine), and an agent's sandboxed
  shell reaps converged leases — a resident serve must be converged
  from an unsandboxed context. Both are launcher concerns
  (`tool/uatk_serve.sh`), not supervisor gaps.
- Restart budgeting behaved exactly per ADR-0040: one failed start
  consumed budget, the next pass restarted within it, a converged
  state took no action.
- Cleanup: serve killed, lease record removed, TextEdit instances
  quit; the owner's unrelated serve (ephemeral port, workbench
  evidence) was left untouched.

Companion evidence: `docs/evidence/pid-scoped-rung-2026-10-12/`
(the typed-event rung, same day).
