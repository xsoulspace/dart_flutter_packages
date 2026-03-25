import 'dart:async';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'vosk_availability_probe.dart';
import 'vosk_models.dart';
import 'vosk_native_runtime.dart';

abstract interface class VoskRealtimeBackend {
  Future<void> start({
    required VoskModelConfig modelConfig,
    required VoskRuntimeConfig runtimeConfig,
    required VoskRealtimeConfig realtimeConfig,
    required void Function(InferenceTranscriptEvent event) emit,
  });

  Future<void> sendAudioChunk(List<int> audioBytes);

  Future<void> commit();

  Future<void> stop();
}

class VoskRealtimeSttSession
    implements
        InferenceRealtimeSession<InferenceTranscriptEvent>,
        InferenceRealtimeAudioSink {
  VoskRealtimeSttSession({
    VoskRealtimeBackend? backend,
    this.modelConfig = const VoskModelConfig(),
    this.runtimeConfig = const VoskRuntimeConfig(),
    this.realtimeConfig = const VoskRealtimeConfig(),
    VoskAvailabilityProbe? availabilityProbe,
  }) : _backend =
           backend ??
           NativeVoskRealtimeBackend(
             modelConfig: modelConfig,
             runtimeConfig: runtimeConfig,
             realtimeConfig: realtimeConfig,
           ),
       _availabilityProbe =
           availabilityProbe ??
           VoskAvailabilityProbe(
             runtimeConfig: runtimeConfig,
             modelPathResolver: () {
               final direct = modelConfig.modelPath.trim();
               return direct.isEmpty ? null : direct;
             },
           );

  final VoskRealtimeBackend _backend;
  final VoskAvailabilityProbe _availabilityProbe;
  final StreamController<InferenceTranscriptEvent> _eventsController =
      StreamController<InferenceTranscriptEvent>.broadcast();

  final VoskModelConfig modelConfig;
  final VoskRuntimeConfig runtimeConfig;
  final VoskRealtimeConfig realtimeConfig;

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
        message: 'Vosk realtime session is already connected',
      );
    }

    if (!_availabilityProbe.isPlatformSupported()) {
      return InferenceResult<void>.fail(
        code: errorCodeTaskUnsupported,
        message: 'Vosk realtime STT is unsupported on this host',
      );
    }

    try {
      _eventsController.add(
        InferenceTranscriptEvent(
          type: InferenceTranscriptEventType.sessionStateChanged,
          timestamp: DateTime.now().toUtc(),
          sessionState: InferenceRealtimeSessionState.connecting,
          metadata: const <String, dynamic>{'provider': 'vosk'},
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
          metadata: const <String, dynamic>{'provider': 'vosk'},
        ),
      );
      return InferenceResult<void>.ok(null);
    } catch (error) {
      return InferenceResult<void>.fail(
        code: 'engine_unavailable',
        message: 'Failed to start Vosk realtime session',
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
        message: 'Vosk realtime session is not connected',
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
        message: 'Failed to send Vosk audio chunk',
        details: error.toString(),
      );
    }
  }

  Future<InferenceResult<void>> commit() async {
    if (!_isConnected) {
      return InferenceResult<void>.fail(
        code: 'engine_unavailable',
        message: 'Vosk realtime session is not connected',
      );
    }

    try {
      await _backend.commit();
      return InferenceResult<void>.ok(null);
    } catch (error) {
      return InferenceResult<void>.fail(
        code: 'engine_unavailable',
        message: 'Failed to finalize Vosk realtime session',
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
        metadata: const <String, dynamic>{'provider': 'vosk'},
      ),
    );
  }

  @override
  Future<void> dispose() async {
    await close();
    await _eventsController.close();
  }
}
