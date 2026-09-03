// ignore_for_file: lines_longer_than_80_chars

/// N4 escalation rung + M0b declare_check seam — LLM-free scripted proof
/// through the REAL `HarnessAcpBackend` (direct backend calls, in-memory
/// snapshot store). No network, no AFM.
library;

import 'dart:io';

import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_apple_foundation/src/harness_acp_backend.dart';

import 'package:dart_acp_toolkit/dart_acp_toolkit.dart';

class _Scripted implements GenerationHandler {
  _Scripted(this.path, this.content);
  final String path;
  final String content;
  var wrote = false;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final calls = wrote
        ? const <ToolCall>[]
        : [
            ToolCall(
              name: const ToolName('write'),
              arguments: {'path': path, 'content': content},
            ),
          ];
    wrote = true;
    final r = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {'text': wrote ? 'done' : 'writing'},
      rawOutput: wrote ? 'done' : 'writing',
      toolCalls: calls,
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(r);
    return r;
  }
}

void main() {
  late Directory ws;
  late Directory store;
  setUp(() async {
    ws = await Directory.systemTemp.createTemp('escalation');
    store = await Directory.systemTemp.createTemp('escalation_store');
    // A workspace whose check fails until lib/greet.dart is correct. Real
    // delegation fixture: test-based oracle (dart test) — analyze-only would
    // pass trivially before any work (a known convention weakness, see
    // PLAN.md M0b).
    Directory('${ws.path}/lib').createSync();
    Directory('${ws.path}/test').createSync();
    File('${ws.path}/pubspec.yaml').writeAsStringSync(
      'name: g\nenvironment:\n  sdk: ^3.5.0\ndev_dependencies:\n'
      '  test: ^1.25.0\n',
    );
    File('${ws.path}/test/greet_test.dart').writeAsStringSync(
      "import 'package:test/test.dart';\n"
      "import 'package:g/greet.dart';\n"
      'void main() { test(\'greet\', () { expect(greet(\'x\'), \'hello x\'); }); }\n',
    );
    File('${ws.path}/check.dart').writeAsStringSync(
      "import 'dart:io';\nvoid main() {\n  final t = File('lib/greet.dart');\n"
      "  if (!t.existsSync() || !t.readAsStringSync().contains('hello')) {\n"
      '    stderr.writeln(\'greet.dart missing hello\');\n    exit(1);\n  }\n}\n',
    );
  });
  tearDown(() {
    ws.deleteSync(recursive: true);
    store.deleteSync(recursive: true);
  });

  test('escalation rung: budget exhausted → guidance prompt continues', () async {
    // Turn 1: the model writes WRONG content (all 3 attempts fail the gate).
    // Turn 2 (operator guidance): the model writes it right.
    var turn = 0;
    final backend = HarnessAcpBackend(
      backend: 'open_router',
      handlerFactory: (_) {
        turn++;
        return turn == 1
            ? _Scripted('lib/greet.dart', 'WRONG')
            : _Scripted(
                'lib/greet.dart',
                "String greet(String name) => 'hello ' + name;",
              );
      },
    );
    final updates = <String>[];
    void emit(AcpSessionUpdate u) {
      final c = switch (u) {
        AgentMessageChunk(:final content) => content,
        _ => null,
      };
      if (c is AcpTextBlock) updates.add(c.text);
    }

    final sid = await backend.createSession(AcpSessionNewRequest(cwd: ws.path));

    // ---- turn 1: wrong work → budget exhausted → escalation offered ----
    final stop1 = await backend.prompt(
      AcpPromptRequest(
        sessionId: sid,
        prompt: const [
          AcpTextBlock(
            'Implement lib/greet.dart: provide String greet(String name) '
            'returning "hello " + name.',
          ),
        ],
      ),
      emit: emit,
      isCancelled: () => false,
    );
    expect(stop1, AcpStopReason.endTurn);
    expect(updates.join(), contains('escalation'),
        reason: 'a budget-exhausted task must be offered to the operator');

    // ---- turn 2: operator guidance CONTINUES the same task ----
    final stop2 = await backend.prompt(
      AcpPromptRequest(
        sessionId: sid,
        prompt: const [
          AcpTextBlock('guidance: greet must return "hello " + name'),
        ],
      ),
      emit: emit,
      isCancelled: () => false,
    );
    expect(stop2, AcpStopReason.endTurn);
    expect(updates.join(), contains('verdict: PASS'), reason: updates.join());
    expect(File('${ws.path}/lib/greet.dart').existsSync(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
