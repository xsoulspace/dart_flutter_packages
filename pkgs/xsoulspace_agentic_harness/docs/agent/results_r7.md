// ignore_for_file: lines_longer_than_80_chars

# R7 results — edit-as-re-derivation (span materializer, daemon, pi surface, packs)

Date: 2026-09-03. LLM-free gates throughout (scripted movers; zero model
code tokens everywhere). ADR: [0023](../../../../docs/decisions/0023_filesystem_projection_target_edit_as_rederivation.md).
Standing rule: every row states backend, decision path, tokens source,
composition, and n. Failures are classified data.

## R7b — the span-edit materializer (the ACT verb for existing code)

Landed: `pkgs/xsoulspace_agentic_dart_meaning/lib/src/span_editor.dart`
(`SpanEditMaterializer`, `SpanPatch`, `SpanEditBounce`, `edit_symbol` tool)
+ the public chain compiler in `dart_materializer.dart`
(`compileOpChainBody`). One tool, minimal closed enum:
`replace_member_body` / `insert_member` (model-composed op rows) +
`apply_executable` (pack-fed; built-in `rename_symbol` at `scope: lexical`
expanding over the refs frontier).

| Row | Gate | n | backend | decision path | tokens source | composition | verdict |
|---|---|---|---|---|---|---|---|
| R7b MAIN | scripted actor: repo_etl scan → invalid rename (bounce) → multi-file lexical rename → insert member; analyze+`dart test` green | 1 | scripted (LLM-free) | edit moves only, one per tool round | Situation.tokensUsed (projection) | coderLean | PASS — ZERO `read`/`write` in registry AND beats; budgets monotonic (1 attempt consumed by the deliberate pause) |
| fence (a) | state-op chain (`load_state`) | 1 | scripted | bounce before generation | — | — | BOUNCED as named data (`fence: expressiveness`), bytes untouched |
| fence (b) | replacing an UNCOVERED legacy member | 1 | scripted | bounce before generation | — | — | BOUNCED (`fence: coverage`) — routes to add-coverage-first |
| fence (c) | `load_arg` outside the declared signature | 1 | scripted | bounce before generation | — | — | BOUNCED (`fence: integration`) |
| auto-revert | wrong body under a COVERED member (2+3≠6) | 1 | scripted | apply → `dart test` fails → in-memory revert | — | — | bytes restored byte-identical; `failure_class: workspace_check_failed` |
| repo-scale plan | lexical rename over the REAL harness package tree | 1 | scripted | plan-only (zero writes) | — | — | PASS — atomic, >1 file in frontier |

Failure classes shipped: `bounce:expressiveness`, `bounce:coverage`,
`bounce:integration`, `workspace_check_failed`, `analyze_failed`,
`lock_conflict`, `permission_denied`.

**Failure attribution (design note):** a move is auto-reverted only for
failures it CAUSED (pre-move green → post-move red). A workspace whose
suite is already red (the failing suite IS the task spec) keeps patches —
the goal loop grades the end state. Verified by the MAIN GATE (rename +
insert against a red suite) and the auto-revert variant (green suite →
revert).

**Performance discipline (the ECS lesson):** the first implementation ran
the full-package analyze+convention twice per move — 10-minute daemon
turns. Fixed: the verify baseline is a WORLD RESOURCE
(`SpanVerifyBaseline` — the post-state of a green move IS the next move's
pre-state), the post-analyze is SCOPED to the touched files (the blast
radius the tree already knows), and per-phase timings ship in every
outcome (`analyze_ms`, `check_ms`). Probe: a 2-file lexical rename applies
+ verifies in **649 ms** wall. The ECS world was always microseconds; the
oracle tier must not pay whole-package subprocess costs per move.

**Write demotion (hard cut, landed with R7b):** the run-graded fs arm is
marked LEGACY-HOST-ONLY in `coding_agent_runner.dart`; the intent surface
never had `write`; the meaning profile's only ACT verb is `edit_symbol`
(gate-asserted: no `read`/`write` in the registry or the beats).

## R7c — the daemon holds the world

Landed in `harness_acp_backend.dart` + `bin/harnessd.dart` (also: the
snapshot codec now EXCLUDES the meaning tree at capture — ADR 0023 §2 —
and the meaning-profile surface in `runCodingAgentOnce`
(`repo_etl`/`meaning_zoom`/`meaning_impact`/`edit_symbol`/`run`, zero
fs tools)).

| Row | Gate | n | verdict |
|---|---|---|---|
| per-workspace persistence | two `session/new` calls, same cwd → ONE session; world + tree stay warm | 1 | PASS |
| loadSession | NEW backend instance restores from the per-workspace snapshot store (`.dart_tool/harnessd_store`); capability flag `loadSession: true` | 1 | PASS (store exists, resumable world) |
| tree never snapshotted | snapshot envelope carries no MeaningNode/Props/Edge (codec change + tests re-cut to the re-derivation contract) | 3 suites | PASS |
| permission deny-by-default | no requester wired → `requestPermission` = REJECT; wired → routed through | 1 | PASS |
| cancel | `cancelSession` aborts generation; prompt turn ends `cancelled` (loop swallows handler errors BY DESIGN, so the flag is observed at the turn boundary) | 1 | PASS |
| escalation ceiling | `escalationAllowance(rounds) = min(3+rounds, 9)` — never unbounded | 1 | PASS |
| unique tool-call ids | streamed `tool_call_update` ids unique per call (`t<n>_<name>` — the name-as-id bug fixed) | 1 | PASS |
| mechanical tree tick | `refresh` re-scans mtime-changed files before every prompt (zero model tokens); scan on a tree-carrying world reports `already` instead of double-building | 1 | PASS |

## TASK 3 — pi works through the daemon (its fs tools disabled)

Driver: `benchmark/pi_driver/run_r7_daemon_gate.mjs` (+ the pi extension
`r7_harnessd_extension.ts` for interactive use). pi session via the SDK
(`createAgentSession`, `noTools: 'builtin'` + explicit `excludeTools`) —
pi's enabled tools are ONLY the daemon-backed five
(`harness_scan/zoom/impact/edit/verify` over stdio JSON-RPC to
`harnessd --backend open_router --profile meaning --scripted`). The
"model" is a scripted OpenAI-compatible server (LLM-free gate discipline:
the gate measures the SURFACE, not the mover).

Row (from `benchmark/runs/r7_daemon_transcript.txt`):

| Column | Value |
|---|---|
| backend | scripted-daemon-actor (pi surface) → harnessd `open_router:scripted` mover |
| decision path | pi tool call → ACP `session/prompt` → harness actor (repo_etl / meaning_zoom / meaning_impact / edit_symbol / run) → verdict chunk |
| tokens source | Situation.tokensUsed (projection; 0.7k–12.5k per turn — model-free mover) |
| composition | coderLean + meaning profile surface |
| n | 1 session, 5 daemon turns, 1 rename applied |
| verdict | PASS — rename `_meaningTreeIds → _meaningTreeComponentIds` landed (2 patches, 1 file), `flutter test` exit 0, post-analyze clean, pre-run bytes restored after the gate |

Failure classes met and fixed along the way (all classified data):
- `permission_denied` — the R7c edit approver asked the client; the gate
  driver did not answer `session/request_permission` → deny-by-default
  WORKED; the driver now answers (a real client asks the human).
- The loop swallows handler errors by design → cancellation is observed at
  the turn boundary, not mid-loop.

Transparency: the daemon now streams every tool RESULT (patches, verify
verdicts, bounce reasons, `analyze_ms`/`check_ms`) as ACP message chunks,
and the verdict chunk carries decisions/rounds/tokens/wall/moves.

## R7d — pack-fed edits

Landed: `EditExecutableWire` in `agentic_executables_wire` (zero-dep,
syntax-only; unknown kinds fail LOUDLY; api-breaking kinds flagged) +
pack realization in `SpanEditMaterializer.registerPackExecutable`.

| Row | Gate | n | verdict |
|---|---|---|---|
| pack-fed edit | `dart/fix_loop_bound` (replace_member_body; the op-chain travels with the PACK) — the model supplies ONLY executable id + symbol id | 1 | PASS — body lands (`!(i > n)`), `dart test` green, ZERO authored tokens |
| wire round-trip | fromJson → toJson → fromJson; unknown kind throws; api-breaking flagged | 3 | PASS |

Open (the recorded seam, AE-owned): `planFromMatrix` consuming
`ae.canonical.draft.v1` + the `distiller` role composition — prose-intent
planning source. NEVER a harness-side text distiller (AE spec §Distillation
↔ harness planning).

## Honest tails

- The daemon gate is seconds, not microseconds: per-turn wall is
  dominated by the free-oracle tier (`flutter test` ~23s on the harness
  package; baseline once per session, scoped analyze ~0.4s per move). The
  ECS world itself is microseconds (cuts 4–61ms at 67k edges). Further
  lever: skip the turn-grade when no move applied and the baseline is
  cached-green — not shipped; recorded.
- The daemon's in-package `dart analyze` exit=2 (warning-y workspace) is
  correctly treated as a pre-existing red baseline — attribution then
  rests on the workspace convention. Analyzer-grade diagnostics routing
  back through `source_maps` (generated range → op row) remains the
  B2-dialect follow-up.
- Lexical rename is v1: getters/setters, operators, named constructors and
  named-parameter breaks BOUNCE (analyzer-grade is P4/J3).
