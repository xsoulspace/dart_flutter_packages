import 'dart:async';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'sherpa_onnx_availability_probe.dart';
import 'sherpa_onnx_models.dart';
import 'sherpa_onnx_native_runtime.dart';

abstract interface class SherpaOnnxRealtimeBackend {
  Future<void> start({
    required SherpaOnnxModelConfig modelConfig,
    required SherpaOnnxRuntimeConfig runtimeConfig,
    required SherpaOnnxRealtimeConfig realtimeConfig,
    required void Function(InferenceTranscriptEvent event) emit,
  });

  Future<void> sendAudioChunk(List<int> audioBytes);

  Future<void> commit();

  Future<void> stop();
}

class SherpaOnnxRealtimeSttSession
    implements
        InferenceRealtimeSession<InferenceTranscriptEvent>,
        InferenceRealtimeAudioSink {
  SherpaOnnxRealtimeSttSession({
    SherpaOnnxRealtimeBackend? backend,
    this.modelConfig =
        const SherpaOnnxModelConfig.streamingZipformerEn20230626(),
    this.runtimeConfig = const SherpaOnnxRuntimeConfig(),
    this.realtimeConfig = const SherpaOnnxRealtimeConfig(),
    SherpaOnnxAvailabilityProbe? availabilityProbe,
  }) : _backend =
           backend ??
           NativeSherpaOnnxRealtimeBackend(
             modelConfig: modelConfig,
             runtimeConfig: runtimeConfig,
             realtimeConfig: realtimeConfig,
           ),
       _availabilityProbe =
           availabilityProbe ??
           SherpaOnnxAvailabilityProbe(
             runtimeConfig: runtimeConfig,
             modelPathResolver: () => runtimeConfig.modelsDirectory,
           );

  final SherpaOnnxRealtimeBackend _backend;
  final SherpaOnnxAvailabilityProbe _availabilityProbe;
  final StreamController<InferenceTranscriptEvent> _eventsController =
      StreamController<InferenceTranscriptEvent>.broadcast();

  final SherpaOnnxModelConfig modelConfig;
  final SherpaOnnxRuntimeConfig runtimeConfig;
  final SherpaOnnxRealtimeConfig realtimeConfig;

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
        message: 'Sherpa-ONNX realtime session is already connected',
      );
    }

    final requiresNativeLoad = _backend is NativeSherpaOnnxRealtimeBackend;
    final isReady = requiresNativeLoad
        ? _availabilityProbe.canLoad(runtimeConfig)
        : _availabilityProbe.isPlatformSupported();
    if (!isReady) {
      return InferenceResult<void>.fail(
        code: errorCodeTaskUnsupported,
        message: 'Sherpa-ONNX realtime STT is unavailable on this host',
      );
    }

    try {
      _eventsController.add(
        InferenceTranscriptEvent(
          type: InferenceTranscriptEventType.sessionStateChanged,
          timestamp: DateTime.now().toUtc(),
          sessionState: InferenceRealtimeSessionState.connecting,
          metadata: const <String, dynamic>{'provider': 'sherpa_onnx'},
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
          metadata: const <String, dynamic>{'provider': 'sherpa_onnx'},
        ),
      );
      return InferenceResult<void>.ok(null);
    } catch (error) {
      return InferenceResult<void>.fail(
        code: 'engine_unavailable',
        message: 'Failed to start Sherpa-ONNX realtime session',
        details: error.toString(),
      );
    }
  }

  @override
  Future<InferenceResult<void>> sendAudioChunk(
    final List<int> audioBytes,
  ) async {
    if (!_isConnected) {
      return InferenceResult<void>.fail(
        code: 'engine_unavailable',
        message: 'Sherpa-ONNX realtime session is not connected',
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
        message: 'Failed to send Sherpa-ONNX audio chunk',
        details: error.toString(),
      );
    }
  }

  @override
  Future<InferenceResult<void>> commit() async {
    if (!_isConnected) {
      return InferenceResult<void>.fail(
        code: 'engine_unavailable',
        message: 'Sherpa-ONNX realtime session is not connected',
      );
    }

    _eventsController.add(
      InferenceTranscriptEvent(
        type: InferenceTranscriptEventType.sessionStateChanged,
        timestamp: DateTime.now().toUtc(),
        sessionState: InferenceRealtimeSessionState.finalizing,
        metadata: const <String, dynamic>{'provider': 'sherpa_onnx'},
      ),
    );

    try {
      await _backend.commit();
      return InferenceResult<void>.ok(null);
    } catch (error) {
      return InferenceResult<void>.fail(
        code: 'engine_unavailable',
        message: 'Failed to finalize Sherpa-ONNX realtime session',
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
        metadata: const <String, dynamic>{'provider': 'sherpa_onnx'},
      ),
    );
  }

  @override
  Future<void> dispose() async {
    await close();
    await _eventsController.close();
  }
}
