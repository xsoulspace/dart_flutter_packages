import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import '../elevenlabs_common.dart';
import '../elevenlabs_config.dart';
import 'elevenlabs_realtime_common.dart';

class ElevenLabsRealtimeSttEvent {
  const ElevenLabsRealtimeSttEvent({
    required this.messageType,
    required this.raw,
    this.transcript,
    this.isError = false,
  });

  final String messageType;
  final Map<String, dynamic> raw;
  final String? transcript;
  final bool isError;
}

class ElevenLabsRealtimeSttSession {
  ElevenLabsRealtimeSttSession({
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

  final StreamController<ElevenLabsRealtimeSttEvent> _eventsController =
      StreamController<ElevenLabsRealtimeSttEvent>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  int _sampleRate = 16000;

  Stream<ElevenLabsRealtimeSttEvent> get events => _eventsController.stream;

  bool get isConnected => _channel != null;

  Future<InferenceResult<void>> connect({
    final String modelId = 'scribe_v1',
    final String audioFormat = 'pcm_16000',
    final int sampleRate = 16000,
    final String commitStrategy = 'manual',
    final String? languageCode,
    final bool includeTimestamps = false,
    final double? vadSilenceThresholdSecs,
    final double? vadThreshold,
    final int? minSpeechDurationMs,
    final int? minSilenceDurationMs,
  }) async {
    final normalizedModelId = modelId.trim();
    if (normalizedModelId.isEmpty) {
      return InferenceResult<void>.fail(
        code: 'request_invalid',
        message: 'Realtime STT requires non-empty modelId',
      );
    }

    if (sampleRate <= 0) {
      return InferenceResult<void>.fail(
        code: 'request_invalid',
        message: 'Realtime STT sampleRate must be greater than zero',
      );
    }

    if (isConnected) {
      return InferenceResult<void>.fail(
        code: 'request_invalid',
        message: 'Realtime STT session is already connected',
      );
    }

    final authHeadersResult = await resolveRealtimeAuthHeaders(_authConfig);
    if (!authHeadersResult.success || authHeadersResult.data == null) {
      return InferenceResult<void>.fail(
        code: authHeadersResult.error?.code ?? errorCodeAuthFailed,
        message:
            authHeadersResult.error?.message ??
            'Realtime STT auth resolution failed',
      );
    }

    final query = <String, String>{
      'model_id': normalizedModelId,
      'audio_format': audioFormat.trim(),
      'commit_strategy': commitStrategy.trim(),
      'include_timestamps': includeTimestamps.toString(),
      if (languageCode != null && languageCode.trim().isNotEmpty)
        'language_code': languageCode.trim(),
      if (vadSilenceThresholdSecs != null)
        'vad_silence_threshold_secs': vadSilenceThresholdSecs.toString(),
      if (vadThreshold != null) 'vad_threshold': vadThreshold.toString(),
      if (minSpeechDurationMs != null)
        'min_speech_duration_ms': minSpeechDurationMs.toString(),
      if (minSilenceDurationMs != null)
        'min_silence_duration_ms': minSilenceDurationMs.toString(),
    };

    final uri = _endpointConfig.resolveWebSocketPath(
      '/v1/speech-to-text/realtime',
      query: query,
    );

    try {
      _sampleRate = sampleRate;
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
        message: 'Failed to connect ElevenLabs realtime STT websocket',
        details: error.toString(),
      );
    }
  }

  Future<InferenceResult<void>> sendAudioChunk(
    final List<int> audioBytes, {
    final String? previousText,
    final bool commit = false,
  }) {
    if (audioBytes.isEmpty && !commit) {
      return Future<InferenceResult<void>>.value(
        InferenceResult<void>.fail(
          code: 'request_invalid',
          message: 'Realtime STT audio chunk must not be empty',
        ),
      );
    }

    return _sendJson(<String, dynamic>{
      'message_type': 'input_audio_chunk',
      'audio_base_64': base64Encode(audioBytes),
      'commit': commit,
      'sample_rate': _sampleRate,
      if (previousText != null && previousText.trim().isNotEmpty)
        'previous_text': previousText,
    });
  }

  Future<InferenceResult<void>> commit() => _sendJson(<String, dynamic>{
    'message_type': 'input_audio_chunk',
    'audio_base_64': '',
    'commit': true,
    'sample_rate': _sampleRate,
  });

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
        message: 'Realtime STT websocket is not connected',
      );
    }

    try {
      channel.sink.add(jsonEncode(payload));
      return InferenceResult<void>.ok(null);
    } catch (error) {
      return InferenceResult<void>.fail(
        code: 'engine_unavailable',
        message: 'Failed to send realtime STT message',
        details: error.toString(),
      );
    }
  }

  void _handleIncomingMessage(final Object? message) {
    if (message is! String) {
      _eventsController.add(
        const ElevenLabsRealtimeSttEvent(
          messageType: 'non_text_message',
          raw: <String, dynamic>{'message_type': 'non_text_message'},
          isError: true,
        ),
      );
      return;
    }

    try {
      final decoded = jsonDecode(message);
      final raw = mapWithStringKeys(decoded);
      if (raw.isEmpty) {
        _eventsController.add(
          const ElevenLabsRealtimeSttEvent(
            messageType: 'invalid_json',
            raw: <String, dynamic>{'message_type': 'invalid_json'},
            isError: true,
          ),
        );
        return;
      }

      final messageType = nonEmptyString(raw['message_type']) ?? 'unknown';
      final transcript =
          nonEmptyString(raw['transcript']) ?? nonEmptyString(raw['text']);
      final isError = _errorMessageTypes.contains(messageType);

      _eventsController.add(
        ElevenLabsRealtimeSttEvent(
          messageType: messageType,
          raw: raw,
          transcript: transcript,
          isError: isError,
        ),
      );
    } catch (error) {
      _eventsController.add(
        ElevenLabsRealtimeSttEvent(
          messageType: 'decode_error',
          raw: const <String, dynamic>{'message_type': 'decode_error'},
          isError: true,
          transcript: error.toString(),
        ),
      );
    }
  }

  void _handleSocketError(final Object error, final StackTrace stackTrace) {
    _eventsController.add(
      ElevenLabsRealtimeSttEvent(
        messageType: 'socket_error',
        raw: const <String, dynamic>{'message_type': 'socket_error'},
        isError: true,
        transcript: error.toString(),
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

  static const Set<String> _errorMessageTypes = <String>{
    'error',
    'auth_error',
    'quota_exceeded',
    'commit_throttled',
    'transcriber_error',
    'unaccepted_terms_error',
    'rate_limited',
    'input_error',
    'queue_overflow',
    'resource_exhausted',
    'session_time_limit_exceeded',
    'chunk_size_exceeded',
    'insufficient_audio_activity',
  };
}
