# act_with_project — the "model picks a tiny move over the MEANING" arm (real AFM)

> On-device `AppleFoundationNativeClient`, native tool calling. One tool,
> closed enum sub-actions; AST fully internal to the host materializer.

## The result that settles the argument

Same tiny 2-4k on-device model, same task ("build a runnable 3x3 tic-tac-toe"):

| surface | tool trace | result |
|---|---|---|
| **six separate tools** (`read/write/.../run`) + content/`runs` checkers | model tried to *write code* → emitted syntactically invalid Dart (unterminated string, `package:dart:convert` misimport) | **FAIL** — `dart run main.dart` never compiles |
| **one `act_with_project`** (closed enum) + host materializer | model **only picked moves**: `add`(board,player1,player2) x3, `link` x3, `materialize` x1 — never wrote a code token, never saw an AST | **PASS** — `dart run main.dart` exit=0 |

## Why

The model's whole job collapsed to a **choice over a tiny closed world** (add a
node / link / set a prop / materialize). Materialization (`model-choices → valid
Dart`) is a **pure host program** (the "AST stays internal" / Dart-DTD idea);
`run` / exit-code is the oracle. `Agent = G ∘ F` holds: only the model's tiny
selection is non-deterministic; everything after is deterministic.

This is the load-bearing evidence that the harness was never "smarter model
writes a file" — it is *repurpose-a-small-model by exposing trivial, benchmarkable
moves*, with structure+AST internal. **Tokens per decision drops** (a `choice` is
tiny vs a whole-file `write`).

## Files
- `pkgs/xsoulspace_agentic_harness/lib/src/tooling/structured_editor.dart` — the
  seam: `StructuredDoc` (internal graph), closed `actActionCases`, `actWithProjectTool`.
- `pkgs/xsoulspace_agentic_harness/test/structured_editor_test.dart` — LLM-free tests.
- `bin/act_with_project_afm.dart` — real-AFM driver with the tic-tac-toe
  materializer + run oracle.
- `bin/gate_run_afm.dart` — the six-tool baseline for the SAME build task (FAIL).
