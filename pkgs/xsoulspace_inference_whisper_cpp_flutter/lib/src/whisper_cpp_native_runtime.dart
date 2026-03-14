import 'dart:io';
import 'dart:typed_data';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_whisper_cpp_raw/xsoulspace_inference_whisper_cpp_raw.dart';

import 'whisper_cpp_models.dart';
import 'whisper_cpp_realtime_stt_session.dart';

typedef WhisperCppException = WhisperCppRawException;
typedef WhisperCppLibraryLoader = WhisperCppRawLibraryLoader;
typedef WhisperCppBindings = WhisperCppRawBindings;

WhisperCppRawRuntimeConfig _toRawRuntimeConfig(
  final WhisperCppRuntimeConfig value,
) => WhisperCppRawRuntimeConfig(
  libraryPath: value.libraryPath,
  librarySearchPaths: value.librarySearchPaths,
  modelsDirectory: value.modelsDirectory,
);

WhisperCppRawModelConfig _toRawModelConfig(final WhisperCppModelConfig value) =>
    WhisperCppRawModelConfig(
      preset: WhisperCppRawModelPreset.tinyEn,
      modelPath: value.modelPath,
      providerExtras: value.providerExtras,
    );

WhisperCppRawRealtimeConfig _toRawRealtimeConfig(
  final WhisperCppRealtimeConfig value,
) => WhisperCppRawRealtimeConfig(
  sampleRate: value.sampleRate,
  stepMs: value.stepMs,
  lengthMs: value.lengthMs,
  keepMs: value.keepMs,
  threads: value.threads,
  language: value.language,
  translate: value.translate,
  providerExtras: value.providerExtras,
);

final class NativeWhisperCppBatchBackend {
  NativeWhisperCppBatchBackend({
    required this.runtimeConfig,
    required this.modelConfig,
  }) : _runtime = WhisperCppRawBatchRuntime(
         runtimeConfig: _toRawRuntimeConfig(runtimeConfig),
         modelConfig: _toRawModelConfig(modelConfig),
       );

  final WhisperCppRuntimeConfig runtimeConfig;
  final WhisperCppModelConfig modelConfig;
  final WhisperCppRawBatchRuntime _runtime;

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
            'provider': 'whisper_cpp_flutter',
            'model': modelConfig.modelPath,
            'runtime_version': _runtime.version(),
          },
        ),
      );
    } on WhisperCppRawException catch (error) {
      return InferenceResult<InferenceResponse>.fail(
        code: error.code,
        message: error.message,
        details: error.details,
      );
    } on Object catch (error) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message: 'whisper.cpp transcription failed',
        details: error.toString(),
      );
    }
  }

  Future<WhisperCppRawAudioInput> _resolveAudioInput(
    final InferenceAudioInput input,
  ) async {
    switch (input.resolvedSource) {
      case InferenceAudioSource.bytes:
        return WhisperCppRawAudioInput.wav(
          bytes: Uint8List.fromList(input.bytes!),
          sampleRateHz: input.sampleRateHz ?? 16000,
        );
      case InferenceAudioSource.filePath:
        final bytes = await File(input.filePath!).readAsBytes();
        return WhisperCppRawAudioInput.wav(
          bytes: bytes,
          sampleRateHz: input.sampleRateHz ?? 16000,
        );
      case InferenceAudioSource.microphone:
      case null:
        throw const WhisperCppRawException(
          code: errorCodeTaskUnsupported,
          message: 'Microphone input must use a realtime whisper.cpp session',
        );
    }
  }
}

final class NativeWhisperCppRealtimeBackend
    implements WhisperCppRealtimeBackend {
  NativeWhisperCppRealtimeBackend({
    required this.modelConfig,
    required this.runtimeConfig,
    required this.realtimeConfig,
  }) : _runtime = WhisperCppRawRealtimeRuntime(
         modelConfig: _toRawModelConfig(modelConfig),
         runtimeConfig: _toRawRuntimeConfig(runtimeConfig),
         realtimeConfig: _toRawRealtimeConfig(realtimeConfig),
       );

  final WhisperCppModelConfig modelConfig;
  final WhisperCppRuntimeConfig runtimeConfig;
  final WhisperCppRealtimeConfig realtimeConfig;
  final WhisperCppRawRealtimeRuntime _runtime;

  void Function(InferenceTranscriptEvent event)? _emit;

  @override
  Future<void> start({
    required final WhisperCppModelConfig modelConfig,
    required final WhisperCppRuntimeConfig runtimeConfig,
    required final WhisperCppRealtimeConfig realtimeConfig,
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
          'provider': 'whisper_cpp',
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
          'provider': 'whisper_cpp',
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
