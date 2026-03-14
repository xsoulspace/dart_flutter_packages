import 'dart:io';
import 'dart:typed_data';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_sherpa_onnx_raw/xsoulspace_inference_sherpa_onnx_raw.dart';

import 'sherpa_onnx_models.dart';
import 'sherpa_onnx_realtime_stt_session.dart';

typedef SherpaOnnxException = SherpaOnnxRawException;
typedef SherpaOnnxLibraryLoader = SherpaOnnxRawLibraryLoader;
typedef SherpaOnnxBindings = SherpaOnnxRawBindings;

SherpaOnnxRawRuntimeConfig _toRawRuntimeConfig(
  final SherpaOnnxRuntimeConfig value,
) => SherpaOnnxRawRuntimeConfig(
  libraryPath: value.libraryPath,
  librarySearchPaths: value.librarySearchPaths,
  modelsDirectory: value.modelsDirectory,
);

SherpaOnnxRawModelConfig _toRawModelConfig(final SherpaOnnxModelConfig value) =>
    SherpaOnnxRawModelConfig(
      preset: SherpaOnnxRawPreset.streamingZipformerEn20230626,
      encoderPath: value.encoderPath,
      decoderPath: value.decoderPath,
      joinerPath: value.joinerPath,
      tokensPath: value.tokensPath,
      providerExtras: value.providerExtras,
    );

SherpaOnnxRawRealtimeConfig _toRawRealtimeConfig(
  final SherpaOnnxRealtimeConfig value,
) => SherpaOnnxRawRealtimeConfig(
  sampleRate: value.sampleRate,
  featureChunkSize: value.featureChunkSize,
  enableEndpointing: value.enableEndpointing,
  minSilenceDurationMs: value.minSilenceDurationMs,
  minSpeechDurationMs: value.minSpeechDurationMs,
  providerExtras: value.providerExtras,
);

final class NativeSherpaOnnxBatchBackend {
  NativeSherpaOnnxBatchBackend({
    required this.runtimeConfig,
    required this.modelConfig,
  }) : _runtime = SherpaOnnxRawBatchRuntime(
         runtimeConfig: _toRawRuntimeConfig(runtimeConfig),
         modelConfig: _toRawModelConfig(modelConfig),
       );

  final SherpaOnnxRuntimeConfig runtimeConfig;
  final SherpaOnnxModelConfig modelConfig;
  final SherpaOnnxRawBatchRuntime _runtime;

  Future<InferenceResult<InferenceResponse>> transcribe(
    final InferenceRequest request,
  ) async {
    try {
      final input = await _resolveAudioInput(request.audioInput!);
      final result = await _runtime.transcribe(input);
      return InferenceResult<InferenceResponse>.ok(
        InferenceResponse(
          task: InferenceTask.speechToText,
          output: const <String, dynamic>{},
          transcript: result.transcript,
          normalizedTranscript: normalizeTranscript(result.transcript),
          segments: result.segments
              .map(
                (final segment) => InferenceSpeechSegment(
                  text: segment.text,
                  startMs: segment.startMs,
                  endMs: segment.endMs,
                ),
              )
              .toList(growable: false),
          meta: <String, dynamic>{
            'provider': 'sherpa_onnx_flutter',
            'model': modelConfig.encoderPath,
            if (result.rawJson != null) 'raw_result': result.rawJson,
          },
        ),
      );
    } on SherpaOnnxRawException catch (error) {
      return InferenceResult<InferenceResponse>.fail(
        code: error.code,
        message: error.message,
        details: error.details,
      );
    } on Object catch (error) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message: 'Sherpa-ONNX transcription failed',
        details: error.toString(),
      );
    }
  }

  Future<SherpaOnnxRawAudioInput> _resolveAudioInput(
    final InferenceAudioInput input,
  ) async {
    switch (input.resolvedSource) {
      case InferenceAudioSource.bytes:
        return SherpaOnnxRawAudioInput.wav(
          bytes: Uint8List.fromList(input.bytes!),
          sampleRateHz: input.sampleRateHz ?? 16000,
        );
      case InferenceAudioSource.filePath:
        final bytes = await File(input.filePath!).readAsBytes();
        return SherpaOnnxRawAudioInput.wav(
          bytes: bytes,
          sampleRateHz: input.sampleRateHz ?? 16000,
        );
      case InferenceAudioSource.microphone:
      case null:
        throw const SherpaOnnxRawException(
          code: errorCodeTaskUnsupported,
          message: 'Microphone input must use a realtime Sherpa session',
        );
    }
  }
}

final class NativeSherpaOnnxRealtimeBackend
    implements SherpaOnnxRealtimeBackend {
  NativeSherpaOnnxRealtimeBackend({
    required this.modelConfig,
    required this.runtimeConfig,
    required this.realtimeConfig,
  }) : _runtime = SherpaOnnxRawRealtimeRuntime(
         modelConfig: _toRawModelConfig(modelConfig),
         runtimeConfig: _toRawRuntimeConfig(runtimeConfig),
         realtimeConfig: _toRawRealtimeConfig(realtimeConfig),
       );

  final SherpaOnnxModelConfig modelConfig;
  final SherpaOnnxRuntimeConfig runtimeConfig;
  final SherpaOnnxRealtimeConfig realtimeConfig;
  final SherpaOnnxRawRealtimeRuntime _runtime;

  void Function(InferenceTranscriptEvent event)? _emit;

  @override
  Future<void> start({
    required final SherpaOnnxModelConfig modelConfig,
    required final SherpaOnnxRuntimeConfig runtimeConfig,
    required final SherpaOnnxRealtimeConfig realtimeConfig,
    required final void Function(InferenceTranscriptEvent event) emit,
  }) async {
    _emit = emit;
    await _runtime.start();
  }

  @override
  Future<void> sendAudioChunk(final List<int> audioBytes) async {
    final result = _runtime.sendAudioChunk(audioBytes);
    if (result == null) {
      return;
    }
    _emit?.call(
      InferenceTranscriptEvent(
        type: InferenceTranscriptEventType.partialTranscript,
        timestamp: DateTime.now().toUtc(),
        transcript: result.transcript,
        sessionState: InferenceRealtimeSessionState.streaming,
        metadata: <String, dynamic>{
          'provider': 'sherpa_onnx',
          if (result.rawJson != null) 'raw_result': result.rawJson,
          if (result.segments.isNotEmpty)
            'segments': result.segments
                .map(
                  (final segment) => <String, dynamic>{
                    'text': segment.text,
                    'start_ms': segment.startMs,
                    'end_ms': segment.endMs,
                  },
                )
                .toList(growable: false),
        },
      ),
    );
  }

  @override
  Future<void> commit() async {
    final result = _runtime.commit();
    if (result == null) {
      return;
    }
    _emit?.call(
      InferenceTranscriptEvent(
        type: InferenceTranscriptEventType.finalTranscript,
        timestamp: DateTime.now().toUtc(),
        transcript: result.transcript,
        isFinal: true,
        sessionState: InferenceRealtimeSessionState.finalizing,
        metadata: <String, dynamic>{
          'provider': 'sherpa_onnx',
          if (result.rawJson != null) 'raw_result': result.rawJson,
          if (result.segments.isNotEmpty)
            'segments': result.segments
                .map(
                  (final segment) => <String, dynamic>{
                    'text': segment.text,
                    'start_ms': segment.startMs,
                    'end_ms': segment.endMs,
                  },
                )
                .toList(growable: false),
        },
      ),
    );
  }

  @override
  Future<void> stop() async {
    await _runtime.stop();
    _emit = null;
  }
}
