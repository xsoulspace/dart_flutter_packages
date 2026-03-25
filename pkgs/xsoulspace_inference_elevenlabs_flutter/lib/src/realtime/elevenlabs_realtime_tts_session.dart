import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import '../elevenlabs_common.dart';
import '../elevenlabs_config.dart';
import 'elevenlabs_realtime_common.dart';

class ElevenLabsRealtimeTtsEvent {
  const ElevenLabsRealtimeTtsEvent({
    required this.raw,
    this.audioBytes,
    this.isFinal = false,
    this.error,
  });

  final Map<String, dynamic> raw;
  final List<int>? audioBytes;
  final bool isFinal;
  final String? error;
}

class ElevenLabsRealtimeTtsSession {
  ElevenLabsRealtimeTtsSession({
    required final ElevenLabsAuthConfig authConfig,
    final ElevenLabsEndpointConfig? endpointConfig,
    final ElevenLabsWebSocketConnector? webSocketConnector,
  }) : _authConfig = authConfig,
       _endpointConfig = endpointConfig ?? ElevenLabsEndpointConfig(),
       _webSocketConnector =
           webSocketConnector ?? defaultElevenLabsWebSocketConnector;

  final ElevenLabsAuthConfig _authConfig;
  final ElevenLabsEndpointConfig _endpointConfig;
  final ElevenLabsWebSocketConnector _webSocketConnector;

  final StreamController<ElevenLabsRealtimeTtsEvent> _eventsController =
      StreamController<ElevenLabsRealtimeTtsEvent>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  Stream<ElevenLabsRealtimeTtsEvent> get events => _eventsController.stream;

  bool get isConnected => _channel != null;

  Future<InferenceResult<void>> connect({
    required final String voiceId,
    final String? modelId,
    final String outputFormat = 'mp3_44100_128',
  }) async {
    final normalizedVoiceId = voiceId.trim();
    if (normalizedVoiceId.isEmpty) {
      return InferenceResult<void>.fail(
        code: 'request_invalid',
        message: 'Realtime TTS requires non-empty voiceId',
      );
    }

    if (isConnected) {
      return InferenceResult<void>.fail(
        code: 'request_invalid',
        message: 'Realtime TTS session is already connected',
      );
    }

    final authHeadersResult = await resolveRealtimeAuthHeaders(_authConfig);
    if (!authHeadersResult.success || authHeadersResult.data == null) {
      return InferenceResult<void>.fail(
        code: authHeadersResult.error?.code ?? errorCodeAuthFailed,
        message:
            authHeadersResult.error?.message ??
            'Realtime TTS auth resolution failed',
      );
    }

    final query = <String, String>{'output_format': outputFormat};
    final model = modelId?.trim();
    if (model case final String modelValue when modelValue.isNotEmpty) {
      query['model_id'] = modelValue;
    }

    final uri = _endpointConfig.resolveWebSocketPath(
      '/v1/text-to-speech/$normalizedVoiceId/stream-input',
      query: query,
    );

    try {
      _channel = _webSocketConnector(uri, headers: authHeadersResult.data);
      _subscription = _channel!.stream.listen(
        _handleIncomingMessage,
        onError: _handleSocketError,
        onDone: _handleSocketDone,
        cancelOnError: false,
      );
      return InferenceResult<void>.ok(null);
    } catch (error) {
      await _teardown();
      return InferenceResult<void>.fail(
        code: 'engine_unavailable',
        message: 'Failed to connect ElevenLabs realtime TTS websocket',
        details: error.toString(),
      );
    }
  }

  Future<InferenceResult<void>> initialize({
    final Map<String, dynamic>? voiceSettings,
    final Map<String, dynamic>? generationConfig,
  }) => _sendJson(<String, dynamic>{
    'text': ' ',
    if (voiceSettings case final Map<String, dynamic> settings)
      'voice_settings': settings,
    if (generationConfig case final Map<String, dynamic> config)
      'generation_config': config,
  });

  Future<InferenceResult<void>> sendText({
    required final String text,
    final bool tryTriggerGeneration = false,
    final bool flush = false,
    final Map<String, dynamic>? voiceSettings,
    final Map<String, dynamic>? generatorConfig,
  }) {
    final payload = <String, dynamic>{
      'text': text,
      if (tryTriggerGeneration) 'try_trigger_generation': true,
      if (flush) 'flush': true,
      if (voiceSettings case final Map<String, dynamic> settings)
        'voice_settings': settings,
      if (generatorConfig case final Map<String, dynamic> config)
        'generator_config': config,
    };
    return _sendJson(payload);
  }

  Future<InferenceResult<void>> flush() =>
      _sendJson(const <String, dynamic>{'text': '', 'flush': true});

  Future<InferenceResult<void>> closeInput() =>
      _sendJson(const <String, dynamic>{'text': ''});

  Future<void> close() => _teardown();

  Future<void> dispose() async {
    await _teardown();
    await _eventsController.close();
  }

  Future<InferenceResult<void>> _sendJson(
    final Map<String, dynamic> payload,
  ) async {
    final channel = _channel;
    if (channel == null) {
      return InferenceResult<void>.fail(
        code: 'engine_unavailable',
        message: 'Realtime TTS websocket is not connected',
      );
    }

    try {
      channel.sink.add(jsonEncode(payload));
      return InferenceResult<void>.ok(null);
    } catch (error) {
      return InferenceResult<void>.fail(
        code: 'engine_unavailable',
        message: 'Failed to send realtime TTS message',
        details: error.toString(),
      );
    }
  }

  void _handleIncomingMessage(final Object? message) {
    if (message is! String) {
      _eventsController.add(
        ElevenLabsRealtimeTtsEvent(
          raw: const <String, dynamic>{'message_type': 'non_text_message'},
          error: 'Realtime TTS received non-text websocket message',
        ),
      );
      return;
    }

    try {
      final decoded = jsonDecode(message);
      final raw = mapWithStringKeys(decoded);
      if (raw.isEmpty) {
        _eventsController.add(
          ElevenLabsRealtimeTtsEvent(
            raw: const <String, dynamic>{'message_type': 'invalid_json'},
            error: 'Realtime TTS message was not a JSON object',
          ),
        );
        return;
      }

      List<int>? audioBytes;
      final audio = raw['audio'];
      if (audio is String && audio.isNotEmpty) {
        audioBytes = base64Decode(audio);
      }

      final isFinal = raw['isFinal'] == true || raw['is_final'] == true;

      _eventsController.add(
        ElevenLabsRealtimeTtsEvent(
          raw: raw,
          audioBytes: audioBytes,
          isFinal: isFinal,
        ),
      );
    } catch (error) {
      _eventsController.add(
        ElevenLabsRealtimeTtsEvent(
          raw: const <String, dynamic>{'message_type': 'decode_error'},
          error: error.toString(),
        ),
      );
    }
  }

  void _handleSocketError(final Object error, final StackTrace stackTrace) {
    _eventsController.add(
      ElevenLabsRealtimeTtsEvent(
        raw: const <String, dynamic>{'message_type': 'socket_error'},
        error: error.toString(),
      ),
    );
  }

  void _handleSocketDone() {
    _channel = null;
  }

  Future<void> _teardown() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();

    final channel = _channel;
    _channel = null;
    await channel?.sink.close();
  }
}
