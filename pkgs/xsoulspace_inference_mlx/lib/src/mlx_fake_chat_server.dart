import 'dart:io' show InternetAddress;

import 'package:xsoulspace_inference_local_serve/xsoulspace_inference_local_serve.dart';

import 'mlx_chat_wire.dart';

/// The scripted generation seam of the pure-Dart chat fake: an engine
/// answers a decoded [MlxChatRequest]. Deterministic engines keep the whole
/// client path testable with no Python runtime and no model weights.
abstract interface class MlxScriptedEngine {
  MlxChatResult answer(final MlxChatRequest request);
}

/// Replays pinned completions in order; an unpinned request falls back to
/// the last pin (or the empty string). Mirrors the scripted-engine shape
/// the laya server uses.
final class ScriptedMlxChatEngine implements MlxScriptedEngine {
  ScriptedMlxChatEngine(final List<String> completions)
    : completions = List<String>.unmodifiable(completions);

  final List<String> completions;
  final List<MlxChatRequest> requests = <MlxChatRequest>[];
  var _cursor = 0;

  /// Clears the cursor so a fresh run replays from the start.
  void reset() => _cursor = 0;

  @override
  MlxChatResult answer(final MlxChatRequest request) {
    requests.add(request);
    final text = completions.isEmpty
        ? ''
        : completions[
            _cursor < completions.length - 1 ? _cursor++ : completions.length - 1];
    return MlxChatResult(
      text: text,
      finishReason: 'stop',
      resolvedModel: request.model,
      promptTokens: request.messages.fold<int>(
        0,
        (total, message) => total + message.content.length ~/ 4,
      ),
      completionTokens: text.length ~/ 4,
    );
  }
}

/// A pure-Dart OpenAI-compatible chat server on the loopback interface.
///
/// Serves `GET /health` (open, `{"status":"ok","model":...}`) and
/// `POST /v1/chat/completions` (optional `Bearer` auth) over the shared
/// [LoopbackJsonServer] skeleton — the same wire `mlx_lm.server` speaks —
/// so clients, prompt builders, and draft lanes run and are tested with no
/// model runtime. This is a wire fake, not a model: the engine is
/// deterministic unless a real server answers instead.
final class FakeMlxChatServer {
  FakeMlxChatServer({
    required MlxScriptedEngine engine,
    this.model = 'fake-mlx',
    this.apiKey,
    this.address,
    this.port = 0,
    // A named parameter cannot spell the private initializing formal.
    // ignore: prefer_initializing_formals
  }) : _engine = engine;

  final String model;
  final String? apiKey;
  final InternetAddress? address;
  final int port;

  final MlxScriptedEngine _engine;

  // A late final field can reference instance members (the route tear-off);
  // a constructor initializer cannot.
  late final LoopbackJsonServer _server = LoopbackJsonServer(
    apiKey: apiKey,
    address: address,
    port: port,
    healthPayload: () => <String, Object?>{
      'status': 'ok',
      'model': model,
    },
    route: _handleChat,
  );

  /// The bound base URL (`http://127.0.0.1:<port>`), after [start].
  Uri get url => _server.url;

  Future<void> start() => _server.start();

  Future<void> stop() => _server.stop();

  Future<LoopbackReply?> _handleChat(final LoopbackRequest request) async {
    if (request.method != 'POST' || request.path != '/v1/chat/completions') {
      return null;
    }
    final body = request.jsonBody!;
    final requestModel = body['model'];
    final messages = body['messages'];
    if (requestModel is! String || messages is! List || messages.isEmpty) {
      return const LoopbackReply(422, <String, Object?>{
        'error': <String, Object?>{'message': 'model and messages required'},
      });
    }
    final decoded = <MlxChatMessage>[];
    for (final raw in messages) {
      if (raw is! Map) {
        return const LoopbackReply(422, <String, Object?>{
          'error': <String, Object?>{'message': 'messages must be objects'},
        });
      }
      decoded.add(
        MlxChatMessage(
          role: '${raw['role'] ?? 'user'}',
          content: '${raw['content'] ?? ''}',
        ),
      );
    }
    final result = _engine.answer(
      MlxChatRequest(
        model: requestModel,
        messages: decoded,
        maxTokens: body['max_tokens'] is int ? body['max_tokens'] as int : null,
        temperature: body['temperature'] is num
            ? (body['temperature'] as num).toDouble()
            : null,
        stop: switch (body['stop']) {
          final List stop => <String>[for (final s in stop) '$s'],
          final String s => <String>[s],
          _ => const <String>[],
        },
      ),
    );
    return LoopbackReply(200, <String, Object?>{
      'id': 'chatcmpl-fake-mlx',
      'model': model,
      'choices': <Object?>[
        <String, Object?>{
          'index': 0,
          'finish_reason': result.finishReason ?? 'stop',
          'message': <String, Object?>{
            'role': 'assistant',
            'content': result.text,
          },
        },
      ],
      'usage': <String, Object?>{
        // Measured only when a real tokenizer runs; the scripted engine's
        // counts are estimates and the meta contract says so upstream.
        'prompt_tokens': result.promptTokens ?? 0,
        'completion_tokens': result.completionTokens ?? 0,
      },
    });
  }
}
