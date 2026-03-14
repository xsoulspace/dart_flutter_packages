import 'dart:io';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_whisper_cpp_raw/xsoulspace_inference_whisper_cpp_raw.dart';

import 'whisper_cpp_availability_probe.dart';
import 'whisper_cpp_models.dart';
import 'whisper_cpp_native_runtime.dart';

typedef WhisperCppTranscribeFn =
    Future<InferenceResult<InferenceResponse>> Function({
      required InferenceRequest request,
      required WhisperCppModelConfig modelConfig,
      required WhisperCppRuntimeConfig runtimeConfig,
    });

class WhisperCppInferenceClient implements InferenceClient {
  WhisperCppInferenceClient({
    this.modelConfig = const WhisperCppModelConfig(),
    this.runtimeConfig = const WhisperCppRuntimeConfig(),
    WhisperCppAvailabilityProbe? availabilityProbe,
    WhisperCppTranscribeFn? transcribe,
  }) : _availabilityProbe =
           availabilityProbe ??
           WhisperCppAvailabilityProbe(
             runtimeConfig: runtimeConfig,
             modelPathResolver: () {
               final direct = modelConfig.modelPath.trim();
               return direct.isEmpty ? null : direct;
             },
           ),
       _transcribe = transcribe,
       _nativeBackend = NativeWhisperCppBatchBackend(
         runtimeConfig: runtimeConfig,
         modelConfig: modelConfig,
       );

  final WhisperCppModelConfig modelConfig;
  final WhisperCppRuntimeConfig runtimeConfig;
  final WhisperCppAvailabilityProbe _availabilityProbe;
  final WhisperCppTranscribeFn? _transcribe;
  final NativeWhisperCppBatchBackend _nativeBackend;

  String? resolveRuntimeLibraryPath() {
    return WhisperCppRawLibraryLoader(
      runtimeConfig: WhisperCppRawRuntimeConfig(
        libraryPath: runtimeConfig.libraryPath,
        librarySearchPaths: runtimeConfig.librarySearchPaths,
        modelsDirectory: runtimeConfig.modelsDirectory,
      ),
    ).resolveExistingLibraryPath();
  }

  String? resolveModelPath() {
    try {
      return resolveWhisperCppRawModelPath(
        modelConfig: WhisperCppRawModelConfig(
          preset: WhisperCppRawModelPreset.tinyEn,
          modelPath: modelConfig.modelPath,
          providerExtras: modelConfig.providerExtras,
        ),
        runtimeConfig: WhisperCppRawRuntimeConfig(
          libraryPath: runtimeConfig.libraryPath,
          librarySearchPaths: runtimeConfig.librarySearchPaths,
          modelsDirectory: runtimeConfig.modelsDirectory,
        ),
      );
    } on Object {
      return null;
    }
  }

  Future<InferenceResult<String>> ensureRuntimeReady() async {
    final path = resolveRuntimeLibraryPath();
    if (path == null) {
      return InferenceResult<String>.fail(
        code: 'engine_unavailable',
        message:
            'whisper.cpp runtime library was not found in any configured path',
        details: WhisperCppRawLibraryLoader(
          runtimeConfig: WhisperCppRawRuntimeConfig(
            libraryPath: runtimeConfig.libraryPath,
            librarySearchPaths: runtimeConfig.librarySearchPaths,
            modelsDirectory: runtimeConfig.modelsDirectory,
          ),
        ).candidateLibraryPaths(),
      );
    }
    return InferenceResult<String>.ok(path);
  }

  Future<InferenceResult<String>> ensureModelInstalled() async {
    final path = resolveModelPath();
    if (path == null) {
      return InferenceResult<String>.fail(
        code: 'engine_unavailable',
        message: 'whisper.cpp model file was not found',
        details: <String, dynamic>{
          'model_path': modelConfig.modelPath,
          'models_directory': runtimeConfig.modelsDirectory,
        },
      );
    }
    return InferenceResult<String>.ok(path);
  }

  Future<List<String>> getInstalledModels() async {
    final path = resolveModelPath();
    return path == null ? const <String>[] : <String>[path];
  }

  Future<bool> deleteInstalledModel() async {
    final path = resolveModelPath();
    if (path == null) {
      return false;
    }
    final file = File(path);
    if (!file.existsSync()) {
      return false;
    }
    await file.delete();
    return true;
  }

  @override
  String get id => 'whisper_cpp_flutter';

  @override
  bool get isAvailable => _transcribe != null
      ? _availabilityProbe.isPlatformSupported()
      : _availabilityProbe.canLoad(runtimeConfig);

  @override
  Set<InferenceTask> get supportedTasks => const <InferenceTask>{
    InferenceTask.speechToText,
  };

  @override
  Future<bool> refreshAvailability() async => isAvailable;

  @override
  void resetAvailabilityCache() {}

  @override
  Future<InferenceResult<InferenceResponse>> infer(
    final InferenceRequest request,
  ) async {
    if (!supportedTasks.contains(request.task)) {
      return InferenceResult<InferenceResponse>.fail(
        code: errorCodeTaskUnsupported,
        message: 'Task ${request.task.name} is not supported by $id',
      );
    }

    final validation = validateInferenceRequest(request);
    if (!validation.success) {
      return InferenceResult<InferenceResponse>.fail(
        code: validation.error?.code ?? 'request_invalid',
        message: validation.error?.message ?? 'Inference request is invalid',
        details: validation.error?.details,
      );
    }

    if (request.audioInput?.resolvedSource == InferenceAudioSource.microphone) {
      return InferenceResult<InferenceResponse>.fail(
        code: errorCodeTaskUnsupported,
        message: 'Microphone input requires WhisperCppRealtimeSttSession',
      );
    }

    final transcribe = _transcribe;
    if (transcribe != null) {
      return transcribe(
        request: request,
        modelConfig: modelConfig,
        runtimeConfig: runtimeConfig,
      );
    }

    if (!isAvailable) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message: 'whisper.cpp runtime is not available on this host',
      );
    }

    return _nativeBackend.transcribe(request);
  }
}
