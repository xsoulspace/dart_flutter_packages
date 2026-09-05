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

## Closed gaps (moved to results when landed)

(none yet — this ledger was opened 2026-09-06)

## Non-goals

- **No GitHub/tracker integration.** Tasks enter as plain task sentences +
  the workspace convention (`--check`); the workspace oracle is the gate.
  An external tracker would add a protocol level the composition law
  forbids (no second protocol, ever).
