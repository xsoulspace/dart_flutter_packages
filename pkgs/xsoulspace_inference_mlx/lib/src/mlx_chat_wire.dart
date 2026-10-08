import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// One chat message on the OpenAI-compatible wire.
final class MlxChatMessage {
  const MlxChatMessage({required this.role, required this.content});

  final String role;
  final String content;

  Map<String, Object?> toJson() => <String, Object?>{
    'role': role,
    'content': content,
  };
}

/// One generation request, encoded for `/v1/chat/completions`.
final class MlxChatRequest {
  const MlxChatRequest({
    required this.model,
    required this.messages,
    this.maxTokens,
    this.temperature,
    this.topP,
    this.stop = const <String>[],
    this.templateArgs,
  });

  final String model;
  final List<MlxChatMessage> messages;

  /// Upper bound on generated tokens. Sent only when set — the server's own
  /// default applies otherwise.
  final int? maxTokens;
  final double? temperature;
  final double? topP;
  final List<String> stop;

  /// Chat-template kwargs (e.g. Qwen3's `enable_thinking: false`), passed
  /// through engines that honor them; ignored where unsupported.
  final Map<String, Object?>? templateArgs;

  Map<String, Object?> toJson() => <String, Object?>{
    'model': model,
    'messages': <Object?>[for (final m in messages) m.toJson()],
    'stream': false,
    'max_tokens': ?maxTokens,
    'temperature': ?temperature,
    'top_p': ?topP,
    if (stop.isNotEmpty) 'stop': stop,
    'template_args': ?templateArgs,
  };
}

/// One completed generation: the text plus the measured facts the server
/// reported. Token counts are the server's own usage report (measured),
/// never a client-side estimate.
final class MlxChatResult {
  const MlxChatResult({
    required this.text,
    this.finishReason,
    this.resolvedModel,
    this.promptTokens,
    this.completionTokens,
  });

  final String text;
  final String? finishReason;
  final String? resolvedModel;
  final int? promptTokens;
  final int? completionTokens;
}

/// The chat-generation seam. The HTTP endpoint implements it against a
/// loopback server; tests substitute scripted endpoints.
abstract interface class MlxChatEndpoint {
  Future<MlxChatResult> complete(final MlxChatRequest request);

  Future<void> dispose();
}

/// Content-free transport diagnostic (byte counts, durations, statuses —
/// never prompt or completion text).
typedef MlxWireDiagnostic = void Function(Map<String, Object?> event);

/// OpenAI-compatible `/v1/chat/completions` endpoint on a loopback server.
///
/// Non-streaming v1: one request, one completion. Transient transport
/// failures (5xx, socket errors) retry up to [maxTransientRetries] times
/// after [retryDelay]; validation failures do not retry.
final class HttpMlxChatEndpoint implements MlxChatEndpoint {
  HttpMlxChatEndpoint({
    required final Uri endpoint,
    this.model = 'local',
    this.timeout = const Duration(seconds: 120),
    this.maxTransientRetries = 1,
    this.retryDelay = const Duration(milliseconds: 100),
    this.onDiagnosticEvent,
    final http.Client? httpClient,
  }) : _chatUrl = endpoint.replace(
         path: '${endpoint.path}/v1/chat/completions',
       ),
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  final String model;
  final Duration timeout;
  final int maxTransientRetries;
  final Duration retryDelay;
  final MlxWireDiagnostic? onDiagnosticEvent;

  final Uri _chatUrl;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  @override
  Future<MlxChatResult> complete(final MlxChatRequest request) async {
    final body = utf8.encode(jsonEncode(request.toJson()));
    Object? lastError;
    for (var attempt = 0; attempt <= maxTransientRetries; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(retryDelay);
      }
      final stopwatch = Stopwatch()..start();
      try {
        final response = await _httpClient
            .post(
              _chatUrl,
              headers: const <String, String>{
                'content-type': 'application/json',
                'accept': 'application/json',
              },
              body: body,
            )
            .timeout(timeout);
        stopwatch.stop();
        _emit(<String, Object?>{
          'type': 'mlx.chat.post',
          'url_path': _chatUrl.path,
          'request_bytes': body.length,
          'status': response.statusCode,
          'latency_ms': stopwatch.elapsedMilliseconds,
          'attempt': attempt,
        });
        if (response.statusCode >= 500) {
          lastError = 'server error ${response.statusCode}';
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw MlxChatException(
            'chat request answered ${response.statusCode}',
            retryable: false,
          );
        }
        return _decode(response.body);
      } on MlxChatException {
        rethrow;
      } on TimeoutException {
        lastError = 'timed out after ${timeout.inMilliseconds}ms';
      } on Object catch (error) {
        lastError = error;
      }
    }
    throw MlxChatException('$lastError', retryable: true);
  }

  MlxChatResult _decode(final String responseBody) {
    final Object? decoded;
    try {
      decoded = jsonDecode(responseBody);
    } on FormatException {
      throw MlxChatException('response was not JSON', retryable: false);
    }
    if (decoded is! Map) {
      throw MlxChatException('response was not an object', retryable: false);
    }
    final choices = decoded['choices'];
    String? text;
    String? finishReason;
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final first = (choices.first as Map).cast<String, Object?>();
      final message = first['message'];
      if (message is Map) {
        text = '${message['content'] ?? ''}';
      } else {
        text = '${first['text'] ?? ''}';
      }
      finishReason = first['finish_reason'] == null
          ? null
          : '${first['finish_reason']}';
    }
    if (text == null) {
      throw MlxChatException(
        'response carried no completion',
        retryable: false,
      );
    }
    final usage = decoded['usage'];
    final promptTokens = usage is Map ? usage['prompt_tokens'] : null;
    final completionTokens = usage is Map ? usage['completion_tokens'] : null;
    return MlxChatResult(
      text: text,
      finishReason: finishReason,
      resolvedModel: decoded['model'] == null ? null : '${decoded['model']}',
      promptTokens: promptTokens is int ? promptTokens : null,
      completionTokens: completionTokens is int ? completionTokens : null,
    );
  }

  void _emit(final Map<String, Object?> event) {
    try {
      onDiagnosticEvent?.call(event);
    } on Object {
      // Diagnostics must never change inference behavior.
    }
  }

  @override
  Future<void> dispose() async {
    if (_ownsHttpClient) _httpClient.close();
  }
}

/// A typed chat-wire failure. [retryable] mirrors the transport facts:
/// a 4xx is a contract problem (do not retry unchanged), a socket error
/// or timeout may succeed on a retry.
final class MlxChatException implements Exception {
  MlxChatException(this.message, {required this.retryable});

  final String message;
  final bool retryable;

  @override
  String toString() => 'MlxChatException: $message';
}
