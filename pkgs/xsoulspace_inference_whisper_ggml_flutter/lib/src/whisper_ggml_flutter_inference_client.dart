import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:whisper_ggml/whisper_ggml.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

typedef WhisperTranscribeFn =
    Future<WhisperTranscribeResponse> Function({
      required WhisperModel model,
      required String modelPath,
      required String audioPath,
      required String language,
    });

typedef WhisperModelPathResolver = Future<String> Function(WhisperModel model);
typedef WhisperModelDownloadFn = Future<String> Function(WhisperModel model);
typedef WhisperModelInitFn = Future<void> Function(WhisperModel model);

class WhisperGgmlFlutterInferenceClient implements InferenceClient {
  WhisperGgmlFlutterInferenceClient({
    final WhisperModel initialModel = WhisperModel.base,
    final WhisperController? whisperController,
    final WhisperModelPathResolver? resolveModelPath,
    final WhisperModelDownloadFn? downloadModel,
    final WhisperModelInitFn? initModel,
    final WhisperTranscribeFn? transcribe,
    this.defaultLanguage = 'en',
  }) : _selectedModel = initialModel,
       _controller = whisperController ?? WhisperController(),
       _resolveModelPathOverride = resolveModelPath,
       _downloadModelOverride = downloadModel,
       _initModelOverride = initModel,
       _transcribeOverride = transcribe;

  final WhisperController _controller;
  final WhisperModelPathResolver? _resolveModelPathOverride;
  final WhisperModelDownloadFn? _downloadModelOverride;
  final WhisperModelInitFn? _initModelOverride;
  final WhisperTranscribeFn? _transcribeOverride;

  final String defaultLanguage;
  WhisperModel _selectedModel;

  @override
  String get id => 'whisper_ggml_flutter';

  @override
  bool get isAvailable =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  @override
  Set<InferenceTask> get supportedTasks => const <InferenceTask>{
    InferenceTask.speechToText,
  };

  WhisperModel get selectedModel => _selectedModel;

  Future<void> selectModel(final WhisperModel model) async {
    await _runInitModel(model);
    _selectedModel = model;
  }

  Future<bool> isModelInstalled(final WhisperModel model) async {
    final modelPath = await _runResolveModelPath(model);
    return File(modelPath).existsSync();
  }

  Future<List<WhisperModel>> getInstalledModels() async {
    final installed = <WhisperModel>[];
    for (final model in WhisperModel.values) {
      if (await isModelInstalled(model)) {
        installed.add(model);
      }
    }
    return installed;
  }

  Future<String> downloadModel([final WhisperModel? model]) async {
    final targetModel = model ?? _selectedModel;
    return _runDownloadModel(targetModel);
  }

  Future<bool> deleteModel([final WhisperModel? model]) async {
    final targetModel = model ?? _selectedModel;
    final modelPath = await _runResolveModelPath(targetModel);
    final file = File(modelPath);
    if (!file.existsSync()) {
      return false;
    }
    await file.delete();
    return true;
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
        message: '$id is supported only on Android, iOS, and macOS',
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

    final model = _selectedModel;

    try {
      await _runInitModel(model);
    } catch (error) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message: 'Failed to initialize Whisper model',
        details: error.toString(),
      );
    }

    final modelPath = await _runResolveModelPath(model);
    if (!File(modelPath).existsSync()) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message:
            'Whisper model is not installed. Download and initialize it first.',
        details: <String, dynamic>{
          'model': model.modelName,
          'model_path': modelPath,
        },
      );
    }

    final audioPreparation = await _prepareAudioInput(request.audioInput!);
    if (!audioPreparation.success || audioPreparation.data == null) {
      return InferenceResult<InferenceResponse>.fail(
        code: audioPreparation.error?.code ?? errorCodeAudioInputInvalid,
        message:
            audioPreparation.error?.message ?? 'Failed to prepare audio input',
        details: audioPreparation.error?.details,
      );
    }

    final preparedAudio = audioPreparation.data!;
    try {
      final language = _resolveLanguage(request);
      final transcription = await _runTranscribe(
        model: model,
        modelPath: modelPath,
        audioPath: preparedAudio.path,
        language: language,
      );

      final transcript = transcription.text;
      final normalizedTranscript = normalizeTranscript(transcript);
      final segments =
          (transcription.segments ?? const <WhisperTranscribeSegment>[])
              .map(
                (final segment) => InferenceSpeechSegment(
                  text: segment.text,
                  startMs: segment.fromTs.inMilliseconds,
                  endMs: segment.toTs.inMilliseconds,
                ),
              )
              .toList(growable: false);

      final meta = <String, dynamic>{
        'provider': id,
        'model': model.modelName,
        'language': language,
        'segment_count': segments.length,
      };

      return InferenceResult<InferenceResponse>.ok(
        InferenceResponse(
          task: InferenceTask.speechToText,
          output: const <String, dynamic>{},
          transcript: transcript,
          normalizedTranscript: normalizedTranscript,
          segments: segments,
          meta: meta,
        ),
        meta: meta,
      );
    } catch (error) {
      return InferenceResult<InferenceResponse>.fail(
        code: errorCodeAudioInputInvalid,
        message: 'Whisper transcription failed for provided audio input',
        details: error.toString(),
      );
    } finally {
      await preparedAudio.cleanup();
    }
  }

  String _resolveLanguage(final InferenceRequest request) {
    final rawLanguage = request.metadata['language'];
    if (rawLanguage is String && rawLanguage.trim().isNotEmpty) {
      return rawLanguage.trim();
    }
    return defaultLanguage;
  }

  Future<String> _runResolveModelPath(final WhisperModel model) async {
    if (_resolveModelPathOverride != null) {
      return _resolveModelPathOverride(model);
    }
    return _controller.getPath(model);
  }

  Future<String> _runDownloadModel(final WhisperModel model) async {
    if (_downloadModelOverride != null) {
      return _downloadModelOverride(model);
    }
    return _controller.downloadModel(model);
  }

  Future<void> _runInitModel(final WhisperModel model) async {
    if (_initModelOverride != null) {
      await _initModelOverride(model);
      return;
    }
    await _controller.initModel(model);
  }

  Future<WhisperTranscribeResponse> _runTranscribe({
    required final WhisperModel model,
    required final String modelPath,
    required final String audioPath,
    required final String language,
  }) async {
    if (_transcribeOverride != null) {
      return _transcribeOverride(
        model: model,
        modelPath: modelPath,
        audioPath: audioPath,
        language: language,
      );
    }

    final whisper = Whisper(model: model);
    return whisper.transcribe(
      transcribeRequest: TranscribeRequest(
        audio: audioPath,
        language: language,
        isNoTimestamps: false,
        isRealtime: false,
      ),
      modelPath: modelPath,
    );
  }

  Future<InferenceResult<_PreparedAudio>> _prepareAudioInput(
    final InferenceAudioInput audioInput,
  ) async {
    final filePath = audioInput.filePath?.trim() ?? '';
    if (filePath.isNotEmpty) {
      final file = File(filePath);
      if (!file.existsSync()) {
        return InferenceResult<_PreparedAudio>.fail(
          code: errorCodeAudioInputInvalid,
          message: 'Audio file does not exist at provided path',
          details: <String, dynamic>{'file_path': filePath},
        );
      }
      return InferenceResult<_PreparedAudio>.ok(
        _PreparedAudio(path: file.path),
      );
    }

    final bytes = audioInput.bytes;
    if (bytes == null || bytes.isEmpty) {
      return InferenceResult<_PreparedAudio>.fail(
        code: errorCodeAudioInputInvalid,
        message: 'Audio input bytes are empty',
      );
    }

    final tempDir = await Directory.systemTemp.createTemp(
      'xsoulspace_whisper_audio_',
    );
    final extension = _extensionForMimeType(audioInput.mimeType);
    final tempFile = File(p.join(tempDir.path, 'input$extension'));
    await tempFile.writeAsBytes(bytes, flush: true);

    return InferenceResult<_PreparedAudio>.ok(
      _PreparedAudio(path: tempFile.path, cleanupDirectory: tempDir),
    );
  }

  String _extensionForMimeType(final String mimeType) {
    final normalized = mimeType.toLowerCase().trim();
    if (normalized.contains('wav')) {
      return '.wav';
    }
    if (normalized.contains('mpeg') || normalized.contains('mp3')) {
      return '.mp3';
    }
    if (normalized.contains('m4a') || normalized.contains('mp4')) {
      return '.m4a';
    }
    if (normalized.contains('aac')) {
      return '.aac';
    }
    return '.audio';
  }
}

class _PreparedAudio {
  _PreparedAudio({required this.path, this.cleanupDirectory});

  final String path;
  final Directory? cleanupDirectory;

  Future<void> cleanup() async {
    if (cleanupDirectory == null) {
      return;
    }
    if (!cleanupDirectory!.existsSync()) {
      return;
    }
    try {
      await cleanupDirectory!.delete(recursive: true);
    } catch (_) {
      // best-effort cleanup only
    }
  }
}
