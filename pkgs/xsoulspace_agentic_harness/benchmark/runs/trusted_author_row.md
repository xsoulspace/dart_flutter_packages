# P1 trusted-author tier — the self-hosting row (2026-09-06)

The FIRST real harness fix landed through the authored-body pack executable
kind (`EditExecutableKind.authoredBody`). n=1, LLM-free, real workspace
(`pkgs/xsoulspace_agentic_harness`), real oracle.

## The fix

`splitCheckCommand` (lib/src/tooling/workspace_conventions.dart) was
whitespace-only; a quoted `--check` word (e.g. a test path with a space)
split wrong. The fix needs a character loop — INEXPRESSIBLE in the closed
op vocabulary (loops are hard-cut, pipeline_coding.md) — so the trusted-
author tier is the ONLY route. That is the tier's reason to exist, proven.

## Row (gate: span_edit gate extension + this run; every number's source stated)

| step | value | source |
|---|---|---|
| repo_etl scan | 845 ms | driver wall |
| pack entry | `dart/quote_aware_check_split`, kind `authored_body` | `.dart_tool/harnessd/edit_pack.json` (round-trip through `CapturedEditExecutable.fromJson`) |
| pack-write consent | 1 call; unified diff rendering asserted (`--- a/pack:…`, `+++ b/pack:…`, `+<body>`) | driver callback (in a real session: the human / consent plan; the diff below ships for review) |
| model move | `apply_executable {executableId, symbolId}` ONLY — zero authored tokens | driver |
| apply wall | 71.4 s (of which the workspace convention `flutter test` = 34.2 s; scoped `dart analyze` = 167 ms) | `SpanEditOutcome.analyzeMs/checkMs` |
| scoped analyze exit | 0 | outcome |
| workspace convention exit | 0 (full harness suite) | outcome |
| auto-revert | ARMED (baseline clean), patches KEPT | outcome |
| regression test | `workspace_conventions_test.dart` quote-awareness (5 asserts) — suite 413 passed / 0 failed vs baseline 412/0 | `test_baseline_check` |

## The consented diff (for the human's post-hoc review — git revert is the veto)

```diff
--- a/pkgs/xsoulspace_agentic_harness/lib/src/tooling/workspace_conventions.dart
+++ b/pkgs/xsoulspace_agentic_harness/lib/src/tooling/workspace_conventions.dart
-List<String> splitCheckCommand(String raw) =>
-    raw.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
+List<String> splitCheckCommand(String raw) {
+  final out = <String>[];
+  final word = StringBuffer();
+  var inWord = false;
+  String? quote;
+  for (var i = 0; i < raw.length; i++) { … quote grouping; adjacent
+    segments concatenate; whitespace splits; unterminated quote stays
+    literal (honest data, never a guess) … }
+  return out;
+}
```

(Full body: `git show` on this file, or the pack entry itself.)

## Found + fixed while landing the row (dogfood working as intended)

1. **Expression-bodied members were unreachable** — `_memberSite` compared
   `text[cursor] == '=>'` while cursor rests on `=`, so every `=>` member
   bounced "unexpected token". Fixed with `startsWith('=>', cursor)`;
   `=> <expr>;` members now re-materialize into brace form (signature
   byte-for-byte, `=>` span replaced by the braced body — statements are
   the common currency). Gate: all 23 span/pack/capture/retire/materializer
   tests re-run green.
2. **Daemon wiring gap (open, named)**: `editSymbolTool` in
   `coding_agent_runner.dart` does not wire `packConsent` — the ACP
   permission round-trip is async while pack registration is sync. Until
   wired, an authored pack entry in the daemon path skips at load
   (deny-by-default holds structurally). Route: consent-plan answer
   (`planAllows`-style sync path) or async registration.

## Non-claims

- n=1 row — not a pass-rate claim; the span_edit gate (4 LLM-free tests)
  carries the behavioral coverage.
- The consent callback in the row is mechanical (session-as-trusted-author);
  no human interactively answered a permission prompt.
