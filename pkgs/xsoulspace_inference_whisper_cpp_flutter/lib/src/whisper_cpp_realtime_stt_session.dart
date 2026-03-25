import 'dart:async';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'whisper_cpp_availability_probe.dart';
import 'whisper_cpp_models.dart';
import 'whisper_cpp_native_runtime.dart';

abstract interface class WhisperCppRealtimeBackend {
  Future<void> start({
    required WhisperCppModelConfig modelConfig,
    required WhisperCppRuntimeConfig runtimeConfig,
    required WhisperCppRealtimeConfig realtimeConfig,
    required void Function(InferenceTranscriptEvent event) emit,
  });

  Future<void> sendAudioChunk(List<int> audioBytes);

  Future<void> commit();

  Future<void> stop();
}

class WhisperCppRealtimeSttSession
    implements
        InferenceRealtimeSession<InferenceTranscriptEvent>,
        InferenceRealtimeAudioSink {
  WhisperCppRealtimeSttSession({
    WhisperCppRealtimeBackend? backend,
    this.modelConfig = const WhisperCppModelConfig(),
    this.runtimeConfig = const WhisperCppRuntimeConfig(),
    this.realtimeConfig = const WhisperCppRealtimeConfig(),
    WhisperCppAvailabilityProbe? availabilityProbe,
  }) : _backend =
           backend ??
           NativeWhisperCppRealtimeBackend(
             modelConfig: modelConfig,
             runtimeConfig: runtimeConfig,
             realtimeConfig: realtimeConfig,
           ),
       _availabilityProbe =
           availabilityProbe ??
           WhisperCppAvailabilityProbe(
             runtimeConfig: runtimeConfig,
             modelPathResolver: () {
               final direct = modelConfig.modelPath.trim();
               return direct.isEmpty ? null : direct;
             },
           );

  final WhisperCppRealtimeBackend _backend;
  final WhisperCppAvailabilityProbe _availabilityProbe;
  final StreamController<InferenceTranscriptEvent> _eventsController =
      StreamController<InferenceTranscriptEvent>.broadcast();

  final WhisperCppModelConfig modelConfig;
  final WhisperCppRuntimeConfig runtimeConfig;
  final WhisperCppRealtimeConfig realtimeConfig;

  bool _isConnected = false;

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<InferenceTranscriptEvent> get events => _eventsController.stream;

  @override
  Future<InferenceResult<void>> connect() async {
    if (_isConnected) {
      return InferenceResult<void>.fail(
        code: 'request_invalid',
        message: 'whisper.cpp realtime session is already connected',
      );
    }

    final requiresNativeLoad = _backend is NativeWhisperCppRealtimeBackend;
    final isReady = requiresNativeLoad
        ? _availabilityProbe.canLoad(runtimeConfig)
        : _availabilityProbe.isPlatformSupported();
    if (!isReady) {
      return InferenceResult<void>.fail(
        code: errorCodeTaskUnsupported,
        message: 'whisper.cpp realtime STT is unsupported on this host',
      );
    }

    try {
      _eventsController.add(
        InferenceTranscriptEvent(
          type: InferenceTranscriptEventType.sessionStateChanged,
          timestamp: DateTime.now().toUtc(),
          sessionState: InferenceRealtimeSessionState.connecting,
          metadata: const <String, dynamic>{'provider': 'whisper_cpp'},
        ),
      );

      await _backend.start(
        modelConfig: modelConfig,
        runtimeConfig: runtimeConfig,
        realtimeConfig: realtimeConfig,
        emit: _eventsController.add,
      );
      _isConnected = true;
      _eventsController.add(
        InferenceTranscriptEvent(
          type: InferenceTranscriptEventType.sessionStateChanged,
          timestamp: DateTime.now().toUtc(),
          sessionState: InferenceRealtimeSessionState.streaming,
          metadata: const <String, dynamic>{'provider': 'whisper_cpp'},
        ),
      );
      return InferenceResult<void>.ok(null);
    } catch (error) {
      return InferenceResult<void>.fail(
        code: 'engine_unavailable',
        message: 'Failed to start whisper.cpp realtime session',
        details: error.toString(),
      );
    }
  }

  Future<InferenceResult<void>> sendAudioChunk(
    final List<int> audioBytes,
  ) async {
    if (!_isConnected) {
      return InferenceResult<void>.fail(
        code: 'engine_unavailable',
        message: 'whisper.cpp realtime session is not connected',
      );
    }

    if (audioBytes.isEmpty) {
      return InferenceResult<void>.fail(
        code: 'request_invalid',
        message: 'Audio chunk must not be empty',
      );
    }

    try {
      await _backend.sendAudioChunk(audioBytes);
      return InferenceResult<void>.ok(null);
    } catch (error) {
      return InferenceResult<void>.fail(
        code: 'engine_unavailable',
        message: 'Failed to send whisper.cpp audio chunk',
        details: error.toString(),
      );
    }
  }

  Future<InferenceResult<void>> commit() async {
    if (!_isConnected) {
      return InferenceResult<void>.fail(
        code: 'engine_unavailable',
        message: 'whisper.cpp realtime session is not connected',
      );
    }

    try {
      await _backend.commit();
      return InferenceResult<void>.ok(null);
    } catch (error) {
      return InferenceResult<void>.fail(
        code: 'engine_unavailable',
        message: 'Failed to finalize whisper.cpp realtime session',
        details: error.toString(),
      );
    }
  }

  @override
  Future<void> close() async {
    if (!_isConnected) {
      return;
    }

    await _backend.stop();
    _isConnected = false;
    _eventsController.add(
      InferenceTranscriptEvent(
        type: InferenceTranscriptEventType.sessionStateChanged,
        timestamp: DateTime.now().toUtc(),
        sessionState: InferenceRealtimeSessionState.closed,
        metadata: const <String, dynamic>{'provider': 'whisper_cpp'},
      ),
    );
  }

  @override
  Future<void> dispose() async {
    await close();
    await _eventsController.close();
  }
}
