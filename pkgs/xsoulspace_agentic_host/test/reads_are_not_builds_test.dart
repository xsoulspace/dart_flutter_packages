// ignore_for_file: lines_longer_as_80_chars

/// ADR 0027 gate: reads are not builds + reasoning beats.
///
/// LLM-free (scripted handlers / mechanical read path) — the surface gate
/// never depends on a mover model.
library;

import 'dart:io';

import 'package:dart_acp_toolkit/dart_acp_toolkit.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_agentic_host/xsoulspace_agentic_host.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

void main() {
  late Directory ws;
  setUp(() async {
    ws = await Directory.systemTemp.createTemp('adr0027_');
    // A minimal bare-file workspace: the convention resolves to
    // `dart run main.dart` (fast — no pub resolve in the grade).
    File('${ws.path}/main.dart').writeAsStringSync(
      'void main() { print("greet: " + greet("x")); }\n'
      'String greet(String name) => "hello \$name";\n',
    );
  });
  tearDown(() async {
    try {
      ws.deleteSync(recursive: true);
    } on Object {
      // best effort
    }
  });

  group('read-directive router (mechanical — zero model, zero grade)', () {
    test('classifier: directive-only → true; prose/mutation → false', () {
      expect(isReadOnlyDirectivePrompt('[scan]'), isTrue);
      expect(isReadOnlyDirectivePrompt('[scan] [zoom meaning]'), isTrue);
      expect(
        isReadOnlyDirectivePrompt(
          'harness_zoom {"focusId":"f_x","zoom":"point"}',
        ),
        isTrue,
      );
      expect(isReadOnlyDirectivePrompt('[scan] also fix the bug'), isFalse);
      expect(isReadOnlyDirectivePrompt('[scan] harness_edit {}'), isFalse);
      expect(isReadOnlyDirectivePrompt('[verify]'), isFalse);
      expect(isReadOnlyDirectivePrompt('fix the loop bug'), isFalse);
    });

    test(
      'read directives execute mechanically: no task, no verdict, no grade',
      () async {
        final backend = HarnessAcpBackend(backend: 'open_router');
        final sid = await backend.createSession(
          AcpSessionNewRequest(cwd: ws.path),
        );
        final updates = <String>[];
        final sw = Stopwatch()..start();
        final stop = await backend.prompt(
          AcpPromptRequest(
            sessionId: sid,
            prompt: const [
              AcpTextBlock('[scan] [zoom main] [zoom main.dart]'),
            ],
          ),
          emit: (u) => updates.add(
            u is AgentMessageChunk ? (u.content as AcpTextBlock).text : '',
          ),
          isCancelled: () => false,
        );
        sw.stop();
        final out = updates.join();
        expect(stop, AcpStopReason.endTurn);
        expect(out, contains('[repo_etl]'));
        expect(out, contains('[meaning_zoom]'));
        expect(out, contains('[read path] mechanical — no task, no grade'));
        expect(out, isNot(contains('verdict:')), reason: 'reads are not builds');
        // Honest wall budget: the OLD path paid ~68s (dart test cold
        // compile); the mechanical path must stay two orders below.
        // ignore: avoid_print
        print('MEASURED read-path wall: ${sw.elapsedMilliseconds} ms');
        expect(
          sw.elapsed,
          lessThan(const Duration(seconds: 30)),
          reason: 'read path must not compile/grade (ADR 0027)',
        );
        await backend.disposeSession(sid);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('[read-only]-marked delegation: actor runs, gate stamped '
        'not-applicable, no test compile', () async {
      var handlerCalls = 0;
      final backend = HarnessAcpBackend(
        backend: 'open_router',
        meaningProfile: true,
        handlerFactory: (_) {
          handlerCalls++;
          return _Scripted();
        },
      );
      final sid = await backend.createSession(
        AcpSessionNewRequest(cwd: ws.path),
      );
      final updates = <String>[];
      final stop = await backend.prompt(
        AcpPromptRequest(
          sessionId: sid,
          prompt: const [
            AcpTextBlock(
              '[read-only] look at the greet function and report its shape',
            ),
          ],
        ),
        emit: (u) => updates.add(
          u is AgentMessageChunk ? (u.content as AcpTextBlock).text : '',
        ),
        isCancelled: () => false,
      );
      final out = updates.join();
      expect(stop, AcpStopReason.endTurn);
      expect(handlerCalls, 1, reason: 'the real (scripted) actor runs');
      expect(out, contains('read_only_not_applicable'));
      expect(out, contains('verdict: PASS'));
      await backend.disposeSession(sid);
    });
  });

  group('reasoning beats (ADR 0027 §3)', () {
    test('thinking is captured (chars in verdict) and reused on escalation',
        () async {
      final backend = HarnessAcpBackend(
        backend: 'open_router',
        meaningProfile: true,
        remoteMover: true,
      );
      final mover = _ThinkingMover(turns: 2);
      backend.attachMoveProposer(mover.respond);
      final sid = await backend.createSession(
        AcpSessionNewRequest(cwd: ws.path),
      );
      final updates = <String>[];
      await backend.prompt(
        AcpPromptRequest(
          sessionId: sid,
          prompt: const [AcpTextBlock('[scan] h_edit placeholder')],
        ),
        emit: (u) => updates.add(
          u is AgentMessageChunk ? (u.content as AcpTextBlock).text : '',
        ),
        isCancelled: () => false,
      );
      final out = updates.join();
      expect(
        out,
        contains('reasoning '),
        reason: 'the ledger line carries the reasoning column',
      );
      expect(mover.sawReasoningHint, isTrue,
          reason: 'proposals carry the reasoning class');
      await backend.disposeSession(sid);
    });

    test('empty move → mover_refusal (named bounce, never silent)', () async {
      final backend = HarnessAcpBackend(
        backend: 'open_router',
        meaningProfile: true,
        remoteMover: true,
      );
      final mover = _ThinkingMover(turns: 0);
      backend.attachMoveProposer(mover.respond);
      final sid = await backend.createSession(
        AcpSessionNewRequest(cwd: ws.path),
      );
      final updates = <String>[];
      await backend.prompt(
        AcpPromptRequest(
          sessionId: sid,
          prompt: const [AcpTextBlock('[scan] harness_edit {}')],
        ),
        emit: (u) => updates.add(
          u is AgentMessageChunk ? (u.content as AcpTextBlock).text : '',
        ),
        isCancelled: () => false,
      );
      expect(
        updates.join(),
        contains('mover_refusal'),
        reason: 'refusal-on-task-text is a named failure class (ADR 0027)',
      );
      await backend.disposeSession(sid);
    });
  });
}

/// Emits one zoom call then goes quiet (the loop closes; the turn ends).
class _Scripted implements GenerationHandler {
  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: const {'text': 'read'},
      rawOutput: 'read',
      toolCalls: [
        const ToolCall(
          name: ToolName('repo_etl'),
          arguments: {'action': 'scan'},
        ),
      ],
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

/// Remote-mover stand-in: answers with thinking text; [turns] = how many
/// decisions carry tool calls before going empty (0 = refusal on move 1).
class _ThinkingMover {
  _ThinkingMover({required this.turns});
  final int turns;
  var answered = 0;
  var sawReasoningHint = false;

  Future<AcpMoveResponse> respond(AcpMoveProposal proposal) async {
    if (proposal.reasoning.isEmpty || proposal.reasoning == 'high') {
      sawReasoningHint = true;
    }
    answered++;
    if (answered > turns) {
      return const AcpMoveResponse(text: '', thinking: 'refusing this task');
    }
    return AcpMoveResponse(
      toolCalls: [
        AcpMoveToolCall(name: 'repo_etl', arguments: {'action': 'scan'}),
      ],
      text: 'scanning',
      thinking:
          'Constraint: the gate grades via the workspace convention. '
          'Rejected: writing tests directly (the oracle must derive them).',
    );
  }
}
