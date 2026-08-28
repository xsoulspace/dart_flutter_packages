# Gate run-graded vs baseline — real Apple Foundation Model

> Real-backend measurement of the Gate A/B seams on self-contained "build a
> runnable Dart program" tasks. Backend: `AppleFoundationNativeClient`
> (on-device, macOS arm64), native tool calling (ADR 0013). Run via
> `pkgs/xsoulspace_inference_apple_foundation/bin/gate_run_afm.dart`.
> Both arms get an identical retry prompt (`maxCheckerRetries`-style, mirrors
> `CodingSuiteRunner` verifier-in-the-loop) that says "run `dart run main.dart`,
> read the error, rewrite".

## Verdict

**Both arms FAIL** on a real 2–4k on-device model. The failure is **model
capability, not harness machinery**: the cut model cannot emit syntactically
valid `main.dart` even when handed the exact compile error. This is the true
remaining pi-parity frontier — a 2–4k model cannot hold multi-line Dart syntax
in its projected cut.

## What the run-graded seam changes (the win)

The `run` tool (Gate A) + `runs` checker (behavioral oracle) now let the loop
**execute and observe its own output** — the thing it could never do before:

- run-graded board: `write ×5, run ×2` — models reads the compile error
  (`Error: String starting with ' must end with '.'`) and **iterates** to
  self-correct.
- baseline board (pre-retry-prompt): flails in discovery — writes to missing
  `src/`, `list_dir`/`glob` spirals, no `run`.

The difference is deterministic and already LLM-free-tested
(`test/build_gates_test.dart`, `test/run_tool_test.dart`). The `runs` checker
grades by executing the target (`exit==0`), so a "pass" is now a *working*
program, not a string match.

## Active limits to reach the tic-tac-toe goal
1. **Model can't emit valid Dart in the 2–4k cut** — the gating failure. This
   is the edit-quality gap (P1) made concrete on-device. `runs`/`run` provide
   the oracle; they cannot manufacture syntax the model can't produce.
2. **Discovery still costs**: in one arm the model moved the file into `src/`
   the jail didn't have, then spent calls rediscovering. Locate/grep help but
   don't stop a model that guesses wrong paths.

## What would move the needle next
- **Mechanical syntax-repair or a "give me a one-liner" tool** for the `runs`
  oracle to feed a canonical minimal fix (LLM-free) rather than the raw stderr
  — the model needs a *correct* snippet, not a diagnostic it can't honor.
- **a2a team (Stage C)**: a tiny Planner (decompose) + a tiny Coder (emit one
  cell at a time) + the run tool — so each 2–4k step stays under the syntax
  ceiling by writing tiny, mechanical, already-valid slices (ADR 0009).
- **Projection**: put the *current* `main.dart` + the *latest* compiler error
  adjacent in the cut (projection improvement), not more tokens overall.

## Numbers (honest; excluded for pass-rate at this backend)
Both arms: `build_board` ❌, `build_turn` ❌. Equivalent on this model; the
gate is correctly *observed* (fail-loud), not masked.