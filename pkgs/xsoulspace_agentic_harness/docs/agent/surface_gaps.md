# Surface gaps ledger — the intent-first growth loop, measured

> The law (root AGENTS.md § Harness surface routing): agents work THROUGH
> the harness surface where it covers the work. When an escape to raw
> bash/edit is honest and necessary, the escape MUST append a row here.
> A gap row is not a defeat — it is the NEXT work item: the same surface
> must later serve a 2–4k on-device model (AFM), for whom raw bash does
> not exist. Gaps close as materializer specs / surface verbs (ADR 0024/0026),
> never as new loops.
>
> Format: | date | task | what bash did | why the surface didn't cover it | gap (verb/spec to build) |

| date | task | what bash did | why the surface didn't cover it | gap (verb/spec to build) |
|---|---|---|---|---|
| 2026-09-06 | ADR 0025: rename package + move 3 lib files + 8 tests (git mv) | `git mv` + sed import rewrites | no REFACTOR executable for package-scale meaning changes; fs moves are a PROJECTION of tree structure (paths derive from meaning — ADR 0023), never model-addressed | refactor executables in the dart spec family: `rename_package` / `move_symbol` packs (model supplies executable id + params; host re-parents tree nodes and re-derives fs layout + imports; refs-frontier oracle) |
| 2026-09-06 | ADR 0025: delete 11 dead bins + 3 openrouter bins | `git rm` | no RETIRE intent; deletion is not a primitive — it is the materializer's consequence of a meaning decision (orphan pruning) | `retire_symbol`/`retire_intent` meaning verb → materializer prunes files/exports/refs; refs-frontier analyze IS the nothing-dangles oracle |
| 2026-09-06 | New files: ADRs, results docs, pubspec, TS extension, new tests | `write` | md/yaml/json/ts materializer families not landed (ADR 0024 §2) | md/yaml/json spec families (P2) + a `text` family for TS/config one-offs |
| 2026-09-06 | Bulk generated-file rewrite (sed over 12 files) | `sed -i` per-file | NO batch verb is wanted (fs-thinking relapse): the DECISION is already the batch — op chains per decision, atomic apply, one verify, revert with attribution. What's missing is (a) per-decision op-chain WIDTH for large meaning changes, (b) pack authoring for pre-known refactors | (a) host capacity: widen op rows per decision; (b) pack work-orders (AE repair packs, zero-authored-token precedent `dart/fix_loop_bound`); consent via host-side consent plans — all INVISIBLE to the model |
| 2026-09-06 | Multi-edit consent friction (would stall autonomous runs) | (avoided by using bash) | per-write request_permission; no consent plan | `session/consent_plan {scope, verbs, budget, ttl}` — one bounded grant, logged; per-write prompts only outside the plan |
| 2026-09-06 | Cross-repo work (last_answer) | direct edits | one daemon per workspace; no multi-workspace daemon (PLAN P4) | multi-workspace daemon (actor-topology P4) |
| 2026-09-06 | Whole-session verification | `dart analyze` per package via bash | `harness_verify` not exercised this session (trust gap; also ETL cold start) | measure harness-path vs bash-path on real tasks (A/B rows in results_seam_speed.md); warm daemon by default |

| 2026-09-06 | Dogfood: harness_scan via the pi extension | (extension sent prose → graded task → `dart test` over the whole monorepo, 260 s FAIL) | read tools wrapped directives in prose — the classifier correctly refused to treat them as reads (leftover prose = task) | FIXED in-session: extension sends PURE directives (`[scan]`, `harness_zoom {…}`) → mechanical read path (34–54 ms). Lesson: the classifier's strictness is the LAW working |
| 2026-09-06 | Dogfood: harness_verify via the pi extension | (not run — prose would grade `dart test` at monorepo root) | verify needs a PER-WORKSPACE convention: the root has no package convention; `harnessd_cli` lacks a `--check` passthrough and package-scoped verify | `--check` flag on `runHarnessdCli` + extension passes the active package's convention; verify = analyzer tier + scoped convention, never monorepo-wide |

| 2026-09-06 | Dogfood: daemon idle-exit bricked the session (`idle-exit after 10 minutes` → every call fails → only session restart) | (extension had a forever-cached dead client + the daemon exit(0) left stale socket pointer) | THREE compounding defects: daemon exit(0) without cleanup; socket attach without error/close handlers; ensureClient returning dead cached clients | FIXED in-session: graceful shutdown (pointer/socket/lock pruned), attach bumps idle, extension detects dead clients + retries once across respawn (HARNESSD_IDLE_EXIT_MINUTES default 30) |

| 2026-09-06 | Dogfood run #2 (reads + fixes) | five REAL defects caught by working through the surface | (1) stale AOT bundle auto-detected → served pre-0025 daemon code silently; (2) workspace-root pubspec resolved `dart test` → exit 65 (workspace needs flutter tooling); (3) the mtime tick re-parsed 1,121 files on NO changes (count mismatch: tree-node count vs enumerated dart count); (4) fs-tier rebuild churned all 2,448 nodes per tick (8.3 s); (5) new dart files never had symbols parsed by the tick (ambiguity fence blind) | ALL FIXED in-session: AOT opt-in only; workspace root → flutter test; tick = tree-driven + cutoff-gated fs rebuild + new-file ingestion (warm tick 5.8 s → 1.4 s, 0 re-parses; locked by `etl_tick_test.dart`). Registry tests: `Platform.resolvedExecutable` under flutter test = flutter_tester HANGS running CLI scripts → use `'dart'` (2 zombie processes killed; root suite green again) |
| 2026-09-06 | Dogfood: recovery retry raced a still-spawning daemon (double-spawn → attached to the loser socket) | (recovery worked on the next call) | spawn + waitForPointer is not serialized across concurrent tool calls | extension: a spawn lock/promise so concurrent ensureClient calls share one spawn (small TS fix) |
| 2026-09-06 | Warm-tick floor | ~1.4 s per prompt on the monorepo | the tick still walks the full fs (scanWorkspaceFs + dir lookups) to detect adds/drops | tree-driven fs tier: stat from stored file nodes, walk only to reconcile; target <300 ms |

| 2026-09-06 | Extensibility concern (hardcoded `FsScan.dartFiles`) | (design review, no bash needed) | the class→extractor wiring was hardcoded (tick filtered `.dart` by label suffix, scan called `scanDartFile` directly) | CLOSED: `file_class_spec.dart` — the FILE-CLASS SPEC registry (extensions + optional parse fn as data); scan, tick and code-tier dispatch all go through `specForRel`; adding md/yaml/json/text = registering a spec + a materializer spec, zero new verbs |

| 2026-09-06 | Tiny-model spec writing (the frontier unlocked as DATA) | (no bash — the unlock is a prompt + a validator) | a model-written spec cannot land safely without a mechanical validator | `spec_check` tool: schema + golden round-trip + oracle-failability + fence-name resolution → PASS registers the spec as data, FAIL bounces with named repair. Work order: `docs/agent/prompts/spec_writer_work_order.md` (standing preamble = the nine laws) |
| 2026-09-06 | Dogfood: extension double-spawn race | FIXED (closure row for the row above): `ensureClient` serialized behind ONE shared in-flight promise (concurrent callers await the same spawn/attach; cleared on settle so failures retry honestly). BONUS defect found in the same pass: a failed attach after spawn left `client = spawned` — a dead stdio shell that never reports `isDead()` → now dropped so the next call re-attaches to the live daemon | (was: spawn + waitForPointer unserialized) | — |
| 2026-09-06 | Warm-tick floor (PLAN §Open issues) | FIXED: `reconcileFsTier` in fs_etl.dart — tree-driven reconcile: stat STORED file nodes (1 syscall each, no walk), listSync ONLY dirs whose own mtime moved past the cutoff (a dir mtime changes iff an entry is added/removed/renamed inside), new dirs walked fully (bounded by the same skip rules); drops + idempotent buildFsTier keep old semantics. MEASURED on the real monorepo (2,450 files): no-op warm tick **24 ms / 20 ms** (budget <300 ms PASS; was ~1,400 ms); 1-changed-file tick 17 ms. Gates: `etl_tick_test.dart` (change+add+drop+new-dir reconciled in ONE tick, no full walk) + `tool/warm_tick_probe.dart` (the measured probe) | (was: full fs walk per prompt) | — |
| 2026-09-06 | Dogfood: `harness_fs_write` bounced in remote-mover mode (THIS session; this row could not land through the surface that bounced — escaped to raw edit, honestly) | the whole-file content rides the directive as a graded TASK; the mover model refused the huge payload → `mover_refusal: empty move` after a **9-minute wall** (547,979 ms — 6× over the 90 s turn budget) | a consented whole-file write is NOT a decision for the mover: the content is DATA and the human is the approver (session/request_permission). Routing it through the mover re-composes (and can refuse) what should be mechanical | fs_write joins the ADR 0027 PURE-directive class: `harness_fs_write {path, content}` executes mechanically in the daemon (path jail-check + review-gate consent + write + tree reconcile), zero mover involvement; the mover sees only the consent diff. REMAINING: a consent wait must not silently consume the turn budget (Phase 1.5 finding (a) — deny-on-timeout, short deadline). FIXED same session: `isMechanicalWriteDirective` + `_runMechanicalWrites` in `harness_acp_backend.dart` (jail-check → consent → write_review → tree reconcile, zero mover); gate `harnessd_mechanical_write_test.dart` (4 tests: allow lands + tree reconciles / reject never lands / no-approver refusal / mixed-prompt classification) |
| 2026-09-06 | Warm-tick reconcile itself (algorithmic Dart: imperative fs-stat loops) | raw `edit` on fs_etl.dart + repo_etl_tool.dart + etl_tick_test.dart (analyzed + suite green before claim) | FRAMING CORRECTED (was wrongly "loops can't compose"): the op vocabulary HAS maths/loops/calls (`add/sub/mul/lt/gt`, `jump`/`jump_if_false` backward = loops, step-limit 1000, `call` = intent→intent). What it LACKS is I/O executor ops (`fs_stat`) — the set is pure by design | the verified-growth route (ADR 0022 §3): an `fs_stat`/fs-I/O executor op lands AS DATA (spec + VM semantics + parity test) pulled by a failing task — then the reconcile composes as intents. Also: pipeline_coding.md must SAY this ("a capability gap routes through executor-op growth, never body editing") — it didn't, which is why the session missed it |

| 2026-09-06 | Lost-decision audit (session retrospective) | (investigation, no code) | FOUR built decisions were unwired/undermentioned: (1) `locate` (ADR 0014 §2, Stage 1.5) — the structural discovery ray-cast — was exported only from `benchmark_api.dart`, absent from the meaning profile, the daemon registry and the pi extension; (2) `jump`/`call`/math ops make algorithmic intent bodies EXPRESSIBLE (see corrected row above) — undocumented in pipeline_coding.md, so agents conclude "closed vocabulary can't do it"; (3) R9.1 workspace consent (`.harnessd/consent.json`) auto-applies per session but was never wired into the pi flow; (4) planning mechanics (ADR 0009 `projectPlanFrontier` — the next-actionable frontier as token-budgeted projection) never surfaced as "use EVERYWHERE, including free-form → structural" guidance | ALL WIRED/DOCUMENTED 2026-09-06: (1) `meaning_locate` tree-native ray in meaning profile + daemon read world + scripted actor + pi extension, gate `meaning_locate_tool_test.dart`; (2) two-layer vocabulary + capability-gap law in pipeline_coding.md; (3) mechanical write path inherits the consent plan (plan-allowed writes answer mechanically) + `.harnessd/consent.json` shipped for this repo; (4) "Planning is projection" section in pipeline_coding.md |
| 2026-09-06 | R9.1 investigation A instrumentation (apple_foundation) | (a) Swift bridge edit `bridge.swift` via raw edit (meaning surface is Dart-only — no Swift materializer/verb); (b) member-level Dart edits (`native_client.dart` infer pre-flight log, `hook/build.dart`) via raw edit — the tree indexes the CLASS symbol only, not its members, so `harness_edit` `replace_member_body` had no symbol to target; (c) new probe file `tool/afm_flatness_probe.dart` via write (no bin-script materializer); (d) `cp` of the rebuilt dylib to `.dart_tool/lib` (infra op) | the meaning surface cannot carry Swift bridge work or member-level Dart instrumentation; new-file + dylib-copy are file ops, not meaning moves | verbs to grow: (1) a native/Swift-tier story (spec or declared escape) so bridge work is surfaced; (2) member symbols under indexed classes so `replace_member_body` reaches method bodies; (3) probe/tool scripts as surface-runnable artifacts (the R9.1 probe is exactly the kind of thing a tiny model should drive through a verb, not raw dart run) |

## Closed gaps (moved to results when landed)

(none yet — this ledger was opened 2026-09-06)

## Non-goals

- **No GitHub/tracker integration.** Tasks enter as plain task sentences +
  the workspace convention (`--check`); the workspace oracle is the gate.
  An external tracker would add a protocol level the composition law
  forbids (no second protocol, ever).

## 2026-09-06 — member reorder + import lint (mechanical tier escape)

- **What bash/edit did**: fixed `sort_constructors_first` + `unnecessary_import`
  + `unnecessary_parenthesis` in `test/one_move_contract_test.dart` (ADR 0028
  gate, landed uncommitted by the concurrent session) via the `edit` tool.
- **Why the surface didn't cover it**: `harness_edit` actions are
  `replace_member_body` / `insert_member` / `apply_executable` — there is NO
  member-REORDER verb (moving a constructor above a field) and no
  import-directive edit verb. `harness_fs_write` is forbidden for Dart.
- **DISPOSITION (2026-09-06, owner decision): SKIP — not a surface verb.**
  Lints are configurable PER PROJECT, so they are not generalizable into the
  meaning surface; lint-class repairs route to the tools that own them:
  `dart fix` / the analyzer's own fix arm, or a per-project custom-lint /
  lint-CLI pack. The span surface stays structural (meaning moves), never
  lint-shaped.

## 2026-09-06 — trusted-author tier bootstrap (cross-repo wire + span editor)

- **What bash/edit did**: (a) edited `EditExecutableKind` in the SEPARATE
  `~/xs/agentic_executables` repo (outside every registered workspace root —
  the meaning tree does not cover it); (b) constructor/field/switch-case
  changes in `span_editor.dart` (op-chain verbs cannot express constructor
  signatures or enum-case additions); (c) fixed the expression-bodied cursor
  bug in `_memberSite` (same non-body-shape limits); (d) wrote the pack
  entry JSON (host data; in a real session this routes through
  `harness_fs_write` + consent — here the session was the trusted author,
  diff published in `benchmark/runs/trusted_author_row.md`).
- **Why the surface didn't cover it**: the tier under construction IS the
  missing verb (chicken-and-egg — its own bootstrap cannot ride it); the AE
  wire repo is not a registered root; Dart structural changes (constructor
  params, enum cases, member reorders) are outside
  replace_member_body/insert_member/apply_executable.
- **The verb/spec to build**: (1) register the AE wire repo as a workspace
  root (or export its tree into the hub — AE knowledge plane, PLAN P3); (2)
  structural executables for class-shape changes (add param, add enum case)
  as trusted-author pack kinds — the authored-body tier is the right host.

## 2026-09-06 — P3 AE knowledge plane gate (cross-repo wire, lane C)

- **What bash/edit did**: edited `agentic_executables_wire/lib/src/meaning_tree_export.dart` + `test/meaning_tree_round_trip_test.dart` in the SEPARATE `~/xs/agentic_executables` repo (outside every registered workspace root — the meaning surface does not cover it); verified via `dart test`/`dart analyze` there (26 tests, 0 issues).
- **Gap (verb/spec to build)**: hub/registry wiring — `ae know` construct/deconstruct over `.ae_ln/` canonicals so harness intent/plan/spec populations package through `ae.knowledge_pack.v1` (PLAN P3 remains: seam proven, wiring named-not-built).

## 2026-09-06 — new-file materializer bootstrap (md, lane B)

- **What bash/edit did**: (a) wrote the NEW files `md_materializer.dart` +
  `test/md_materializer_test.dart` (pkgs/xsoulspace_agentic_workspace) via
  the write tool — the materializer under construction IS the missing verb
  (its own bootstrap cannot ride it, same chicken-and-egg as the
  trusted-author row); (b) additive Dart edits outside the op-chain
  vocabulary via the edit tool: `MaterializerSpec` registration plumbing in
  `file_class_spec.dart` (shared with the concurrent lane; consolidated to
  one registry map + `materializerSpecFor`), `fs_etl.dart` md map
  delegation to the materializer's ONE heading parser
  (`parseMdSections` — map and emitter must agree byte-precise), and the
  package export.
- **Why the surface didn't cover it**: `harness_edit` actions
  (replace_member_body/insert_member/apply_executable) compile pure
  op-chains into member bodies — they cannot add a registry map, a
  top-level const, a new file, or re-point a private top-level function's
  body at a new import; the coverage fence also requires prior suite
  coverage, which a bootstrap cannot have.
- **The verb/spec to build**: none new — the gap CLOSES as the landed
  spec itself (`materializerSpecs['md']` + `edit_section`); future md edits
  in this repo route through the verb, not bash. Structural-class-shape
  changes (constructor params, top-level consts) remain a generic gap: the
  trusted-author row's "structural executables" kind covers them when
  evidence demands.

## 2026-09-06 — packConsent daemon wiring (constructor plumbing, lane A)

- **What edit did**: additive constructor plumbing in
  `pkgs/xsoulspace_agentic_host/lib/src/coding_agent_runner.dart` (new
  `packConsent` param + materializer construction at the
  `editSymbolTool` registration), a new sync plan-answer closure in
  `harness_acp_backend.dart` (threaded into `runCodingAgentOnce`), a
  pubspec path-dep line, and the new gate
  `test/harnessd_pack_consent_test.dart` (2 tests, green; full host suite
  43/43). `harness_scan` ran first; `harness_locate`/`harness_edit` were
  NOT used.
- **Why the surface didn't cover it**: the change is constructor/call-site
  plumbing (thread a callback through a parameter list and a registry
  call) plus a top-level test FILE — `harness_edit` compiles pure
  op-chains into COVERED member bodies and cannot add constructor params,
  re-point call sites' named args, or bootstrap a new file (the coverage
  fence requires prior coverage). Same generic structural-class gap lane B
  named above.
- **The verb/spec to build**: none new — the trusted-author
  "structural executables" kind covers constructor-param threading when
  evidence demands; new-file bootstrap remains the materializer-spec gap.

## 2026-09-06 — `ae know` CLI + hub manifest (P3 knowledge plane, lane G)

- **What bash/escape-hatch did**: lane G edited `~/xs/agentic_executables`
  (OUTSIDE the meaning surface) with root_edit/write/bash: added the
  `ae.hub_manifest.v1` wire contract (`agentic_executables_wire`, new file
  `hub_manifest_wire.dart` + `canonicalJsonForm` extraction), the `ae know`
  command in `agentic_executables_cli/lib/src/cli.dart` (parser case +
  `_handleKnow`/`_knowBuild`/`_knowExport`/`_knowImport`/`_writeKnowPack`
  handlers inserted by exact-text edit), and two new test files. No dart
  code in dart_flutter_packages packages was touched.
- **Why the surface didn't cover it**: the repo is not registered as a
  meaning-tree workspace root — `harness_scan`/`harness_edit` operate on
  dart_flutter_packages only, so cross-repo Dart edits fall back to the
  honest-edit path by routing (AGENTS.md: "everything else … bash is
  HONEST and allowed" with this note).
- **The verb/spec to build**: a cross-root meaning surface — register
  sibling repos (e.g. `~/xs/agentic_executables`) as harnessd roots so
  `harness_scan`/`harness_zoom`/`harness_edit`/`harness_verify` cover their
  Dart packages too; the `ae know`/hub-manifest work is exactly the kind of
  seam-first change (wire contract + CLI verb + round-trip gate) the
  meaning surface is designed to edit through.

## 2026-09-06 — P3 VCS-as-meaning projection bootstrap (lane H)

- **What bash/edit did**: (a) wrote the NEW files `lib/src/meaning/vcs_meaning.dart` +
  `test/vcs_meaning_test.dart` via the write tool — the projection under construction IS
  the new meaning surface (same new-file bootstrap gap lane B named: `harness_edit`
  compiles op-chains into COVERED member bodies and cannot create files); (b) ran
  `git init/commit` in SYSTEM TEMP fixture dirs inside the GATE (test-side fixture
  commands, never model surface; the adapter itself is jailed to
  `gitReadOnlyCommands` = {status, branch, log, rev-parse} with named refusals).
- **Why the surface didn't cover it**: new-file bootstrap (no prior coverage → the
  coverage fence cannot admit it) plus fixture repo setup that must run OUTSIDE the
  jail by design.
- **The verb/spec to build**: none new for reading — the projection lands as pure
  MeaningNode/MeaningProps/MeaningEdge data consumable through the EXISTING
  locate/zoom rays. NAMED, NOT BUILT (registration seam, owned with lanes E/F): (1)
  export `vcs_meaning.dart` from the package barrel + wire `projectVcsMeaning` into
  the daemon's tree-refresh tick (alongside repo_etl) so `vcs.repo` nodes enter the
  live workspace world; (2) mutation verbs (branch/create, stage/commit as meaning
  moves) stay with the edit tier — deliberately not built this round.

## 2026-09-06 — Execution-as-meaning bootstrap (lane F)

- **What the meaning surface did**: `harness_scan` → `harness_locate`(`runTool`)
  → `harness_zoom`(point) before any edit (34 ms / 16 ms walls — ADR 0027
  confirmed); then `harness_edit` `replace_member_body` on the runTool symbol was
  REFUSED (`mover_refusal: empty move` — no captured `EditExecutableWire` for an
  uncaptured symbol whose "body" is a `ToolDef.encode(...)` expression wrapping a
  nested `execute` closure).
- **What the edit tool did**: (a) `runTool` signature change (new optional
  `RunMeaningRecorder? meaning` param) + nested-closure body threading
  (allowlist-scope capture, stopwatch, `meaning?.recordOutcome` on
  success/timeout/spawn-error) + one import line in `lib/src/tools/fs_tools.dart`;
  (b) wrote NEW files `lib/src/meaning/execution_meaning.dart` +
  `test/execution_meaning_test.dart` (same new-file bootstrap gap lane B/H named:
  the coverage fence cannot admit a file it has never covered).
- **Why the surface didn't cover it**: `edit_symbol`'s span currency is top-level
  member bodies with captured executables — it has no verb for (1) signature
  changes on uncaptured symbols, (2) editing NESTED closures inside a returned
  expression body, (3) import insertion, (4) new-file bootstrap.
- **The verb/spec to build**: a capture path that admits `ToolDef` factory bodies
  (the execute closure as a named sub-executable: `runTool/execute`), so the
  run tool's meaning-threading evolves through the surface like any other member;
  plus the standing new-file bootstrap verb. Nothing re-implemented in bash — the
  escape was one honest edit-tool pass, logged here per the routing law.

## 2026-09-06 — Pack inventory as meaning nodes + task-grammar classifier (lane E)

- **What the meaning surface did**: `harness_scan` → `harness_locate`/`harness_zoom`
  to read `repoEtlTool`, `editSymbolTool`'s pack load loop, `meaning_locate`'s ray
  and the `RunGradedGoalPolicy`/`ReActContinuationPolicy` flow order before any
  edit; `harness_edit` was NOT used for the code changes of this lane.
- **What the escapes did**: (1) wrote NEW files `lib/src/meaning/capability_nodes.dart`,
  `lib/src/tools/task_grammar.dart` + three NEW test files (the standing new-file
  bootstrap gap — same shape lanes B/F/H named; the coverage fence cannot admit a
  file it has never covered); (2) applied multi-block exact-text edits via the
  host edit tool on `repo_etl_tool.dart` and `coding_agent_runner.dart` (5-block
  and 3-block replacements around non-member code: import lists, result-map
  literals, spawn arguments — `edit_symbol`'s member-body span currency has no
  verb for import-list or multi-site literal splices on uncaptured symbols);
  (3) two mechanical `python3` inline splices for const-correctness fixes in the
  new test file.
- **Why the surface didn't cover it**: same named gaps as lane F — no new-file
  materializer verb; no verb for import-block / argument-list / map-literal edits
  (the span tier covers member bodies with captured executables only).
- **The verb/spec to build**: new-file bootstrap verb + an "anchored splice"
  edit class (import block, argument list, record/map literal) with the same
  fence family; then this lane's edits become `edit_symbol` moves.

## 2026-09-06 — lane D finishing pass (yaml/json materializer, post-timeout)

- **What bash/edit did**: the lane D subagent died on an upstream idle timeout
  after writing `yaml_json_materializer.dart` but before integration. The
  finishing pass (main session): fixed 6 compile errors in the interrupted
  generation (dead `_finalize`, `_OpenEntry.indexPlaceholder` → `index0`,
  `_short` promotion, `trimEnd` → `trimRight`), added the `edit_key` ToolDef,
  registered the yaml/json `MaterializerSpec`s, barrel export, `yaml` dep,
  and the gate `test/yaml_json_materializer_test.dart` (6 tests) — via the
  `edit`/`write` tools, not the meaning surface.
- **Why the surface didn't cover it**: interrupted-generation repair (dead
  code removal, constructor reshapes) is outside the member-body span
  currency; the gate + wiring bootstrap is the known new-file class.
- **The verb/spec to build**: covered by the earlier new-file bootstrap +
  anchored-splice rows (lanes B/E/F). ADDITIONAL finding from the gate: the
  json emitter needed a comma fix-up whose fence must WIDEN to the adjusted
  adjacent line — `keypath_splice`'s fence contract should name
  "adjacent-line punctuation repair" as part of the intended change.

## 2026-09-06 — lane B′ (VCS registration seam + zoom staleness)

- **What bash/edit did**: (1) one barrel export line (`vcs_meaning.dart` in
  `lib/xsoulspace_agentic_harness.dart`); (2) restructured the
  `meaning_zoom` `execute` closure in `meaning_query_tools.dart`
  (multi-site splice inside one closure body: staleness re-stat before the
  cut, `refreshed`/`refreshed_path` result fields, null-safe span props
  re-read) plus a NEW typedef + `Resource` class
  (`MeaningNodeRefresher`/`MeaningNodeRefresh`); (3) new top-level
  functions in the workspace pkg (`registerMeaningNodeRefresher` in
  fs_etl.dart, `_projectVcs` + four result-map splices in repo_etl_tool.dart);
  (4) new test files (`vcs_registration_test.dart`, a staleness gate in
  md_materializer_test.dart, `tool/zoom_staleness_probe.dart`); (5) scoped
  per-package test runs via `flutter test` in the package dir.
- **Why the surface didn't cover it**: `harness_edit`'s span currency is
  member bodies/insert-members with captured executables — no verb for
  (a) barrel export lines, (b) top-level type declarations (typedef +
  Resource class), (c) closure-body restructures with map-literal splices
  at multiple sites, (d) new files (the known new-file class). The run
  tool's allowlist has NO package-cwd scope: `dart test` from the repo
  root fails on flutter deps ("Because xsoulspace_monetization_rustore
  requires the Flutter SDK") — every scoped test run escaped to bash.
- **The verb/spec to build**: (a) a package-scoped cwd pin on the run tool
  (`{"command":["dart","test",…],"pkg":"xsoulspace_agentic_harness"}` or
  auto-derive from the path scope) — closes the EVERY-session escape;
  (b) covered by the standing new-file + anchored-splice rows (lanes B/E/F/D);
  (c) a `declare_resource`/`declare_typedef` insert verb for top-level
  declarations would have covered the `MeaningNodeRefresh` half of this lane.

## 2026-09-06 — lane A′ consent-UX hardening (host P1)

- **What bash/edit did**: (a) the P1 consent-UX changes in
  `harness_acp_backend.dart` (permission deadline as data, the bounded
  `_askClientPermission` round-trip with Timer/Completer/closures,
  cancel-interrupts-permission-waits, F3 path-attribution audit) and the new
  gate `test/harnessd_consent_ux_test.dart` landed via the `edit`/`write`
  tools, not `edit_symbol`; (b) scoped test runs
  (`flutter test test/harnessd_consent_ux_test.dart` etc.) ran via bash.
- **Why the surface didn't cover it**: (a) the bodies race a client answer
  against a `Timer` deadline and a cancel `Completer` with `unawaited`
  observers and try/catch — outside the closed op-chain compiler
  (`compileOpChainBody`: state ops, literals, jumps; no async, no closures,
  no try/catch), and the constant/typedef/field additions are top-level or
  constructor-initializer shapes `replace_member_body` does not span;
  (b) the daemon `run` tool executes from the workspace root only — it has
  no cwd arg, so a per-package `flutter test` fails pub resolution
  (`xsoulspace_monetization_rustore requires the Flutter SDK`).
- **The verb/spec to build**: (a) a `replace_member_body` escape for
  imperative async bodies — either a wider `authoredBody`-style span
  materializer for host Dart (fenced whole-member splice with the existing
  capture/revert oracles) or compiler growth for try/catch + await +
  closures; plus top-level declaration insert (`declare_const`,
  `declare_typedef`) and constructor-initializer edit verbs; (b) a `cwd`
  (workspace-relative) param on the mechanical `run` directive — the
  allowlist stays, the jail resolves the scope.

## 2026-09-06 — lane C′ per-package verify derivation (P1)

- **What bash/edit did**: (a) the derivation (`derivePerPackageVerify`,
  `pendingEditsOf`/`sessionTouchedFiles` — new top-level functions + the
  record/typed-hole walk restructure in `verify_tiers.dart`), the
  `RunGoalCommand` type + field additions on `RunGoalPlan`, the multi-step
  imperative `runGoalVerifier` body (per-step loop, fail-fast,
  `verify_wall_ms` beat stamp), the per-package final-gate closures in
  `coding_agent_runner.dart`, and the new gate
  `xsoulspace_agentic_host/test/harnessd_per_package_verify_test.dart`
  landed via the `edit`/`write` tools, not `edit_symbol`; (b) scoped test
  runs (`flutter test test/…` inside pkgs/xsoulspace_agentic_harness /
  xsoulspace_agentic_host) ran via bash — `harness_run` executes from the
  repo root only, where `dart test` fails pub resolution (the standing
  no-package-cwd row below, measured again this session).
- **Why the surface didn't cover it**: (a) the derivation is new
  top-level function/class-declaration authorship plus an imperative
  async body with records, early returns and a Stopwatch — outside the
  closed op-chain compiler and the member-body capture verbs (same class
  as the lane A′ row); `RunGoalPlan` field additions + a new record type
  are declaration-shape edits no verb spans; (b) unchanged: the mechanical
  run directive has no cwd/pkg scope.
- **The verb/spec to build**: (a) covered by the standing new-file +
  anchored-splice + imperative-body rows — no new verb class observed;
  (b) the package-scoped run scope (`{"command":["dart","test",…],
  "pkg":"…"}` or auto-derived from the file scope) remains the single
  highest-frequency escape; NOTE: this very task fixed the VERIFY seam of
  that gap (per-package verify derivation + `RunGoalCommand.cwd`), so the
  remaining escape is only the interactive test-run surface.

## 2026-09-06 — lane D′ afm_wave_gate driver (new-file bootstrap, apple_foundation)

- **What bash/edit did**: (a) the new gate driver
  `pkgs/xsoulspace_inference_apple_foundation/bin/afm_wave_gate.dart` (the P1
  REAL-model gate rows for the four 2026-09-06 surface-wave tiers:
  task-grammar pre-pass, trusted-author consent, `edit_section`, `edit_key`)
  landed via the `write` tool — a NEW file has no meaning node to focus, so
  the whole-file bootstrap cannot ride `edit_symbol`; (b) the package's
  `pubspec.yaml` gained two workspace-local deps
  (`xsoulspace_agentic_workspace` for the REAL md/yaml materializers the
  `--dry` mode validates against; `agentic_executables_wire` for the
  authored-body wire enum) — a yaml edit outside any materializer's jail.
- **Why the surface didn't cover it**: (a) the standing new-file class —
  bootstrapping a file is not a meaning edit over an existing node; the
  meaning surface grows by registration, not by authoring new registries
  model-side; (b) pubspec is class `yaml` in the file-class spec, but the
  workspace's OWN pubspec is outside the daemon's per-workspace jail (the
  daemon serves the package workspace, not the monorepo root), so
  `edit_key` had no workspace to serve it in.
- **The verb/spec to build**: (a) a `file_bootstrap` verb (`{path, content,
  reason}`) — mechanical jail-checked write + tree reconcile, the
  `harness_fs_write` shape extended to CREATE (registered files only), so
  new-file bootstraps leave the raw-write class; (b) a workspace root that
  spans the monorepo (multi-workspace daemon, PLAN P4) so the repo's own
  yaml/md files are in-jail and the yaml/md edit verbs can serve them.

## 2026-09-06 — lane C′ follow-up: harness_edit has NO mechanical directive path (mover_refusal ×3, measured)

- **What bash/edit did**: nothing — three `harness_edit {insert_member …}`
  delegations through the remote-mover daemon each ended
  `mover_refusal: empty move` (walls 103 s / 117 s / 183 s, each burning a
  root-convention fallback verify). The single-package verify derivation
  could NOT be exercised end-to-end by the agent: the touched-file beat
  never landed because the mutation verb routes through the mover
  round-trip, and the mover model closed every decision empty.
- **Why the surface didn't cover it**: reads (`[scan]`/`[zoom]`/
  `harness_locate`), `harness_run {…}` and `harness_fs_write {…}` all have
  MECHANICAL directive paths (`isReadOnlyDirectivePrompt` /
  `isMechanicalRunDirective` / `isMechanicalWriteDirective`) —
  `harness_edit {…}` does not: in remote-mover mode it is always a graded
  mover task, so the one verb that feeds the per-package verify
  derivation is the one verb with no deterministic route.
- **The verb/spec to build**: a mechanical edit-directive path for
  `harness_edit {…}` payloads — same shape as the write path
  (payload-validated, edit-approver consent round-trip, dropped-payload
  accounting, beat lands on the goal actor's thread) — or, minimally,
  mover-refusal fallback that executes a SINGLE well-formed
  `harness_edit` payload mechanically instead of grading the root
  convention. Until then, a mover flake costs a full root verify.

| 2026-09-07 | ADR 0033: member/function-scale Dart refactor (extract `buildMeaningProfileSurface` + `deriveContextRow` into new host files; rewire runner) | raw `edit`/`write` on 5 Dart files + 3 new files (analyzed + suites green before claim) | `harness_edit` actions are `replace_member_body`/`insert_member`/`apply_executable` on indexed symbols — a cross-file FUNCTION EXTRACTION (move ~70 lines into a new exported function, rewire the call site, re-thread two params) has no meaning move; the tree indexes the class symbol only (known gap, R9.1 row) | a `extract_function`/`move_members` refactor executable in the dart spec family (refs-frontier oracle already exists); member symbols under indexed functions |
| 2026-09-07 | ADR 0033 §4: Swift bridge change (`end_after_tool` flag in bridge.swift) + bridge regression run (`check_bridge_swift.sh`) | raw edit on bridge.swift + `sh tool/check_bridge_swift.sh` (17/17 pass) | the meaning surface is Dart-only — no Swift materializer/verb (declared escape, R9.1 row) | native/Swift-tier story (spec or declared escape) so bridge work is surfaced; the flag itself is the mechanism that lets the harness END the native loop without any Swift-side model trust |
| 2026-09-07 | ADR record repair: renumber duplicate ADR 0030 → 0032 (`git mv` + README index) | `git mv` + sed | file renames are fs ops, not meaning moves; the ADR index is md (no md materializer yet) | md spec family (P2, ADR 0024 §2); ADR numbering check as a workspace-convention gate row |

| 2026-09-07 | ADR 0034: ONE edit verb (class-routed edit_symbol absorbs edit_section/edit_key; read world converges to meaning_program) | raw edits on 7 lib files + 5 test files (incl. python bulk rewrites of directive strings); suites green before claim | cross-file SURFACE CONVERGENCE (tool schema union + registry field rename verb→actions + relay dialect change + doc-comment repairs) has no meaning move; the tree indexes class symbols, not tool enums/relay regexes | a `converge_surface` refactor executable (spec declares the surviving verb + the absorbed verbs; host rewrites schema enum, relay payloads and teaching strings; refs-frontier oracle) |

| 2026-09-07 | ADR 0034 dispositions: parent-addressed creation (router `anchor` slot + set_key CREATE oracle bug fix) | raw edits on 4 lib files + test fixture rewrite; suites green before claim | the creation gap was found by READING the materializers' CREATE branches against the router — the meaning tree has no "capability regression" ray (zoom on a verb does not enumerate what the pre-unification verbs could do that the unified one cannot) | a `surface_capability_diff` check: when a verb is absorbed, a mechanical diff of the absorbed verbs' arg space vs the survivor's — the regression would have been named at unification time, not by hand |

| 2026-09-07 | P1 ToolCallError bounce fix (PLAN row): streaming-path named-code classification in bridge.swift (`generate-stream` catch now routes through `xsErrorClassification` → `tool_args_invalid`, same as the blocking path) + bridge regression run (`sh tool/check_bridge_swift.sh`, 27 unit passes; live-session flakes are environmental, see task report) | raw edit on bridge.swift — the meaning surface is Dart-only, no Swift materializer/verb (same declared escape as the ADR 0033 §4 row) | a native/Swift-tier story (spec or declared escape) so bridge work is surfaced; the harness-side bounce/round machinery that CONSUMES the named code is Dart and stayed on the surface |

| 2026-09-07 | ADR 0035 §1/§2/§3/§5: materializer bindings (the registry IS the format seam — kind-switch router dies, fs-tier map hardcodes die, registration-time registry linter, mechanism-first unknown-id bounce) | raw `edit`/`write` on 7 lib files + 4 test files in xsoulspace_agentic_workspace (1 new lib file + 1 new test file); full suite green before claim (86 pass, incl. 2 pre-existing failures in edit_node_unified_test repaired: slot_scoping bounce maps missing `ok:false` + an escaped-`$` test typo) | Dart edits in `pkgs/*/` have no meaning surface here: the refactor spans ROUTING (no indexed symbol to address — the switch is a control-flow shape, not a member), REGISTRY DATA (new file of binding records), and fs-tier ETL plumbing; `harness_edit` actions (replace_member_body/insert_member/apply_executable) cannot express "replace dispatch mechanism across files" (same gap class as the ADR 0033 §4 row) | a `converge_dispatch`/`register_binding` refactor executable: spec declares the registry + the bindings; host rewrites the router dispatch, kills the switch, and lints registration (the §3 linter is already the seed — it just needs to be the EDIT mechanism too, not only a gate) |

| 2026-09-07 | ADR 0035 §4: SAFE span_editor decomposition (lexical utils → `dart_lexicon.dart`, pack registry + wire validation + authored-body machinery → `edit_pack.dart` with `EditPackRegistry`; span_editor keeps its public API and delegates) | raw `edit`/`write` on 2 lib files + 2 new lib files in xsoulspace_agentic_workspace; analyze identical to baseline (214 issues, all pre-existing) + full suite green (86/0) before claim | a mechanical CODE MOVE between libraries has no meaning move: the tree indexes class symbols in one file — there is no verb for "relocate members to a new/existing library and rewrite call-site prefixes" (member spans don't carry their library), and `_`-private helpers can't cross libraries without the rename that only the host can do atomically (same gap class as the ADR 0033 §4 row) | a `move_members`/`extract_library` refactor executable: spec declares the source members + target library + renames; host performs the relocation, de-privatizes, rewrites call sites, and re-runs the scoped analyze oracle (the gates — span_edit_gate/pack_edit_gate/edit_pack_capture — already exist as the verify tier) |

## 2026-09-08 — the session's own reads route through the mover (extension lags the graduated read dialect)

- **What happened**: this pi session's `harness_locate` / `harness_zoom`
  tool calls DELEGATED to the mover model (~140 s each, `mover_refusal`)
  instead of the mechanical read path — the extension still wraps the
  LEGACY per-verb read tools, while the daemon's graduated read world
  (ADR 0034) serves ONE `harness_meaning_program` directive. The exact
  drift class the wave rows measured (stale teaching vs the graduated
  surface), reproduced by the session itself.
- **Why the surface didn't cover it**: the pi extension
  (`r7_harnessd_extension.ts` / the dart-workspace extension) was not
  updated to the one-read-dialect graduation; its tool names no longer
  match the daemon's mechanical read set.
- **The verb/spec to build**: the extension exposes ONE read tool
  (`harness_meaning_program {ops:[…]}`) and drops/aliases the per-verb
  wrappers; the mechanical-directive classifier's read set is asserted
  against the LIVE registry (a registry-derived test, not a name list) so
  this class cannot silently return.
- **Non-claims**: the daemon's mechanical read path itself is proven
  (34–54 ms rows; the warm tick 24 ms); only the session's tool wrappers
  lag. The doc edits in this session stayed raw edits (this row).

| 2026-09-08 | ADR 0035 §6: TS family landing (ts_materializer repairs: mask buffer, function-body member guard, span-boundary parse; registration of the ts FileClassSpec + binding; test/ts_materializer_test.dart incl. the scanner↔tree-sitter conformance delta) | raw `edit`/`write` on 4 lib files + 2 test files in xsoulspace_agentic_workspace; full suite green (95/0) + analyze 0 new errors before claim | the materializer under repair is DART in `pkgs/*/` — but the work was scanner-debug + fixture-data replication + registration DATA: no single meaning node addresses "fix the mask buffer inside tsScanSymbols" (function-level surgery inside a `final RegExp`-hosting library, cross-cutting the scanner/oracle/splice halves), and the conformance fixtures had to be embedded as test DATA because the workspace may not import the FFI leaf (§8 layering) — a copy, not a meaning move | a `conform_scanner` refactor executable: spec declares the fixture set + the named failure classes; host runs the battery against the scanner AND repairs named classes mechanically (the delta table is already the data contract — it just needs to drive the edit, not only the gate) |

## 2026-09-08 — the (a)/(b) decision analysis ran in bash+python (the harness should have carried it)

- **What bash/python did**: classified every burned step across the wave
  logs (grep/uniq counts of invented queries/focusIds; edit-bounce
  classes) and applied multi-section python replacements to PLAN.md /
  afm_wave_results.md.
- **Why the surface didn't cover it**: (1) the log-classification verb
  does not exist — the wave-log analyzer (mechanically-resolvable vs
  composition-required) should be a benchmark/mechanical directive
  reading run logs through the surface; (2) the session's read tools
  route via the mover (the extension gap above), pushing even doc edits
  to raw paths.
- **The verb/spec to build**: `wave_log_classify` (mechanical directive
  over `benchmark/runs/*.log` → the per-run class-split summary rows);
  the extension read-dialect fix (above) so analysis READS are
  mechanical; doc multi-edits via the md binding's section actions once
  reads work.
- **Non-claims**: the analysis CONCLUSION stands (0% vs 100%); the escape
  is the process debt, not the result.
| 2026-09-08 | cs-family landing (ADR 0035 §6 Tier C v1: cs_materializer + binding + tests + baseline doc) | the whole task ran on raw read/write/bash: `read` over the 1,746-line materializer, `write` for the 9-test suite, regex probes via throwaway `dart run` scripts to pin scanner behavior (the scanner returned zero nodes — `\p{L}` regexes missing `unicode: true` — and block-scoped-namespace declarations were unindexed; both found by hand-probing, not by a surface read), doc appends via `cat >>` | no harness surface covers NEW-format materializer landing: the cs files are not yet editable through a cs binding (chicken-and-egg — the binding lands in this very task), and the harness has no "run a one-off probe script against package lib code" verb for scanner debugging; md/doc appends could have used the md binding only if the task docs were registered meaning nodes in THIS workspace | when the NEXT format family lands (v2), bootstrap it the way ts→cs did: land the binding, then re-point the family's own docs/tests at the surface (self-hosting); a `probe` directive (run a named pure fn over inline source, return rows) would have turned the two scanner-bug probes into surface reads — spec as a harness read dialect extension, never a new loop |

## 2026-09-08 — frontier-resolver session: reads routed through the mover, then closed (the extension-dialect row above, EXECUTED)

- **What happened (A side, measured in-session)**: `harness_locate` ×2 and a
  `harness_edit` probe delegated to the mover (194,114 / 194,122 / 183,302 ms —
  `mover_refusal` ×2, zero moves, verify burned 8,999 ms each) — the session
  could not read the tree mechanically while the debt row above stood.
- **What closed it (B side)**: (1) the extension now exposes ONE read tool
  (`harness_meaning_program {ops:[…]}`; legacy wrappers REMOVED);
  (2) the mechanical-read set is asserted against the LIVE one-truth registry
  (`pkgs/xsoulspace_agentic_host/test/mechanical_read_registry_test.dart` —
  both directions: every recognized read form is served by a registry tool,
  the program op set is derived from the LIVE tool's closed-set halt bounce,
  and the legacy wrapper names are pinned OUT);
  (3) the read wall over the REAL monorepo tree measured **28 ms** (scripted
  probe, `run_dogfood_seam_ab.mjs`);
  (4) one REAL `harness_edit` md insert (the A/B row into
  `results_seam_speed.md`) landed THROUGH the md binding via the scripted
  daemon — byte-precise, consented, oracle-gated (edit wall 41.5 s incl. the
  in-materializer verify; the pure splice is ms-scale).
- **Non-claims**: the on-device wave rows 2–4 re-run (the repair-(a)
  graduation measurement) is a separate, machine-quiet gate; the A/B rows are
  n=1 in-session observations. The 41.5 s edit wall is the verify convention
  (flutter test over the touched package), not the splice.
| 2026-09-08 | ADR 0009 (last_answer) session registry + profiler protocol layer (host: `HarnessSessionRegistry`, `SessionHandle`; profiler: pure-Dart `session_protocol.dart` reader + gates) | whole task ran on raw `read`/`write`/`edit`/`bash` (6 new Dart files + 3 barrel/pubspec integration edits); gates verified via `flutter test`/`flutter analyze` + a plain-VM `dart run` probe | the pi session this task ran in had NO harness surface tools mounted (no harness_scan/harness_edit/harness_verify directives available) — the registry/protocol files are new files in pkgs/*/ Dart packages, which the surface covers in principle, but the session's tool list did not expose them | when surface tools mount, new-file Dart work in pkgs/*/ should route harness_scan → harness_edit → harness_verify as the AGENTS.md law says; the headless gate (protocol answers with no Flutter in the process) is exactly the shape a `verify` directive should carry as a named gate |
