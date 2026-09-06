// ignore_for_file: lines_longer_than_80_chars

/// ADR 0027 amendment — MECHANICAL RUNS gate: a directive-only
/// `harness_run {…}` prompt executes through the allowlisted run tool —
/// per-file scopes pass (e.g. `dart test test/foo_test.dart`), non-
/// convention commands bounce as named data BEFORE spawning, and mixed
/// prompts never take the path. Zero mover, zero grade.
library;

import 'dart:async';
import 'dart:io';

import 'package:dart_acp_toolkit/dart_acp_toolkit.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_agentic_host/xsoulspace_agentic_host.dart';

void main() {
  late Directory ws;

  setUp(() async {
    ws = await Directory.systemTemp.createTemp('mech_run_');
    // A bare script: `dart run tool/ok.dart` prints ok — no pubspec needed.
    File('${ws.path}/tool/ok.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync("void main() { print('ok-mech-run'); }\n");
  });
  tearDown(() {
    try {
      ws.deleteSync(recursive: true);
    } on Object {
      // best effort
    }
  });

  Future<(AcpStopReason, String)> delegate(String text) async {
    final backend = HarnessAcpBackend(meaningProfile: true, remoteMover: true);
    final sid = await backend.createSession(
      AcpSessionNewRequest(cwd: ws.path),
    );
    final updates = StringBuffer();
    final stop = await backend.prompt(
      AcpPromptRequest(sessionId: sid, prompt: [AcpTextBlock(text)]),
      isCancelled: () => false,
      emit: (u) {
        if (u is AgentMessageChunk) {
          updates.write(
            u.content is AcpTextBlock ? (u.content as AcpTextBlock).text : '',
          );
        }
      },
    );
    return (stop, updates.toString());
  }

  test('classifier: pure run payload → mechanical; mixed → never', () {
    expect(
      isMechanicalRunDirective(
        'harness_run {"command": ["dart", "test", "test/a_test.dart"]}',
      ),
      isTrue,
    );
    expect(
      isMechanicalRunDirective(
        'harness_run {"command": ["dart", "test"]} and then fix failures',
      ),
      isFalse,
      reason: 'leftover prose = a task',
    );
    expect(
      isMechanicalRunDirective(
        'harness_edit {"action": "replace_member_body"} '
        'harness_run {"command": ["dart", "test"]}',
      ),
      isFalse,
    );
  });

  test('allowlisted command runs mechanically; output streams back', () async {
    final (stop, updates) = await delegate(
      'harness_run {"command": ["dart", "run", "tool/ok.dart"]}',
    );
    expect(stop, AcpStopReason.endTurn);
    expect(updates, contains('ok-mech-run'), reason: updates);
    expect(updates, contains('[run path] mechanical'), reason: updates);
  });

  test('non-allowlisted command bounces as named data BEFORE spawning',
      () async {
    final (stop, updates) = await delegate(
      'harness_run {"command": ["rm", "-rf", "/"]}',
    );
    expect(stop, AcpStopReason.endTurn, reason: 'the bounce IS the answer');
    expect(updates, contains('command_not_allowed'), reason: updates);
    expect(
      updates,
      contains('[run path] mechanical'),
      reason: 'the refusal rides the MECHANICAL path — no task, no grade',
    );
  });
}
