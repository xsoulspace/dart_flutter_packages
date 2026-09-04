// ignore_for_file: lines_longer_than_80_chars

# R7 results — edit-as-re-derivation (span materializer, daemon, pi surface, packs)

Date: 2026-09-03. LLM-free gates throughout (scripted movers; zero model
code tokens everywhere). ADR: [0023](../../../../docs/decisions/0023_filesystem_projection_target_edit_as_rederivation.md).
Standing rule: every row states backend, decision path, tokens source,
composition, and n. Failures are classified data. Forward rows (the
production path) live at the TOP; the landed R7a–d records follow.

## R7 production #1 — FULL edit surface over ACP (the pi surface opens)

Landed: the scripted mover's prose directives (`[rename old new]`,
`[impact <symbol>]`) are GONE (hard cut). The id-bearing verbs now travel
as STRUCTURED JSON payloads — `harness_edit {…}` carries the exact
`edit_symbol` args (action, symbolId/classSymbolId, opChain,
executableId, executableParams) and `harness_impact {…}` the exact
`meaning_impact` args — serialized into the `session/prompt` text by the
pi driver ([run_r7_daemon_gate.mjs](../../benchmark/pi_driver/run_r7_daemon_gate.mjs))
and the pi extension ([r7_harnessd_extension.ts](../../benchmark/pi_driver/r7_harnessd_extension.ts)).
The mover executes the payload VERBATIM against the real registry and
NEVER resolves or guesses ids — the caller reads them from the streamed
zoom/impact cuts (the R7d division of labor, now the only path). A
malformed payload is dropped AND COUNTED (classified data, never repaired
into a guess; rescan continues after the broken `{` so a bad group cannot
swallow a following valid payload — gate-asserted).

| Row | Gate | n | backend | decision path | tokens source | composition | verdict |
|---|---|---|---|---|---|---|---|
| production #1 | pi driver transcript performs `insert_member` AND `replace_member_body` (+ `apply_executable` rename) through the structured contract; `dart analyze` + workspace convention (`dart test`) green; pi fs tools disabled | 1 session, 7 daemon turns, 3 edit moves | scripted-daemon-actor (pi surface) → harnessd `open_router:scripted` mover | pi tool call → structured JSON payload in `session/prompt` → harness actor (meaning profile) → `edit_symbol` → verdict chunk | Situation.tokensUsed (projection; model-free mover) | coderLean + meaning profile surface | PASS — body replacement (`return (w * h);`), rename (`area` → `surfaceArea`, test file refs updated), insert (`Box.doubled`, `return (f * 2);`) all landed in a DISPOSABLE fixture workspace (no repo mutation, no revert dance); transcript: [r7_edit_surface_transcript.txt](../../benchmark/runs/r7_edit_surface_transcript.txt) |
| malformed-payload gate | `harness_edit {broken` + one valid payload in one prompt → malformed dropped + counted, valid payload executed, result streamed | 1 | scripted mover (unit, LLM-free) | same | — | — | PASS — `(1 malformed dropped)` reported; `[edit_symbol]` bounce streamed mid-turn ([harnessd_r7c_test.dart](../../../xsoulspace_inference_apple_foundation/test/harnessd_r7c_test.dart)) |

Design notes shipped with the gate: the edit fixture workspace is created
fresh per gate run (pubspec + covered `area` + `Box`) — the coverage fence
(b) is satisfied by the suite's own `expect(area(2, 3), 6)`; ids reach the
caller only through the streamed cut (the mover's `_resolve` name-guessing
path is deleted).

## R7 production #2 — meaning-profile overhead vs the AFM window

Mechanical measurement (LLM-free, zero model tokens): the FIXED cost of
one meaning-profile decision before any content — `meaningProfileSystemPrompt`
+ the 5 tool schemas exactly as `runCodingAgentOnce` wires them — metered
with the harness estimator (`overheadTokens`, chars/4) against the P1
pre-flight `maxContextTokens` guard (3800).

| Row | tokens | note |
|---|---|---|
| system prompt (`meaningProfileSystemPrompt`) | 141 | the law + flow, no per-task code |
| `repo_etl` schema+desc | 132 | |
| `meaning_zoom` schema+desc | 211 | |
| `meaning_impact` schema+desc | 144 | |
| `edit_symbol` schema+desc | 594 | the LARGEST schema, as predicted — the named lever if the row ever stops fitting (lean schemas, never the law) |
| `run` schema+desc | 187 | |
| **FIXED OVERHEAD TOTAL** | **1408** | fits the harness fixed-overhead target (≤ 1500) |
| AFM window (P1 `maxContextTokens`) | 3800 | working memory left for cut + transcript: **2392** |

Tokens source: `overheadTokens` (chars/4, the same estimator the
projection law uses); n=1 registry construction, gate-asserted in
[meaning_profile_overhead_test.dart](../../../xsoulspace_inference_apple_foundation/test/meaning_profile_overhead_test.dart)
(edit_symbol-largest, totals under budget). **Verdict: the surface FITS**
— nothing needs cutting to reach R7e; the only free parameter left is the
cut itself (`coderLean` / `ProjectionBudget`), never the schemas.

## R7 production #4 — the remote mover (pi joins as the session actor's brain)

Landed: the daemon can run **MODEL-LESS**. `HarnessAcpBackend` implements
`AcpMoveProposing` (new ACP toolkit capability, symmetric with
`request_permission`): every decision round-trips to the CLIENT as
`session/propose_move` — bounded cut (`request.prompt`, the projected
situation, never file text) + the CLOSED tool schemas + the live budgets
out; typed tool calls back (`AcpMoveResponse.toolCalls`), decisionId
echo-checked (a stale reply is an empty move, never applied elsewhere).
The loop, its budgets and its oracles are unchanged — only WHO decides is
pluggable (`--scripted` > `--remote-mover` > `handlerFactory` > router).
This is the precondition for production #7: pi's own model decides
through the surface; the daemon never needs open_router/AFM while pi
calls it.

| Row | Gate | n | backend | decision path | tokens source | composition | verdict |
|---|---|---|---|---|---|---|---|
| decision economy | scripted client-as-mover: 2 propose_move round-trips for 2 decisions; the verdict chunk counts `decisions 2` (one truth: the meter over the loop) | 1 | remote mover (LLM-free client) | loop → propose_move (cut + schemas + budgets) → typed tool call (repo_etl scan) → loop → propose_move → done → goal gate | Situation.tokensUsed (projection) | coderLean + meaning profile | PASS — budgets consumed IN-WORLD: proposal 2 carries the live round count advanced by the scan ([harnessd_remote_mover_test.dart](../../../xsoulspace_inference_apple_foundation/test/harnessd_remote_mover_test.dart)) |
| bounded protocol | every proposal carries cut + schemas + budgets; NO file text (`hello x` absent from every prompt); schemas contain the full meaning-profile surface | 2 proposals | same | same | — | — | PASS |
| cancel mid-decision | the client never answers → `cancelSession` completes the pending propose_move → the decision unblocks, the turn ends `cancelled`, zero leaked awaits | 1 | same | same | — | — | PASS |

## R7 production #5 — the persistent daemon (single-instance + warm attach + AOT)

Landed in `bin/harnessd.dart` (`--workspace <path>`, `--idle-exit-minutes`):

- **SINGLE-INSTANCE PER WORKSPACE (mandatory)**: an exclusive file lock at
  `<workspace>/.dart_tool/harnessd/harnessd.lock`; a second daemon for the
  same workspace exits **2** before touching any state (two daemons = two
  worlds = single-writer broken at process level).
- **Warm attach**: the daemon listens on a unix socket (SHORT hashed
  `/tmp/harnessd-<hash>.sock` — macOS caps socket paths at ~104 chars, a
  real workspace path exceeds that; the workspace keeps a POINTER file
  `harnessd.sock` with the real path). Each connection is a full ACP
  server over the SHARED backend; sessions are keyed per workspace, so a
  second pi session continues the live world (zero re-scan — the only
  tree work is the mechanical mtime tick). Measured finding shipped as a
  fix: a raw `Socket` (`Stream<Uint8List>`) as ACP input fails
  `utf8.decoder`'s runtime generic check — the input is mapped to
  `List<int>`.
- **Keep-warm + idle-exit**: the daemon survives session ends (stdio EOF
  does not terminate it in workspace mode); it exits after N idle minutes
  (default 10). The snapshot store is crash recovery only — the WORLD
  stays in the process.
- **AOT**: `dart build cli bin/harnessd.dart` (dart compile is refused
  with build hooks — the `dart build` CLI composes): the binary runs the
  full ACP surface WITH the native-assets hook (the AFM bridge
  `libxs_fm_bridge.dylib` ships in the bundle). NO fallback needed.

| Row | Gate | n | verdict |
|---|---|---|---|
| warm attach | second client (socket) attaches to the warm daemon: SAME sessionId, attach startup < 2s (measured ~0–1 ms), zero re-scan (zoom reads the warm tree) | 1 session pair | PASS ([run_r7_warm_attach_gate.mjs](../../benchmark/pi_driver/run_r7_warm_attach_gate.mjs), transcript [r7_warm_attach_transcript.txt](../../benchmark/runs/r7_warm_attach_transcript.txt)) |
| single-instance | second daemon process, same workspace → exit 2 + `REFUSED` | 1 | PASS (in-process gate + wire gate) |
| socket transport | two connections over the shared backend; per-workspace world continues | 1 | PASS ([harnessd_remote_mover_test.dart](../../../xsoulspace_inference_apple_foundation/test/harnessd_remote_mover_test.dart)) |
| AOT | `dart build cli` composes with native assets; the binary answers ACP initialize; dylib bundled | 1 | PASS — no fallback needed |
| keep-warm | stdio EOF in workspace mode → daemon stays serving socket clients; idle-exit after 10 min | 1 | PASS (code path; idle-exit timer asserted by inspection of the gate runs)

## R7 production #3 — packs as the PRIMARY path (the capture loop)

Landed: the ADR 0021 capture loop wired to the edit tier
([edit_pack_capture.dart](../../../xsoulspace_agentic_dart_meaning/lib/src/edit_pack_capture.dart)).
A MODEL-COMPOSED `replace_member_body` that passes all three fences AND
the free oracles (fully green — a move merely KEPT under a pre-existing
red baseline is NOT a proven resolution) is captured by the HOST as a
project-pack entry: an `EditExecutableWire` (kind `replace_member_body`,
params `['symbolId']`) + the op-chain as data, persisted under
`<workspace>/.dart_tool/harnessd/edit_pack.json`. The executable id is a
MECHANICAL fingerprint of the repair class (action + normalized op rows,
stable FNV-1a) — never model-authored, never prose. Every
`edit_symbol` tool over the workspace AUTO-REALIZES the pack
(`registerPackExecutable`), so the next task consumes the entry via
`apply_executable {executableId, symbolId}` at ZERO authored tokens; the
integration fence still validates the chain against the new symbol's
signature (a wrong repair class bounces as data). Capture is idempotent
(dedup by id) and host-only (the model never sees the pack file).

| Row | Gate | n | backend | decision path | tokens source | composition | verdict |
|---|---|---|---|---|---|---|---|
| capture → reuse | scripted novel resolution (`area`, composed chain) → pack entry (`dart/captured/<fingerprint>`) → a SECOND task/session fixes `product` via `apply_executable` with NO op rows; `dart test` green both tasks | 1 workspace, 2 tasks (2 sessions) | scripted mover (LLM-free) | edit moves; task 2's call carries only executableId + symbolId | task 2 edit: ZERO authored tokens (chain from the pack) | coderLean + meaning profile | PASS — `product` body = the captured chain, convention green ([edit_pack_capture_test.dart](../../../xsoulspace_agentic_dart_meaning/test/edit_pack_capture_test.dart)) |
| proven-only capture | composed move lands under a PRE-EXISTING RED baseline (suite still failing) → move KEPT, pack NOT written | 1 | scripted mover (LLM-free) | same | — | — | PASS — `edit_pack.json` absent; unproven resolutions never enter the pack |
| idempotence | re-capturing the same repair class returns the same id; no duplicate entry; non-capturable actions (`insert_member`) return null | 3 | unit (LLM-free) | — | — | — | PASS |

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
  ECS world itself is microseconds (cuts 4–61ms at 67k edges). Mid-turn
  tool-result streaming SHIPPED with production #1 (a 40ms observer in
  `runCodingAgentOnce` emits `ToolResultContent` beats as they land —
  replacing the old emit-at-run-end truncated copy). Still not shipped:
  skip the turn-grade when no move applied and the baseline is
  cached-green; wire pi's consent UI to `session/request_permission`.
- The daemon's in-package `dart analyze` exit=2 (warning-y workspace) is
  correctly treated as a pre-existing red baseline — attribution then
  rests on the workspace convention. Analyzer-grade diagnostics routing
  back through `source_maps` (generated range → op row) remains the
  B2-dialect follow-up.
- Lexical rename is v1: getters/setters, operators, named constructors and
  named-parameter breaks BOUNCE (analyzer-grade is P4/J3).
