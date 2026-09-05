// ignore_for_file: lines_longer_than_80_chars

/// R7c GATE — the daemon holds the world (ADR 0023 §2). LLM-free scripted
/// proof through the REAL `HarnessAcpBackend`:
///
/// 1. per-workspace persistence: two `session/new` calls for the same cwd
///    continue ONE session; a NEW backend instance (daemon restart) with an
///    existing snapshot store RESTORES the world (`loadSession: true` — the
///    capability flag no longer lies);
/// 2. `requestPermission` is DENY-BY-DEFAULT (no approver wired → reject;
///    an attached requester is routed through);
/// 3. `cancelSession` aborts generation (the telemetry path throws and the
///    prompt turn ends `cancelled` — never a no-op);
/// 4. escalation widening is hard-capped (`escalationAllowance`);
/// 5. tool-call ids streamed over ACP are UNIQUE PER CALL (the old
///    name-as-id bug collapsed distinct calls in clients).
library;

import 'dart:async';
import 'dart:io';

import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_agentic_host/xsoulspace_agentic_host.dart';

import 'package:dart_acp_toolkit/dart_acp_toolkit.dart';

class _Scripted implements GenerationHandler {
  _Scripted(this.path, this.content);
  final String path;
  final String content;
  var wrote = false;
  final Completer<void> gate = Completer<void>();

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    if (!gate.isCompleted) {
      // Hold the turn open so the test can cancel mid-generation.
      await gate.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () {},
      );
    }
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

  setUp(() async {
    ws = await Directory.systemTemp.createTemp('r7c_daemon');
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
  });
  tearDown(() {
    try {
      ws.deleteSync(recursive: true);
    } on Object {
      // best effort
    }
  });

  test(
    'escalation allowance: monotonic widening with a hard ceiling',
    () {
      expect(escalationAllowance(0), 3);
      expect(escalationAllowance(1), 4);
      expect(escalationAllowance(6), 9);
      expect(escalationAllowance(50), 9, reason: 'never unbounded');
      expect(maxEscalationCeiling, 9);
    },
  );

  test(
    'requestPermission is DENY-BY-DEFAULT and routes to the wired requester',
    () async {
      final backend = HarnessAcpBackend(
        backend: 'open_router',
        handlerFactory: (_) => _Scripted('lib/greet.dart', 'x'),
      );
      final outcome = await backend.requestPermission(
        const AcpPermissionRequest(
          sessionId: 'sess_1',
          toolCallId: 't1',
          title: 'write lib/greet.dart',
          kind: 'edit',
        ),
      );
      expect(
        outcome,
        AcpPermissionOutcome.reject,
        reason: 'no approver wired → deny; never an unconditional allow',
      );
      // With a requester attached, the decision routes through it.
      AcpPermissionRequest? seen;
      backend.attachPermissionRequester((request) async {
        seen = request;
        return AcpPermissionOutcome.allow;
      });
      final outcome2 = await backend.requestPermission(
        const AcpPermissionRequest(
          sessionId: 'sess_1',
          toolCallId: 't2',
          title: 'write lib/greet.dart',
          kind: 'edit',
        ),
      );
      expect(outcome2, AcpPermissionOutcome.allow);
      expect(seen, isNotNull);
    },
  );

  test(
    'loadSession: a new backend restores the world from the per-workspace '
    'snapshot store; sessions are keyed per workspace',
    () async {
      final first = HarnessAcpBackend(
        backend: 'open_router',
        handlerFactory: (_) => _Scripted(
          'lib/greet.dart',
          "String greet(String name) => 'hello ' + name;",
        ),
      );
      final sid1 = await first.createSession(AcpSessionNewRequest(cwd: ws.path));
      // Per-workspace keying: a second session for the SAME cwd continues.
      final sid1b = await first.createSession(AcpSessionNewRequest(cwd: ws.path));
      expect(sid1b, sid1);
      expect(
        first.agentCapabilities['loadSession'],
        isTrue,
        reason: 'resume is real (R7c) — the capability flag must not lie',
      );
      final updates = <String>[];
      final stop = await first.prompt(
        AcpPromptRequest(
          sessionId: sid1,
          prompt: const [
            AcpTextBlock(
              'Implement lib/greet.dart: String greet(String name) '
              'returning "hello " + name.',
            ),
          ],
        ),
        emit: (u) {
          final c = switch (u) {
            AgentMessageChunk(:final content) => content,
            _ => null,
          };
          if (c is AcpTextBlock) updates.add(c.text);
        },
        isCancelled: () => false,
      );
      expect(stop, AcpStopReason.endTurn, reason: updates.join());
      expect(File('${ws.path}/lib/greet.dart').existsSync(), isTrue);

      // Daemon restart: a NEW backend instance restores from the store.
      final restarted = HarnessAcpBackend(
        backend: 'open_router',
        handlerFactory: (_) => _Scripted('lib/again.dart', '// untouched'),
      );
      final sid2 = await restarted.createSession(AcpSessionNewRequest(cwd: ws.path));
      // Session ids are per-backend; the RESUME is the store restore.
      final storeFile = File(
        '${ws.path}/.dart_tool/harnessd_store/harness-sessions/current.json',
      );
      expect(storeFile.existsSync(), isTrue,
          reason: 'the per-workspace snapshot store must exist');
      final updates2 = <String>[];
      final stop2 = await restarted.prompt(
        AcpPromptRequest(
          sessionId: sid2,
          prompt: const [AcpTextBlock('continue: state what you changed.')],
        ),
        emit: (u) {
          final c = switch (u) {
            AgentMessageChunk(:final content) => content,
            _ => null,
          };
          if (c is AcpTextBlock) updates2.add(c.text);
        },
        isCancelled: () => false,
      );
      expect(stop2, AcpStopReason.endTurn, reason: updates2.join());
      // The restored world carried the goal actor + monotonic budgets
      // (beats/verdicts/budgets — the tree re-derives; there was none).
      expect(
        updates2.join(),
        isNot(contains('no goal-carrying actor')),
        reason: 'the snapshot must restore a resumable world',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'cancelSession aborts generation: the prompt turn ends cancelled',
    () async {
      final scripted = _Scripted('lib/greet.dart', 'WRONG');
      final backend = HarnessAcpBackend(
        backend: 'open_router',
        handlerFactory: (_) => scripted,
      );
      final sid = await backend.createSession(AcpSessionNewRequest(cwd: ws.path));
      final updates = <String>[];
      final promptFuture = backend.prompt(
        AcpPromptRequest(
          sessionId: sid,
          prompt: const [AcpTextBlock('Implement lib/greet.dart.')],
        ),
        emit: (u) {
          final c = switch (u) {
            AgentMessageChunk(:final content) => content,
            _ => null,
          };
          if (c is AcpTextBlock) updates.add(c.text);
        },
        isCancelled: () => false,
      );
      // Let the generation start, then cancel mid-turn.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      backend.cancelSession(sid);
      scripted.gate.complete();
      final stop = await promptFuture.timeout(const Duration(minutes: 2));
      expect(
        stop,
        AcpStopReason.cancelled,
        reason: 'cancellation must be observable — never a no-op',
      );
      expect(updates.join(), contains('cancelled'));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'tool-call updates stream UNIQUE ids per call (no name-as-id collapse)',
    () async {
      var turn = 0;
      final backend = HarnessAcpBackend(
        backend: 'open_router',
        handlerFactory: (_) {
          turn++;
          return _MultiCallHandler(turn);
        },
      );
      final sid = await backend.createSession(AcpSessionNewRequest(cwd: ws.path));
      final toolIds = <String>[];
      await backend.prompt(
        AcpPromptRequest(
          sessionId: sid,
          prompt: const [AcpTextBlock('Do two things.')],
        ),
        emit: (u) {
          if (u is ToolCallUpdate) toolIds.add(u.toolCallId);
        },
        isCancelled: () => false,
      );
      expect(toolIds.length, greaterThanOrEqualTo(2));
      expect(toolIds.toSet().length, toolIds.length,
          reason: 'every call gets its own id — the name-as-id bug is fixed');
      expect(toolIds.every((id) => id.startsWith('t')), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'R7 production #1 — the scripted mover executes the STRUCTURED '
    'harness_edit contract and DROPS malformed payloads (never guesses)',
    () async {
      final backend = HarnessAcpBackend(
        backend: 'open_router',
        meaningProfile: true,
        scripted: true,
      );
      final sid = await backend.createSession(AcpSessionNewRequest(cwd: ws.path));
      final updates = <String>[];
      await backend.prompt(
        AcpPromptRequest(
          sessionId: sid,
          prompt: const [
            AcpTextBlock(
              'harness_edit {broken json — unbalanced '
              'harness_edit {"action":"apply_executable",'
              '"executableId":"rename_symbol","symbolId":"sym_greet",'
              '"executableParams":{"newName":"greeting"}}',
            ),
          ],
        ),
        emit: (u) {
          final c = switch (u) {
            AgentMessageChunk(:final content) => content,
            _ => null,
          };
          if (c is AcpTextBlock) updates.add(c.text);
        },
        isCancelled: () => false,
      );
      final text = updates.join();
      expect(
        text,
        contains('(1 malformed dropped)'),
        reason: 'a malformed payload is classified data — dropped and '
            'reported, never repaired into a guess',
      );
      expect(
        text,
        contains('[edit_symbol]'),
        reason: 'the VALID structured payload reached the REAL edit_symbol '
            'tool and its result (a structured bounce — no tree scanned in '
            'this workspace) streamed back MID-TURN',
      );
      expect(
        text,
        isNot(contains('[rename')),
        reason: 'the prose [rename] directive is gone — the structured '
            'contract replaced it (hard cut)',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// Emits two tool calls in one turn (id-uniqueness proof).
class _MultiCallHandler implements GenerationHandler {
  _MultiCallHandler(this.turn);
  final int turn;
  var called = false;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    // The legacy run-graded arm needs the workspace to pass its gate; the
    // write lands on the first call of the first turn only.
    final calls = called
        ? const <ToolCall>[]
        : [
            ToolCall(
              name: const ToolName('write'),
              arguments: {
                'path': 'lib/greet.dart',
                'content':
                    "String greet(String name) => 'hello ' + name; // t$turn",
              },
            ),
            ToolCall(
              name: const ToolName('list_dir'),
              arguments: {'path': '.'},
            ),
          ];
    called = true;
    final r = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {'text': 'working'},
      rawOutput: 'working',
      toolCalls: calls,
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(r);
    return r;
  }
}
