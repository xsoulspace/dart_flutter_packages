# Agent Brief — R7 IMPLEMENTATION (code first): edit-as-re-derivation + daemon tool replacement

You are an autonomous coding agent. Your mission: implement the most urgent
R7 tracks **as code**, in priority order, code-first (write the
implementation, then the gate tests; do not stall on doc polish). You may
perform hard cuts (delete/collapse code and tests that contradict the
ADRs) and refactors. You do NOT need approval for mechanical refactors;
you DO need to keep every gate green.

## Repos & surfaces

- Monorepo: `~/xs/storage_problem/dart_flutter_packages`
  - Harness core: `pkgs/xsoulspace_agentic_harness`
  - Dart domain host: `pkgs/xsoulspace_agentic_dart_meaning`
    (R6 workspace-oracle runner, code ETL, `repo_etl` tool — all landed)
  - AFM/CLI host: `pkgs/xsoulspace_inference_apple_foundation`
    (`bin/harnessd.dart`, `lib/src/harness_acp_backend.dart`,
    `lib/src/coding_agent_runner.dart`)
  - ACP toolkit: `~/mcp/cline/intentcall/packages/acp_toolkit`
  - AE: `~/xs/agentic_executables` (wire: `agentic_executables_wire`)
  - pi (the outer agent you may integrate with): `pi` SDK/extensions —
    see pi docs under the installed package, and the skill at
    `~/mcp/cline/skill_steward` (MoE + harness-engineering-lifecycle for
    method; do not over-process).

## Read order (non-negotiable, before any change)

1. `pkgs/xsoulspace_agentic_harness/docs/agent/PLAN.md` — R6/R7 tracks,
   standing rules, cleanup ledger
2. `docs/decisions/0023_filesystem_projection_target_edit_as_rederivation.md`
   — THE decision you implement (filesystem = projection target; edit
   moves; packs; daemon persistence)
3. `docs/decisions/0022_workspace_oracle_meaning_pipeline.md` + R6 evidence
   (`pkgs/xsoulspace_agentic_dart_meaning/test/`, `results_r6.md`)
4. `results_etl_scale.md` (repo-scale verdict + open findings) and
   `pipeline_coding.md` (the law, budgets, invariants)
5. Code: `pkgs/xsoulspace_agentic_dart_meaning/lib/src/`
   (`code_etl.dart`, `repo_etl_tool.dart`, `dart_materializer.dart`,
   `workspace_meaning_runner.dart`) and
   `pkgs/xsoulspace_agentic_harness/lib/src/tools/meaning_query_tools.dart`,
   `lib/src/meaning/meaning_tree.dart` (meaningCut, impactFrontier),
   `lib/src/meaning/meaning_program.dart` (op VM + materializer template)

## Invariants you must not break

- The model NEVER writes code tokens, never sees an AST, never holds the
  whole tree. Host materializes; mechanical oracles verify.
- Every budget is monotonic (maxToolRounds 12/chain, maxRetries 3,
  maxGoalAttempts 3 — widened by escalation, never reset).
- Every harness test ends `expectIdle(world)`.
- Every published row states backend, decision path, tokens source,
  composition, and n. Failures are classified data — never dropped.
- The code tree is RE-DERIVABLE: never snapshot it. Snapshots carry beats,
  verdicts, budgets only (ADR 0023 §2).
- New Components append at the END of `AgentPlugin.install` (ecsly id
  order) — only if you must add components; prefer resources.

## TASK 1 — R7b (CRITICAL PATH): the span-edit materializer

The actor's ACT verb for existing code. Semantic edit moves in; host
span-anchored patches out; mechanical verification; auto-revert.

1. New host module `pkgs/xsoulspace_agentic_dart_meaning/lib/src/span_editor.dart`:
   - `SpanEditMaterializer`: given the meaning tree (symbols carry
     `file`+`line` props) + an edit move, produce a list of
     `SpanPatch{file, startLine, endLine, replacement}` — computed
     host-side, deterministic.
   - Move vocabulary (ONE tool `edit_symbol`, MINIMAL closed enum — B4
     lesson: rename was deleted twice, as a surface-duplication (ADR 0016
     era) and as a parallel text-patch path (B4, `tree_patch.dart`); do
     not rebuild either mistake):
     - `apply_executable{executableId, symbolId, params}` — the PRIMARY
       verb; edit executables come from the default pack + project packs
       (ADR 0019 §4: growth is pack/data-driven, never hand-added verbs);
     - `replace_member_body{memberSymbolId, opChain}` and
       `insert_member{classSymbolId, opChain, params}` — the only
       model-composed moves (R6 compiler compiles the body);
     - cross-file operations — `rename`, `move` — are DEFAULT-PACK edit
       executables that expand over the `impactFrontier` (refs edges,
       hard-capped, degree-ranked) into per-file patches. NOT core
       sub-actions. Ambiguity (same-name symbols, unresolved ids) bounces
       as structured data — never guess; `dart analyze` is the oracle.
   - Sequencing: land `replace_member_body`/`insert_member` FIRST (proves
     the materializer), the rename executable SECOND (proves frontier
     expansion). Both must be gated before the write demotion.
   - Host-side validation BEFORE applying: closed vocabulary, symbol exists,
     target spans parse (file line count), patch does not overlap another
     pending patch. Invalid → structured failure with the exact repair
     move (B2 dialect). Never partially apply a multi-patch edit: all
     patches or none.
2. FENCES (host-enforced, gate-asserted — the critical part):
   (a) expressiveness: a `replace_member_body` chain using state ops,
       async, or external APIs bounces as named data (the v1 dart target
       compiles pure/static-like bodies only — never silently downgrade a
       working member);
   (b) ORACLE COVERAGE: a legacy member may be replaced only when the test
       ETL derives expectations covering it — the actor never sees the old
       body text, so an uncovered replacement would destroy untested
       behavior with nothing in the pipeline noticing. Uncovered →
       structured bounce: add coverage first (routes to pack/operator);
   (c) integration: the compiled body must match the declared signature and
       the file's identifiers — validated before generation.
   Atomic batches: a move expanding to N patches (rename executable) is
   all-or-nothing (in-memory revert) with a mandatory lock pre-check over
   the single-writer `FileLockTable` — batch is a property of the
   executable, never a second tool.
3. Application + verification (the mechanical tier, ADR 0021):
   - Apply patches → run `dart analyze` (workspace) → run workspace
     convention (`resolveWorkspaceCheck`) → on ANY failure: revert every
     patch of this move (keep pre-patch bytes in memory; no git needed) and
     return the structured failure to the actor with the failing detail.
   - `edit_symbol` tool registration: same registry discipline as
     `repo_etl`/`meaning_zoom` — in `repo_etl_tools_test.dart`'s style, add
     to the dart_meaning host; the core learns no Dart (ADR 0015).
4. Budgets: each edit move consumes one tool round; a failed edit consumes
   `AttemptCount` via the existing `RunGradedGoalPolicy` (wire the goal
   loop exactly like `workspace_meaning_runner.dart` does). maxGoalAttempts
   3; escalation widens monotonically.
5. GATE (must pass, LLM-free, in
   `test/span_edit_gate_test.dart`): a scripted actor on a repo-scale world
   (harness-package fixture jail, scanned via `repo_etl`) performs a
   multi-file change — rename one symbol AND insert one member in another
   file — via `edit_symbol` moves only. Assert: `dart analyze` exit 0 +
   workspace convention green after the moves; ZERO `read` and ZERO
   `write` tool calls exist in the registry AND in the thread beats; every
   intermediate invalid move was bounced as structured data and the
   auto-revert restored bytes on a deliberately-failing scripted move
   (second scripted variant); the three fences are gate-asserted with
   dedicated scripted variants: a state-op chain bounces (fence a), a
   replacement of an uncovered legacy member bounces (fence b), and a
   signature-mismatched chain bounces before generation (fence c).
6. Hard cut: the write demotion is a PRECONDITION of the edit tier, not a
   follow-up — the moment `replace_member_body` + `insert_member` gates
   green, remove `write` from the intent-surface registry in
   `workspace_meaning_runner.dart`'s descendants and mark the run-graded
   arm legacy-host-only in `coding_agent_runner.dart` (do NOT delete it;
   direct-profile hosts still use fs_tools). Two co-equal edit paths is
   the exact shape B4 deleted — do not ship it.

## TASK 2 — R7c: daemon holds the world (and fix the daemon's known gaps)

`harnessd` becomes the long-running surface. Known gaps you must close
(recorded in earlier review, all in
`pkgs/xsoulspace_inference_apple_foundation/lib/src/harness_acp_backend.dart`
+ `bin/harnessd.dart`):

1. Per-workspace persistent world: key sessions by `cwd`; the code tree is
   built once per workspace via `repo_etl` and NEVER snapshotted; a
   mechanical tick (`refresh`) re-scans mtime-changed files before each
   prompt. Snapshots persist beats/verdicts/budgets only.
2. `loadSession: true` — implement session restore from the snapshot store
   (the P5 machinery exists; the current docstring CLAIMS resume while the
   capability flag denies it — fix the lie in the honest direction).
3. `requestPermission` must stop returning `allow` unconditionally — route
   it to the write gate / edit approver (deny-by-default).
4. `cancelSession` must plumb into generation cancellation (the AFM bridge
   has `xs_fm_cancel`; the timeout sweeper exists) — no more no-op.
5. Escalation cap: `maxGoalAttempts: 3 + escalationRounds` needs a hard
   ceiling (e.g. 9) — unbounded widening contradicts the budget discipline.
6. Default backend: on macOS default to `apple_foundation_afm`; hosted
   OpenRouter becomes the explicit escalation flag (AFM-first, ADR North
   Star).

## TASK 3 — pi replaces its own tools via the daemon (the ask)

Goal: a pi agent session completes real code work with pi's native
`read`/`write`/`patch` DISABLED, all file access via `harnessd` (coding
agent underneath).

1. Expose the R7 tool surface over ACP so the outer agent never touches
   files: extend `HarnessAcpBackend` so `session/prompt` runs the actor
   with the registry [repo_etl, meaning_zoom, meaning_impact, edit_symbol,
   run checks] — and stream each tool call as `session/update`
   (tool_call_update with REAL ids — the current `_Telemetry` uses the
   tool NAME as id; make ids unique per call).
2. Build the thinnest correct pi integration — choose ONE, in this order
   of preference:
   a. a pi extension that registers daemon-backed tools
      (`zoom`, `impact`, `edit`, `verify`) over stdio JSON-RPC to
      `harnessd` and BLOCKS the built-in read/write/patch tools for
      sessions flagged `--harnessd`;
   b. a driver script (like `benchmark/pi_driver`) that pins the pi agent
      to the daemon as its only file surface and records the transcript.
3. GATE (record to `benchmark/runs/r7_daemon_transcript.txt`): one pi
   session on the harness repo performs: scan → zoom → impact →
   `rename_symbol` (a private symbol, low blast radius) → verify green —
   with pi's own fs tools disabled, transcript proves every file access
   went through the daemon.
4. If pi integration friction blocks you twice: record the friction, ship
   the daemon-side capability + (b) driver as the fallback proof, and note
   the extension for a later pass (detour stop rule).

## TASK 4 — R7d (minimal, only if time remains): one pack-fed edit

- Extend `agentic_executables_wire` with `EditExecutableWire`
  (shape in `~/xs/agentic_executables/docs/ae_harness_etl_spec.md` §Edit
  executables) — zero-dep, syntax-only.
- One worked example in the harness fixture: `fix_loop_bound` executable
  (rename `<=`-style bound fix as insert/replace member body op-chain),
  model supplies only symbol id + executable id; scripted gate proves a
  pack-fed edit at zero authored tokens.

## Order of work (code first)

1. TASK 1 (span editor + gate) — nothing else ships before this gate.
2. TASK 2 (daemon) — unblocks TASK 3.
3. TASK 3 (pi integration + transcript gate).
4. TASK 4 only if 1–3 are green and time remains.

## Validation commands

```sh
cd pkgs/xsoulspace_agentic_dart_meaning && flutter pub get && dart analyze && flutter test
cd pkgs/xsoulspace_agentic_harness && flutter analyze && flutter test
cd pkgs/xsoulspace_inference_apple_foundation && dart analyze && flutter test
sh tool/check_bridge_swift.sh   # only if you touched the native bridge
```

All suites must stay green (harness 323+, dart_meaning 17+, apple_foundation
16+ at brief time). Update `docs/agent/PLAN.md` R7 statuses and append rows
to `results_etl_scale.md` / a new `results_r7.md` with honest columns
(backend, decision path, tokens source, composition, n, failure classes).

## Definition of done

- TASK 1: span-edit gate green; `write` demoted in the meaning profile;
  rows published.
- TASK 2: daemon sessions resume, permissions deny-by-default, cancel
  works, tree refresh tick wired; `harnessd_escalation_test.dart` still
  green.
- TASK 3: transcript committed showing pi working with its fs tools
  disabled through the daemon; frictions recorded if fallback used.
- All: tests green, `expectIdle` everywhere, PLAN.md updated, failures
  classified.
