// ignore_for_file: lines_longer_than_80_chars

/// Gate test — the wave-log classifier (PLAN P2: "Wave-log classifier as
/// a repeatable analyzer"; the decision instrument for the (a)/(b)
/// boundary, `benchmark/runs/afm_wave_results.md` § DECIDED).
///
/// Pure-function test: deterministic parsing assertions only — no world,
/// no idle expectation. Every number asserted below comes from parsing,
/// never guessed, and the (a)/(b) boundary is asserted as DATA
/// (`kWaveLogClasses`), never as code logic.
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

/// Synthetic wave log covering the measured failure surface: an
/// unknown-focusId read bounce, a slot_scoping edit bounce, a
/// command_not_allowed run bounce, a named program bounce, a
/// step-level verify miss, a clean ok result, a final-gate miss, a
/// decision_dropped/window beat, a backend_failed loop beat, an
/// unparseable ok:false beat, and a clean PASS run. Modeled
/// line-for-line on the real `benchmark/runs/afm_wave_*_run1.log` format.
const _syntheticLog = '''
coding_agent run — task: wave_synthetic_a
  backend: apple_foundation_afm
  verdict: FAIL
  overhead tokens (system+schemas): 1473
  decisions: 4
  tool rounds (thread beats): 5
  moves: {repo_etl.scan: 2, meaning_program: 2, edit_symbol: 1}
  projection tokens (honest spend, Situation.tokensUsed): 9000
  meaning nodes: 20, edges: 20
  wall clock: 1000 ms
  final gate (outer oracle, once): FAIL
    check: dart test exit=1:
    check: missing from config.yaml: [max_attempts: 5]
  failure class: final gate: dart test exit=1: | missing from config.yaml: [max_attempts: 5]
--- harness pulse (J1.5.3) ---
tick 5 | decisions 0 | in-flight 0 | pending results 0
— agent-a  [idle]  rounds 5/12 (Σ5)  attempts 1/3 EXHAUSTED
    last: repo_etl:{"action":"scan"} → ok
--- flight recorder ---
tick 100: decisions=0 inFlight=0 pending=0 actors=agent-a:5r/1a
--- tool results (truncated per beat) ---
repo_etl: {"ok":true,"files":4,"dirs":2,"dart_files":1,"symbols":1,"edges":3,"capabilities":0,"vcs":{"status":"not_a_repo","nodes":0}}
meaning_program: {"ok":false,"program_halt":{"index":1,"op":"read","error":"unknown focusId: main.dart","hint":"fix op 1 and resend the program — the next decision sees this verdict and the results-so-far"},"ops_run":1,"results":[{"locate":{"ok":true,"query":"main
edit_symbol: {"ok":false,"error":"slots are ACTION-SCOPED: a dart move does not take anchor, body","bounce":true,"failureClass":"slot_scoping","repair":"dart moves NEVER take raw code: compose opChain over the closed vocabulary (the host compiles it) or
run: {"ok":false,"code":"command_not_allowed","hint":"this surface runs only the workspace convention commands (e.g. dart analyze / dart test / dart run <file>) — file mutation goes through the edit verbs","command":["dart","main.dart"]}
edit_symbol: {"ok":false,"bounce":true,"error":"inBounds returns bool — the chain must end at a return op","repair":"append {label: return} after pushing the result value","fence":"integration"}
goal_verify: {ok: false, command: [dart, test], verify_wall_ms: 4132, detail: run failed exit=1: }
coding_agent run — task: wave_synthetic_b
  backend: apple_foundation_afm
  verdict: FAIL
  overhead tokens (system+schemas): 2268
  decisions: 2
  tool rounds (thread beats): 1
  moves: {repo_etl.scan: 1}
  projection tokens (honest spend, Situation.tokensUsed): 4000
  meaning nodes: 20, edges: 20
  wall clock: 500 ms
  final gate (outer oracle, once): FAIL
    check: dart test exit=1:
  failure class: final gate: dart test exit=1:
--- harness pulse (J1.5.3) ---
tick 2 | decisions 0 | in-flight 0 | pending results 0
⚠ actor agent-b: decision_dropped — context_window_exceeded (cut 36 < floor 600)
--- flight recorder ---
tick 50: decisions=0 inFlight=0 pending=0 actors=agent-b:1r/1a
    agent-b ← : "Error: backend_failed. Retry with tighter context."
--- tool results (truncated per beat) ---
repo_etl: {"ok":true,"files":4}
widget_bean: {"ok":false,"weird":"completely unknown shape","extra":[1,2,3]}
coding_agent run — task: wave_synthetic_c
  backend: apple_foundation_afm
  verdict: PASS
  overhead tokens (system+schemas): 1473
  decisions: 1
  tool rounds (thread beats): 1
  moves: {edit_symbol.apply_executable: 1}
  projection tokens (honest spend, Situation.tokensUsed): 2024
  meaning nodes: 20, edges: 20
  wall clock: 24500 ms
  final gate (outer oracle, once): PASS
    check: dart analyze exit=0
    check: dart test exit=0
--- harness pulse (J1.5.3) ---
tick 1 | decisions 0 | in-flight 0 | pending results 0
— agent-c  [idle]  rounds 1/12 (Σ1)  attempts 1/1
    last: edit_symbol:{"executableId":"use"} → ok
--- flight recorder ---
tick 10: decisions=0 inFlight=0 pending=0 actors=agent-c:1r/1a
--- tool results (truncated per beat) ---
repo_etl: {"ok":true,"files":4,"dirs":2,"dart_files":1,"symbols":1,"edges":3,"capabilities":0,"vcs":{"status":"not_a_repo","nodes":0}}
''';

void main() {
  test('synthetic log: per-run split numbers are exact', () {
    final report = classifyWaveLog(_syntheticLog);
    expect(report.runs, hasLength(3));

    // Run A: 4 named tool bounces + 1 verify miss + 1 final-gate miss.
    final a = report.runs[0];
    expect(a.task, 'wave_synthetic_a');
    expect(a.verdict, 'FAIL');
    expect(a.gateFailed, isTrue);
    expect(a.burnedSteps, 6);
    expect(a.classes, {
      'unknown_id': 1,
      'slot_scoping': 1,
      'command_not_allowed': 1,
      'program_bounce': 1,
      'verify_fail': 1,
      'final_gate_miss': 1,
    });
    expect(a.mechanicallyResolvable, 6);
    expect(a.compositionRequired, 0);
    // 5-way tie → first in table order (the boundary order is data).
    expect(a.failureClass, 'unknown_id');

    // Run B: gate miss + window beats + one unparseable failure beat.
    final b = report.runs[1];
    expect(b.task, 'wave_synthetic_b');
    expect(b.burnedSteps, 4);
    expect(b.classes, {
      'final_gate_miss': 1,
      'decision_dropped': 1,
      'backend_failed': 1,
      'unparseable': 1,
    });
    expect(b.mechanicallyResolvable, 3);
    expect(b.compositionRequired, 1); // the unparseable beat
    expect(b.failureClass, 'decision_dropped'); // tie → table order

    // Run C: the clean row — nothing burned.
    final c = report.runs[2];
    expect(c.task, 'wave_synthetic_c');
    expect(c.verdict, 'PASS');
    expect(c.gateFailed, isFalse);
    expect(c.burnedSteps, 0);
    expect(c.classes, isEmpty);
    expect(c.mechanicallyResolvable, 0);
    expect(c.compositionRequired, 0);
    expect(c.failureClass, 'clean');

    // Top-level split.
    expect(report.burnedSteps, 10);
    expect(report.mechanicallyResolvable, 9);
    expect(report.compositionRequired, 1);
    expect(report.classes, {
      'unknown_id': 1,
      'slot_scoping': 1,
      'command_not_allowed': 1,
      'program_bounce': 1,
      'verify_fail': 1,
      'final_gate_miss': 2,
      'decision_dropped': 1,
      'backend_failed': 1,
      'unparseable': 1,
    });
  });

  test('summary rows carry the class split (driver contract)', () {
    final report = classifyWaveLog(_syntheticLog);
    final summary = report.toSummary();
    expect(summary['burned_steps'], 10);
    expect(summary['mechanically_resolvable'], 9);
    expect(summary['composition_required'], 1);
    expect(summary['classes'], isA<Map<String, int>>());
    final runSummary = report.runs[1].toSummary();
    expect(runSummary['burned_steps'], 4);
    expect(runSummary['composition_required'], 1);
    expect(runSummary['failure_class'], 'decision_dropped');
  });

  test('the (a)/(b) boundary is a data edit, not code logic', () {
    // The DECIDED measurement: every NAMED class is mechanically
    // resolvable today — composition_required only for unnamed beats.
    for (final entry in kWaveLogClasses.entries) {
      final expected = entry.key != 'unparseable';
      expect(
        entry.value.mechanicallyResolvable,
        expected,
        reason: 'class "${entry.key}" must keep its (a)/(b) data edge',
      );
    }
    // Flipping the boundary requires editing the table, not the parser:
    // composition_required is derived mechanically_resolvable vs burned.
    final report = classifyWaveLog(_syntheticLog);
    expect(
      report.compositionRequired,
      report.burnedSteps - report.mechanicallyResolvable,
    );
  });

  test('real committed excerpt: yaml run split matches the published '
      'early-stop class', () {
    final fixture = File('test/fixtures/wave_log_fixture.log');
    expect(fixture.existsSync(), isTrue);
    final report = classifyWaveLog(fixture.readAsStringSync());
    expect(report.runs, hasLength(1));

    final run = report.runs.single;
    // Published (afm_wave_results.md, P1-FIX RE-RUN, yaml row): 2 tool
    // rounds, near-immediate give-up — the EARLY-STOP class.
    expect(run.task, 'wave_yaml_keypath');
    expect(run.gateFailed, isTrue);
    expect(run.burnedSteps, 1); // the final-gate miss, nothing else
    expect(run.classes, {'final_gate_miss': 1});
    expect(run.mechanicallyResolvable, 1);
    expect(run.compositionRequired, 0);
    expect(run.failureClass, 'early_stop');
    expect(report.compositionRequired, 0);
  });

  test('a log with no run blocks classifies to an empty report', () {
    final report = classifyWaveLog('no wave runs here\njust noise\n');
    expect(report.runs, isEmpty);
    expect(report.burnedSteps, 0);
    expect(report.classes, isEmpty);
  });
}
