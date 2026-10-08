import 'dart:io' show InternetAddress;

import 'package:xsoulspace_inference_local_serve/xsoulspace_inference_local_serve.dart';

import 'mlx_chat_wire.dart';

/// A loopback OpenAI-compatible chat wire server over ANY engine endpoint
/// — the pure-Dart scripted fake, or the native in-process engine. This is
/// the engine-policy seam ADR-0039 proposes: consumers always see the same
/// wire (`GET /health`, `POST /v1/chat/completions`) no matter which
/// engine answers behind it.
base class MlxChatWireServer {
  MlxChatWireServer({
    required this._completeRequest,
    this.model = 'mlx',
    this.apiKey,
    this.address,
    this.port = 0,
  });

  final String model;
  final String? apiKey;
  final InternetAddress? address;
  final int port;

  final Future<MlxChatResult> Function(MlxChatRequest request) _completeRequest;

  late final LoopbackJsonServer _server = LoopbackJsonServer(
    apiKey: apiKey,
    address: address,
    port: port,
    healthPayload: () => <String, Object?>{'status': 'ok', 'model': model},
    route: _route,
  );

  /// The bound base URL (`http://127.0.0.1:<port>`), after [start].
  Uri get url => _server.url;

  Future<void> start() => _server.start();

  Future<void> stop() => _server.stop();

  Future<LoopbackReply?> _route(final LoopbackRequest request) async {
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
    final result = await _completeRequest(
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
      'id': 'chatcmpl-mlx',
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
        'prompt_tokens': result.promptTokens ?? 0,
        'completion_tokens': result.completionTokens ?? 0,
      },
    });
  }
}
