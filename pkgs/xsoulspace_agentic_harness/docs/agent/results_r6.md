// ignore_for_file: lines_longer_than_80_chars

# R6 results — the workspace-oracle meaning tier (ADR 0022), first gate

Date: 2026-09-02. All numbers scripted (LLM-free), n stated per row. Tokens
source: `Situation.tokensUsed` per decision (honest projection spend).
Re-run probe: `pkgs/xsoulspace_agentic_dart_meaning/tool/r6_probe.dart`.

## The gate (ADR 0022 validation, now MET)

> A scripted actor drives a workspace-graded task end-to-end (fail tests →
> rows → skeleton → model moves → materialize → `dart test` PASS) with zero
> model code tokens and zero host-authored expectations.

`test/workspace_oracle_e2e_test.dart` — greenfield workspace (pubspec +
`test/calc_test.dart` with 2 failing expects, NO lib/ file):

| Column | Value |
|---|---|
| backend | scripted_llm_free |
| n | 1 |
| verdict | PASS (`dart test exit=0`) |
| decisions | 1 |
| tool rounds | 1 |
| moves | `intent_define.define` ×1 — NO write move, ever |
| projection tokens | 7,857 |
| wall | ~10s (incl. `dart pub get` + `dart test` in the jail) |
| expectations source | DERIVED from the suite's own `expect()` calls (2 rows, provenance `test/calc_test.dart:5`/`:8`) |
| model code tokens | 0 (op rows only) |
| host-authored expectations | 0 |

## Comparison rows (same task class: implement `add(a, b)` so a suite passes)

| Arm | decisions | tokens | verdict | law |
|---|---|---|---|---|
| R6 workspace-oracle meaning tier (this) | 1 | 7,857 | PASS | **held** |
| delegation M1 run-graded `write` arm | 11 | 15,725 | PASS | **violated** (model wrote whole files) |
| pre-wired intent tier (bookmark, on-device AFM) | 9–12/run | ~20,517/run | 0/3 pass@3 | held but oracle was host-authored |

The R6 arm is simultaneously faster (1 decision vs 11/9–12), cheaper (~2× vs
the write arm on projection spend), AND the first arm that is both lawful
and general (the oracle is the workspace, not host data).

## What landed

1. **Core vocabulary growth (ADR 0019 §4 mechanism, ADR 0022 §3):** `lt`,
   `gt`, `add`, `sub`, `mul`, `get_item`, `call` — 14 → 21 ops. Each added
   as spec + VM semantics + parity (interpreter ⇄ materialized template).
   `call` is the composition primitive: chains call intents, so intent-first
   growth compounds (ADR 0019 §4 is now mechanically true). Recursion is
   bounded (depth 16 + 1000-step limit → structured error, never a hang).
2. **ETL-in** (`xsoulspace_agentic_dart_meaning/lib/src/test_etl.dart`):
   failing-suite → skeleton. Declared subjects read `lib/**.dart`
   signatures; greenfield subjects take the target file from the suite's
   own `package:` import and types from the suite's literals. Every
   expectation cites its test line. Unresolvable rows ship as honest
   `unresolved` data.
3. **ETL-out** (`dart_materializer.dart`): expression-stack → structured
   statements compiler (linear arithmetic, forward if/else with
   return-terminated or merging branches, `call` → direct function calls).
   Unsupported shapes (state ops, backward jumps) fail as NAMED problems —
   never silently.
4. **The runner** (`workspace_meaning_runner.dart`): derive → model fills
   bounded slots → derived-expectation replay in-loop → HOST materializes
   (zero model tokens) → workspace convention (`dart test`) grades.
   Monotonic attempt budget; `GoalAttemptsExhausted` on exhaustion.

## Honest non-claims

- Scripted backend only: on-device AFM pass@3 through this path is the
  NEXT gate (the 2–4k model now fills slots whose names/arity are given —
  strictly easier than the old free-form chain authoring that went 0/3,
  but it is unmeasured).
- Greenfield param names are honestly inferred (`arg0:int`): suite
  literals carry no names. Named follow-up: derive names from call-site
  context when the suite provides them.
- `dart pub get` in the jail runs host-side (mechanical, zero model
  tokens); on-device jail resolution is untested.
- One task class (two-param arithmetic). The tic-tac-toe shape
  (`winner(board)` via `get_item`/`eq`/branches + `call`) is unit-proven
  per-op but not yet run through the full runner.
- The n=1 row is a GATE, not a benchmark: no pass@k claim is made.
