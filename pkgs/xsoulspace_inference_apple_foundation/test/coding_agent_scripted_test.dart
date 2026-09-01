// ignore_for_file: lines_longer_than_80_chars

/// B3/B7/B8 — the coding-agent runner, LLM-free: the scripted suite handler
/// through the SAME driver (same surface, verifier, budgets) that the AFM
/// driver uses. This is the CI proof; on-device claims are separate (K
/// discipline) and live in `benchmark/runs/coding_agent_afm_*.log`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:xsoulspace_agentic_harness/benchmark_api.dart'
    show CheckerSpec, FixtureFile, ScriptedSuiteHandler;
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart'
    show CapturedWrite, WriteGateMode;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_inference_apple_foundation/src/coding_agent_runner.dart';

/// A handler that never produces a passing artifact: it emits a `write` of a
/// program that throws — the run-graded oracle exits non-zero EVERY attempt,
/// so the driver must stop at its repair budget, not spin.
class _AlwaysFailingHandler implements GenerationHandler {
  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: const {'text': 'writing a broken program'},
      rawOutput: 'writing a broken program',
      toolCalls: const [
        ToolCall(
          name: ToolName('write'),
          arguments: {'path': 'main.dart', 'content': 'void main() => throw 1;'},
        ),
      ],
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

/// A handler that writes a WORKING main.dart (approved by the gate) and a
/// junk file (rejected by the gate) in the same decision.
class _TwoWritesHandler implements GenerationHandler {
  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: const {'text': 'applying the fix'},
      rawOutput: 'applying the fix',
      toolCalls: const [
        ToolCall(
          name: ToolName('write'),
          arguments: {
            'path': 'main.dart',
            'content': "void main() { print('ok'); }\n",
          },
        ),
        ToolCall(
          name: ToolName('write'),
          arguments: {'path': 'junk.txt', 'content': 'should never land'},
        ),
      ],
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

void main() {
  test('scripted intent_03 passes through the coding-agent driver '
      '(intent-graded verifier + final dart oracle)', () async {
    final jail = await Directory.systemTemp.createTemp('ca_test_intent03_');
    addTearDown(() => jail.delete(recursive: true).catchError((_) {}));
    final r = await runCodingAgentOnce(
      task: codingAgentTasks['intent_03_bookmark_macros']!,
      jail: jail,
      handler: ScriptedSuiteHandler(taskId: 'intent_03_bookmark_macros'),
      backend: 'scripted_llm_free',
    );
    expect(r.passed, isTrue, reason: '${r.failureClass}');
    expect(r.finalGate.single.detail, contains('all 4 calls verified'));
    // The deliverable surface was actually used (not bypassed).
    expect(r.moves.keys, contains('intent_define.define'));
    expect(r.moves.keys, contains('act_with_project.materialize'));
    expect(r.moves.keys, contains('intent_call'));
    // Observability shipped even on pass.
    expect(r.pulseText, isNotEmpty);
    expect(r.recorderDump, isNotEmpty);
  });

  test('scripted bugfix_01 passes the runs-checker + yaml checkers '
      'through the same driver', () async {
    final jail = await Directory.systemTemp.createTemp('ca_test_bugfix01_');
    addTearDown(() => jail.delete(recursive: true).catchError((_) {}));
    final r = await runCodingAgentOnce(
      task: codingAgentTasks['bugfix_01_off_by_one']!,
      jail: jail,
      handler: ScriptedSuiteHandler(taskId: 'bugfix_01_off_by_one'),
      backend: 'scripted_llm_free',
    );
    expect(r.passed, isTrue, reason: '${r.failureClass}');
    expect(
      [for (final c in r.finalGate) c.detail].join(' | '),
      contains('all values present in loop.dart'),
    );
    // The host-authored check ran (the model never writes test code).
    expect(File('${jail.path}/check.dart').existsSync(), isTrue);
  });

  test('bounded repairs: a permanently failing task exhausts '
      'maxGoalAttempts and stamps GoalAttemptsExhausted (no unbounded loop)',
      () async {
    final jail = await Directory.systemTemp.createTemp('ca_test_bound_');
    addTearDown(() => jail.delete(recursive: true).catchError((_) {}));
    final task = CodingAgentTask(
      id: 'free_form',
      prompt: 'make a program',
      checkers: [CheckerSpec(type: 'runs', path: 'main.dart')],
      runCommand: ['dart', 'run', 'main.dart'],
    );
    final sw = Stopwatch()..start();
    final r = await runCodingAgentOnce(
      task: task,
      jail: jail,
      handler: _AlwaysFailingHandler(),
      backend: 'scripted_llm_free',
    );
    sw.stop();
    expect(r.passed, isFalse);
    // Budget: 1 initial + maxGoalAttempts repairs, then stop — fast.
    expect(sw.elapsed, lessThan(const Duration(minutes: 2)));
    expect(formatRunLog(r), contains('goal_unverifiable'));
    expect(r.recorderDump, isNotEmpty);
  });

  test('P3 diff gate end-to-end on a fixture git repo: dryRun→approve — '
      'approved write lands, rejected write never does (LLM-free)',
      () async {
    final jail = await Directory.systemTemp.createTemp('ca_test_gate_');
    addTearDown(() => jail.delete(recursive: true).catchError((_) {}));
    // Make the jail a git repo (a coding agent on a real repo).
    Future<void> git(List<String> args) async {
      final r = await Process.run('git', args, workingDirectory: jail.path);
      if (r.exitCode != 0) fail('git $args: ${r.stderr}');
    }

    await git(['init', '-q', '-b', 'main']);
    await git(['config', 'user.email', 't@example.dev']);
    await git(['config', 'user.name', 't']);

    final task = CodingAgentTask(
      id: 'gate_01',
      prompt: 'make main.dart print ok',
      fixtures: [
        FixtureFile(
          path: 'main.dart',
          content: 'void main() => throw StateError("broken");',
        ),
      ],
      checkers: [CheckerSpec(type: 'runs', path: 'main.dart')],
      runCommand: ['dart', 'run', 'main.dart'],
    );
    final r = await runCodingAgentOnce(
      task: task,
      jail: jail,
      handler: _TwoWritesHandler(),
      backend: 'scripted_llm_free',
      writeGateMode: WriteGateMode.review,
      writeApprover: (CapturedWrite w) async => w.relativePath == 'main.dart',
    );

    // The approved fix landed and the gate went green.
    expect(r.passed, isTrue, reason: '${r.failureClass}');
    expect(File('${jail.path}/main.dart').readAsStringSync(),
        contains("print('ok')"));
    // The rejected write NEVER touched the disk.
    expect(File('${jail.path}/junk.txt').existsSync(), isFalse);
    // The audit ships the diffs + verdicts (K4 evidence). The scripted
    // handler re-fires per decision round, so counts accumulate — the
    // invariants are: every main.dart write approved+applied, every
    // junk.txt write rejected.
    expect(r.writeGateAudit, contains('writes applied:'));
    expect(r.writeGateAudit, contains('rejected:'));
    expect(r.writeGateAudit, contains('--- a/main.dart'));
    expect(r.writeGateAudit, contains('--- /dev/null'));
    expect(r.writeGateAudit, contains('+++ b/junk.txt'));
    expect(r.writeGateAudit, contains('REJECTED'));
    expect(
      RegExp('applied: (\\d+), rejected: (\\d+)', multiLine: true)
          .firstMatch(r.writeGateAudit),
      isNotNull,
    );
    expect(r.writeGateAudit.contains('+should never land'), isTrue,
        reason: 'the rejected diff is in the audit, not on the disk');
  },
  timeout: const Timeout(Duration(minutes: 3)),
  );
}
