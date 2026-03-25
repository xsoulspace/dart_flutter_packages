import 'dart:typed_data';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_vosk_raw/xsoulspace_inference_vosk_raw.dart';

import 'vosk_models.dart';
import 'vosk_realtime_stt_session.dart';

typedef VoskException = VoskRawException;
typedef VoskLibraryLoader = VoskRawLibraryLoader;
typedef VoskBindings = VoskRawBindings;

VoskRawRuntimeConfig _toRawRuntimeConfig(final VoskRuntimeConfig value) =>
    VoskRawRuntimeConfig(
      libraryPath: value.libraryPath,
      librarySearchPaths: value.librarySearchPaths,
      modelDirectory: value.modelDirectory,
    );

VoskRawModelConfig _toRawModelConfig(final VoskModelConfig value) =>
    VoskRawModelConfig(
      modelPath: value.modelPath,
      providerExtras: value.providerExtras,
    );

VoskRawRealtimeConfig _toRawRealtimeConfig(final VoskRealtimeConfig value) =>
    VoskRawRealtimeConfig(
      sampleRate: value.sampleRate,
      emitPartialWords: value.emitPartialWords,
      minSilenceDurationMs: value.minSilenceDurationMs,
      providerExtras: value.providerExtras,
    );

final class NativeVoskBatchBackend {
  NativeVoskBatchBackend({
    required this.runtimeConfig,
    required this.modelConfig,
  }) : _runtime = VoskRawBatchRuntime(
         runtimeConfig: _toRawRuntimeConfig(runtimeConfig),
         modelConfig: _toRawModelConfig(modelConfig),
       );

  final VoskRuntimeConfig runtimeConfig;
  final VoskModelConfig modelConfig;
  final VoskRawBatchRuntime _runtime;

  Future<InferenceResult<InferenceResponse>> transcribe(
    final InferenceRequest request,
  ) async {
    try {
      final input = await _resolveAudioInput(request.audioInput!);
      final result = await _runtime.transcribe(input);
      return InferenceResult<InferenceResponse>.ok(
        InferenceResponse(
          task: InferenceTask.speechToText,
          output: <String, dynamic>{
            if (result.alternatives.isNotEmpty)
              'alternatives': result.alternatives,
          },
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
            'provider': 'vosk_flutter',
            'model': modelConfig.modelPath,
            if (result.rawJson != null) 'raw_result': result.rawJson,
          },
        ),
      );
    } on VoskRawException catch (error) {
      return InferenceResult<InferenceResponse>.fail(
        code: error.code,
        message: error.message,
        details: error.details,
      );
    } on Object catch (error) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message: 'Vosk transcription failed',
        details: error.toString(),
      );
    }
  }

  Future<VoskRawAudioInput> _resolveAudioInput(
    final InferenceAudioInput input,
  ) async {
    switch (input.resolvedSource) {
      case InferenceAudioSource.bytes:
        return VoskRawAudioInput.wav(
          bytes: Uint8List.fromList(input.bytes!),
          sampleRateHz: input.sampleRateHz ?? 16000,
        );
      case InferenceAudioSource.filePath:
        final bytes = await readVoskRawAudioInput(
          filePath: input.filePath,
          bytes: null,
          isBytes: false,
        );
        return VoskRawAudioInput.pcm16le(
          bytes: bytes,
          sampleRateHz: input.sampleRateHz ?? 16000,
        );
      case InferenceAudioSource.microphone:
      case null:
        throw const VoskRawException(
          code: errorCodeTaskUnsupported,
          message: 'Microphone input must use a realtime Vosk session',
        );
    }
  }
}

final class NativeVoskRealtimeBackend implements VoskRealtimeBackend {
  NativeVoskRealtimeBackend({
    required this.modelConfig,
    required this.runtimeConfig,
    required this.realtimeConfig,
  }) : _runtime = VoskRawRealtimeRuntime(
         modelConfig: _toRawModelConfig(modelConfig),
         runtimeConfig: _toRawRuntimeConfig(runtimeConfig),
         realtimeConfig: _toRawRealtimeConfig(realtimeConfig),
       );

  final VoskModelConfig modelConfig;
  final VoskRuntimeConfig runtimeConfig;
  final VoskRealtimeConfig realtimeConfig;
  final VoskRawRealtimeRuntime _runtime;

  void Function(InferenceTranscriptEvent event)? _emit;

  @override
  Future<void> start({
    required final VoskModelConfig modelConfig,
    required final VoskRuntimeConfig runtimeConfig,
    required final VoskRealtimeConfig realtimeConfig,
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
        type: result.isFinal
            ? InferenceTranscriptEventType.finalTranscript
            : InferenceTranscriptEventType.partialTranscript,
        timestamp: DateTime.now().toUtc(),
        transcript: result.transcript,
        isFinal: result.isFinal,
        sessionState: result.isFinal
            ? InferenceRealtimeSessionState.finalizing
            : InferenceRealtimeSessionState.streaming,
        metadata: <String, dynamic>{
          'provider': 'vosk',
          if (result.rawJson != null) 'raw_result': result.rawJson,
          if (result.alternatives.isNotEmpty)
            'alternatives': result.alternatives,
          if (result.segments.isNotEmpty)
            'segments': result.segments
                .map(
                  (final segment) => <String, dynamic>{
                    'text': segment.text,
                    'start_ms': segment.startMs,
                    'end_ms': segment.endMs,
                    if (segment.confidence != null)
                      'confidence': segment.confidence,
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
          'provider': 'vosk',
          if (result.rawJson != null) 'raw_result': result.rawJson,
          if (result.alternatives.isNotEmpty)
            'alternatives': result.alternatives,
          if (result.segments.isNotEmpty)
            'segments': result.segments
                .map(
                  (final segment) => <String, dynamic>{
                    'text': segment.text,
                    'start_ms': segment.startMs,
                    'end_ms': segment.endMs,
                    if (segment.confidence != null)
                      'confidence': segment.confidence,
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
