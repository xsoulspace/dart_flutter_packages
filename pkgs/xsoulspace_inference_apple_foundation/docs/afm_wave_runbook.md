# AFM wave gate — runbook (one command, AX + DX)

The P0 re-run of the 2026-09-06 surface-wave rows on the REAL on-device
Apple Foundation Model. Rows 2–4 re-run after the P1
`tool_args_invalid` fix; **the bounce-recovery rate IS the
union-enum graduation measurement** (ADR 0034): recovery → the ONE
edit verb stands; no recovery → the enum splits per class (a measured
surface change). Full context:
[`afm_wave_results.md`](../../xsoulspace_agentic_harness/benchmark/runs/afm_wave_results.md)
§ P0 RE-RUN.

## Prerequisites (once)

1. macOS with **Apple Intelligence enabled** (System Settings → Apple
   Intelligence & Siri). The model is on-device; no API key.
2. Bridge dylib built (only after Swift edits):
   `cd pkgs/xsoulspace_inference_apple_foundation && flutter pub get &&
   sh tool/check_bridge_swift.sh` — 27/27 unit passes = the bridge is
   healthy.
3. Workspace resolution: `flutter pub get` in this package (the
   monorepo workspace needs the Flutter SDK).

## The one command

```sh
cd pkgs/xsoulspace_inference_apple_foundation

just wave-dry        # STEP 1 — sandbox-safe plumbing validation (no model)
just wave            # STEP 2 — all 4 rows, pass@1, on-device AFM
just wave-row row=md # alternative — ONE row (see AX note)
just wave-row row=yaml runs=3   # n>1 for a real pass-rate row
```

Rows: `grammar` (task-grammar pre-pass) · `trusted` (consented
authored-body pack) · `md` (unified replace_section) · `yaml` (unified
replace_value). Every row drives the ONE `edit_symbol` verb
({action, symbolId, body?, anchor?}) — ADR 0034/0035.

## Exit codes & where results land

| code | meaning |
|---|---|
| 0 | all selected rows PASSED |
| 1 | a row FAILED — verdict + failure class are still PUBLISHED (rows publish even on FAIL) |
| 2 | `engine_unavailable` — AFM unreachable; the rows stay UNTESTED, never PASS |

Per-run logs: `pkgs/xsoulspace_agentic_harness/benchmark/runs/`
(`afm_wave_<row>_run<N>.log` + `afm_wave_summary.log` — one JSON line
per row: verdict, decisions, tool_rounds, tokens, wall_ms, moves,
failure_class). `--dry` needs no dylib and exits 0 only when every
jail's plumbing validates against the REAL materializers.

## Recording the run (the discipline)

Append one table to `afm_wave_results.md` (§ P0 RE-RUN pattern): row /
verdict / decisions / tokens / wall / failure class — every number
states backend (`apple_foundation_afm`), tokens source
(`Situation.tokensUsed`), tool surface (the unified verb), and n.

## Reading the verdict (what this run decides)

- **PASS with recovery through bounces** → the union enum graduates;
  the unified surface stands for TS/C# (ADR 0035 §5/§6).
- **FAIL in `tool_args_invalid` loops despite the named bounce** → the
  enum splits per class — a measured ADR surface change, never a
  guess.
- Failure classes are data: classify `decision_dropped` (window) vs
  repeated-identical-moves (framing) vs final-gate misses (PLAN P2
  instrument row).

## AX notes (agents driving this)

- `harness_run` the dry step first: `["dart", "run",
  "bin/afm_wave_gate.dart", "--dry"]` — cheap, no model, sandbox-safe.
- Real rows run MINUTES each and are wall-time-measured: run ONE row
  per call (`--row`), never all four inside one turn budget; run them
  sequentially (concurrent rows skew wall_ms and contend for the
  on-device model).
- Never edit the fixtures/prompts to make a row pass — the row IS the
  measurement. A failed row publishes honestly; that is the contract.
- `--dry` also grep-gates prompt drift: a prompt teaching a dead verb
  (`edit_section`/`edit_key`) or a path arg FAILS dry (ADR 0035 §5).

## DX notes (changing the rows)

- Fixtures and exact-move prompts live in `bin/afm_wave_gate.dart`
  (rows as data: seeder + task + consent plan + dry validator).
- A new row = one `_WaveRow` entry + seeder + task + dry validator.
  The dry validator must call the REAL materializer (LLM-free), and
  the prompt must carry the exact unified move shape.
- Keep `maxGoalAttempts` at 1 for pass@1 rows (the driver default);
  `--attempts` widens the ladder only for recovery measurements.
