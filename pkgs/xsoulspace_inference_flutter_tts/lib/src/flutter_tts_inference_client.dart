import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:path/path.dart' as p;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

abstract class FlutterTtsDriver {
  Future<dynamic> awaitSynthCompletion(bool awaitCompletion);
  Future<dynamic> synthesizeToFile(
    String text,
    String fileName,
    bool isFullPath,
  );
  Future<dynamic> setLanguage(String language);
  Future<dynamic> setSpeechRate(double rate);
  Future<dynamic> setPitch(double pitch);
  Future<dynamic> setVoice(Map<String, String> voice);
}

class MethodChannelFlutterTtsDriver implements FlutterTtsDriver {
  MethodChannelFlutterTtsDriver([final FlutterTts? flutterTts])
    : _flutterTts = flutterTts ?? FlutterTts();

  final FlutterTts _flutterTts;

  @override
  Future<dynamic> awaitSynthCompletion(final bool awaitCompletion) =>
      _flutterTts.awaitSynthCompletion(awaitCompletion);

  @override
  Future<dynamic> synthesizeToFile(
    final String text,
    final String fileName,
    final bool isFullPath,
  ) => _flutterTts.synthesizeToFile(text, fileName, isFullPath);

  @override
  Future<dynamic> setLanguage(final String language) =>
      _flutterTts.setLanguage(language);

  @override
  Future<dynamic> setSpeechRate(final double rate) =>
      _flutterTts.setSpeechRate(rate);

  @override
  Future<dynamic> setPitch(final double pitch) => _flutterTts.setPitch(pitch);

  @override
  Future<dynamic> setVoice(final Map<String, String> voice) =>
      _flutterTts.setVoice(voice);
}

class FlutterTtsInferenceClient implements InferenceClient {
  FlutterTtsInferenceClient({
    final FlutterTtsDriver? driver,
    final bool Function()? isSupportedPlatform,
    DateTime Function()? now,
  }) : _driver = driver ?? MethodChannelFlutterTtsDriver(),
       _isSupportedPlatform = isSupportedPlatform ?? _defaultPlatformCheck,
       _now = now ?? DateTime.now;

  final FlutterTtsDriver _driver;
  final bool Function() _isSupportedPlatform;
  final DateTime Function() _now;

  @override
  String get id => 'flutter_tts';

  @override
  bool get isAvailable => _isSupportedPlatform();

  @override
  Set<InferenceTask> get supportedTasks => const <InferenceTask>{
    InferenceTask.textToSpeech,
  };

  @override
  Future<bool> refreshAvailability() async => isAvailable;

  @override
  void resetAvailabilityCache() {
    // No availability cache; platform support is evaluated dynamically.
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
        message: '$id artifact synthesis is supported only on iOS/Android',
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

    final outputSpec = _resolveOutputSpec(request);
    final outputFile = File(outputSpec.filePath);

    try {
      await outputFile.parent.create(recursive: true);
      await _applyVoiceOptions(request.voiceOptions);
      await _driver.awaitSynthCompletion(true);
      final synthResult = await _driver.synthesizeToFile(
        request.prompt,
        outputSpec.filePath,
        true,
      );

      if (synthResult is int && synthResult != 1) {
        return InferenceResult<InferenceResponse>.fail(
          code: errorCodeAudioOutputUnavailable,
          message: 'TTS synthesis failed with non-success result code',
          details: <String, dynamic>{'result': synthResult},
        );
      }

      if (!outputFile.existsSync()) {
        return InferenceResult<InferenceResponse>.fail(
          code: errorCodeAudioOutputUnavailable,
          message: 'TTS synthesizeToFile finished but no artifact was produced',
          details: <String, dynamic>{'file_path': outputSpec.filePath},
        );
      }

      final meta = <String, dynamic>{
        'provider': id,
        'output_file_path': outputSpec.filePath,
      };

      return InferenceResult<InferenceResponse>.ok(
        InferenceResponse(
          task: InferenceTask.textToSpeech,
          output: const <String, dynamic>{},
          audioArtifact: InferenceAudioArtifact(
            filePath: outputSpec.filePath,
            mimeType: outputSpec.mimeType,
          ),
          meta: meta,
        ),
        meta: meta,
      );
    } catch (error) {
      return InferenceResult<InferenceResponse>.fail(
        code: errorCodeAudioOutputUnavailable,
        message: 'TTS synthesis failed to produce output artifact',
        details: error.toString(),
      );
    }
  }

  Future<void> _applyVoiceOptions(
    final InferenceVoiceOptions? voiceOptions,
  ) async {
    if (voiceOptions == null) {
      return;
    }

    if (voiceOptions.locale case final String locale
        when locale.trim().isNotEmpty) {
      await _driver.setLanguage(locale.trim());
    }

    if (voiceOptions.speechRate case final double speechRate) {
      await _driver.setSpeechRate(speechRate);
    }

    if (voiceOptions.pitch case final double pitch) {
      await _driver.setPitch(pitch);
    }

    final voiceMap = <String, String>{};

    if (voiceOptions.voiceId case final String voiceId
        when voiceId.trim().isNotEmpty) {
      voiceMap['name'] = voiceId.trim();
      voiceMap['identifier'] = voiceId.trim();
    }

    if (voiceOptions.locale case final String locale
        when locale.trim().isNotEmpty) {
      voiceMap['locale'] = locale.trim();
    }

    if (voiceOptions.providerExtras['voice'] case final Map rawVoiceMap) {
      for (final entry in rawVoiceMap.entries) {
        final key = entry.key.toString().trim();
        final value = entry.value.toString().trim();
        if (key.isEmpty || value.isEmpty) {
          continue;
        }
        voiceMap[key] = value;
      }
    }

    if (voiceMap.isNotEmpty) {
      await _driver.setVoice(voiceMap);
    }
  }

  _OutputSpec _resolveOutputSpec(final InferenceRequest request) {
    final metadataPath = request.metadata['output_file_path'];
    final metadataMime = request.metadata['output_mime_type'];

    if (metadataPath is String && metadataPath.trim().isNotEmpty) {
      final explicitPath = metadataPath.trim();
      return _OutputSpec(
        filePath: explicitPath,
        mimeType: metadataMime is String && metadataMime.trim().isNotEmpty
            ? metadataMime.trim()
            : _mimeTypeFromPath(explicitPath),
      );
    }

    final extension = _defaultExtension();
    final outputPath = p.join(
      request.workingDirectory,
      'tts_${_now().millisecondsSinceEpoch}$extension',
    );

    return _OutputSpec(
      filePath: outputPath,
      mimeType: _mimeTypeFromPath(outputPath),
    );
  }

  String _defaultExtension() {
    if (Platform.isIOS) {
      return '.caf';
    }
    return '.wav';
  }

  String _mimeTypeFromPath(final String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.caf')) return 'audio/x-caf';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    return 'audio/octet-stream';
  }

  static bool _defaultPlatformCheck() => Platform.isAndroid || Platform.isIOS;
}

class _OutputSpec {
  const _OutputSpec({required this.filePath, required this.mimeType});

  final String filePath;
  final String mimeType;
}
