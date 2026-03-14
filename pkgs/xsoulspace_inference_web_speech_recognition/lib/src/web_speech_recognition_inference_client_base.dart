import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'web_speech_recognition_adapter.dart';

class WebSpeechRecognitionInferenceClientBase implements InferenceClient {
  WebSpeechRecognitionInferenceClientBase({
    required final WebSpeechRecognitionAdapter adapter,
  }) : _adapter = adapter;

  final WebSpeechRecognitionAdapter _adapter;

  @override
  String get id => 'web_speech_recognition';

  @override
  bool get isAvailable =>
      _adapter.hasSpeechRecognitionApi && _adapter.isChromiumFamily;

  @override
  Set<InferenceTask> get supportedTasks => const <InferenceTask>{
    InferenceTask.speechToText,
  };

  @override
  Future<bool> refreshAvailability() async => isAvailable;

  @override
  void resetAvailabilityCache() {
    // No availability cache; capability checks are dynamic.
  }

  @override
  Future<InferenceResult<InferenceResponse>> infer(
    final InferenceRequest request,
  ) async {
    if (!supportedTasks.contains(request.task)) {
      return InferenceResult<InferenceResponse>.fail(
        code: errorCodeTaskUnsupported,
        message: 'Task ${request.task.name} is not supported by $id',
        details: <String, dynamic>{
          'supported_tasks': supportedTasks
              .map((final task) => task.name)
              .toList(),
          'requested_task': request.task.name,
        },
      );
    }

    if (!isAvailable) {
      return InferenceResult<InferenceResponse>.fail(
        code: errorCodeTaskUnsupported,
        message: '$id requires a Chromium-family browser with Web Speech API',
        details: <String, dynamic>{
          'reason': 'chromium_or_api_unavailable',
          'requires_chromium': true,
          'speech_recognition_api_detected': _adapter.hasSpeechRecognitionApi,
          'chromium_family': _adapter.isChromiumFamily,
        },
      );
    }

    final requestValidation = validateInferenceRequest(request);
    if (!requestValidation.success) {
      return InferenceResult<InferenceResponse>.fail(
        code: requestValidation.error?.code ?? 'request_invalid',
        message:
            requestValidation.error?.message ??
            'Inference request validation failed',
        details: requestValidation.error?.details,
      );
    }

    final audioInput = request.audioInput;
    if (audioInput == null) {
      return InferenceResult<InferenceResponse>.fail(
        code: errorCodeAudioInputMissing,
        message: 'Speech-to-text request requires audioInput',
      );
    }

    final language = _resolveLanguage(request);

    try {
      final transcript = await _adapter.recognize(
        audioInput: audioInput,
        language: language,
      );
      final normalizedTranscript = normalizeTranscript(transcript);

      final source = audioInput.resolvedSource;
      final meta = <String, dynamic>{
        'provider': id,
        'language': language ?? 'browser_default',
        if (source != null)
          'audio_source': inferenceAudioSourceToJsonValue(source),
      };

      return InferenceResult<InferenceResponse>.ok(
        InferenceResponse(
          task: InferenceTask.speechToText,
          output: const <String, dynamic>{},
          transcript: transcript,
          normalizedTranscript: normalizedTranscript,
          segments: <InferenceSpeechSegment>[
            InferenceSpeechSegment(text: transcript, startMs: 0, endMs: 0),
          ],
          meta: meta,
        ),
        meta: meta,
      );
    } on WebSpeechRecognitionAdapterException catch (error) {
      return _mapAdapterFailure(error);
    } catch (error) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message: 'Web Speech runtime failed unexpectedly',
        details: error.toString(),
      );
    }
  }

  /// Starts live (streaming) recognition on microphone. Returns null if unavailable.
  WebSpeechLiveRecognitionSession? startLiveRecognition({String? language}) =>
      _adapter.startLiveRecognition(language: language);

  String? _resolveLanguage(final InferenceRequest request) {
    final rawLanguage = request.metadata['language'];
    if (rawLanguage is! String) {
      return null;
    }

    final language = rawLanguage.trim();
    return language.isEmpty ? null : language;
  }

  InferenceResult<InferenceResponse> _mapAdapterFailure(
    final WebSpeechRecognitionAdapterException error,
  ) {
    final details = error.toDetails();

    switch (error.kind) {
      case WebSpeechRecognitionFailureKind.permissionOrServiceBlocked:
        return InferenceResult<InferenceResponse>.fail(
          code: errorCodeTaskUnsupported,
          message: error.message,
          details: details,
        );
      case WebSpeechRecognitionFailureKind.invalidCaptureOrInput:
        return InferenceResult<InferenceResponse>.fail(
          code: errorCodeAudioInputInvalid,
          message: error.message,
          details: details,
        );
      case WebSpeechRecognitionFailureKind.runtimeEngineOrNetworkOrLanguage:
        return InferenceResult<InferenceResponse>.fail(
          code: 'engine_unavailable',
          message: error.message,
          details: details,
        );
      case WebSpeechRecognitionFailureKind.unsupported:
        return InferenceResult<InferenceResponse>.fail(
          code: errorCodeTaskUnsupported,
          message: error.message,
          details: details,
        );
    }
  }
}
