// ignore_for_file: lines_longer_than_80_chars

/// Deterministic LLM test double for harness evaluation (ADR 0003).
///
/// A [ScriptedGenerationHandler] replaces a real model with declarative
/// turns. Each turn is one response to one generation request; fault modes
/// (empty, error, throw, hang) exercise the retry/timeout paths
/// deterministically. Every request is recorded for oracle assertions.
library;

import 'dart:async';

import 'package:ecsly/ecsly.dart';

import '../events.dart';
import '../resources/resources.dart';

/// One scripted turn of the fake model.
class ScriptedTurn {
  const ScriptedTurn({
    this.text = '',
    this.toolCalls = const [],
    this.structuredOutput,
    this.deltas,
    this.mode = ScriptedTurnMode.respond,
  });

  /// Plain text response.
  final String text;

  /// Tool calls dispatched with the response.
  final List<ToolCall> toolCalls;

  /// Structured output payload (overrides text in structuredOutput).
  final Map<String, dynamic>? structuredOutput;

  /// Streaming deltas emitted before the response.
  final List<String>? deltas;

  /// Fault mode — see [ScriptedTurnMode].
  final ScriptedTurnMode mode;
}

/// Fault modes for a [ScriptedTurn].
enum ScriptedTurnMode {
  /// Normal: return the configured response.
  respond,

  /// Return an empty response — triggers the retry path.
  empty,

  /// Return an error response — triggers the retry path.
  error,

  /// Throw synchronously — exercises the handler-crash path.
  throwSync,

  /// Never complete — exercises taskTimeoutSweeperSystem.
  hang,
}

/// A deterministic [GenerationHandler]: consumes [turns] in order and loops
/// on the last turn when exhausted (so retry paths replay the same behavior).
///
/// See `example/lib/headless/03_scripted_faults.dart` for a runnable
/// empty-response → retry demonstration with oracle assertions.
class ScriptedGenerationHandler implements GenerationHandler {
  ScriptedGenerationHandler(List<ScriptedTurn> turns)
    : turns = List.unmodifiable(turns);

  /// The scripted turns, consumed in request order.
  final List<ScriptedTurn> turns;

  int _cursor = 0;

  /// Every request served, in order — for oracle assertions.
  final List<ActorGenerateRequest> requests = [];

  ScriptedTurn get _next {
    if (_cursor < turns.length) return turns[_cursor++];
    return turns.isEmpty ? const ScriptedTurn() : turns.last;
  }

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    requests.add(request);
    final turn = _next;

    for (final delta in turn.deltas ?? const <String>[]) {
      world.events.writer<ActorGenerateStreamEvent>().send(
        ActorGenerateStreamEvent(
          actorEntity: request.actorEntity,
          taskId: request.taskId,
          chunk: delta,
        ),
      );
      world.getResource<StreamingTapResource>().publish(
        request.actorEntity,
        delta,
      );
    }

    switch (turn.mode) {
      case ScriptedTurnMode.respond:
        final response = ActorGenerateResponse(
          actorEntity: request.actorEntity,
          structuredOutput: turn.structuredOutput ?? {'text': turn.text},
          rawOutput: turn.text,
          toolCalls: turn.toolCalls,
          taskId: request.taskId,
        );
        world.events.writer<ActorGenerateResponse>().send(response);
        return response;
      case ScriptedTurnMode.empty:
        final response = ActorGenerateResponse(
          actorEntity: request.actorEntity,
          structuredOutput: const {},
          rawOutput: '',
          taskId: request.taskId,
        );
        world.events.writer<ActorGenerateResponse>().send(response);
        return response;
      case ScriptedTurnMode.error:
        final response = ActorGenerateResponse(
          actorEntity: request.actorEntity,
          structuredOutput: const {},
          rawOutput: '',
          error: 'scripted backend error',
          taskId: request.taskId,
        );
        world.events.writer<ActorGenerateResponse>().send(response);
        return response;
      case ScriptedTurnMode.throwSync:
        throw StateError('scripted handler crash');
      case ScriptedTurnMode.hang:
        return Completer<ActorGenerateResponse>().future;
    }
  }
}
