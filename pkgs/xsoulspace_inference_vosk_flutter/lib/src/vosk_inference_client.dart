import 'dart:io';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_vosk_raw/xsoulspace_inference_vosk_raw.dart';

import 'vosk_availability_probe.dart';
import 'vosk_models.dart';
import 'vosk_native_runtime.dart';

typedef VoskTranscribeFn =
    Future<InferenceResult<InferenceResponse>> Function({
      required InferenceRequest request,
      required VoskModelConfig modelConfig,
      required VoskRuntimeConfig runtimeConfig,
    });

class VoskInferenceClient implements InferenceClient {
  VoskInferenceClient({
    this.modelConfig = const VoskModelConfig(),
    this.runtimeConfig = const VoskRuntimeConfig(),
    VoskAvailabilityProbe? availabilityProbe,
    VoskTranscribeFn? transcribe,
  }) : _availabilityProbe =
           availabilityProbe ??
           VoskAvailabilityProbe(
             runtimeConfig: runtimeConfig,
             modelPathResolver: () {
               final direct = modelConfig.modelPath.trim();
               return direct.isEmpty ? null : direct;
             },
           ),
       _transcribe = transcribe,
       _nativeBackend = NativeVoskBatchBackend(
         runtimeConfig: runtimeConfig,
         modelConfig: modelConfig,
       );

  final VoskModelConfig modelConfig;
  final VoskRuntimeConfig runtimeConfig;
  final VoskAvailabilityProbe _availabilityProbe;
  final VoskTranscribeFn? _transcribe;
  final NativeVoskBatchBackend _nativeBackend;

  String? resolveRuntimeLibraryPath() {
    return VoskRawLibraryLoader(
      runtimeConfig: VoskRawRuntimeConfig(
        libraryPath: runtimeConfig.libraryPath,
        librarySearchPaths: runtimeConfig.librarySearchPaths,
        modelDirectory: runtimeConfig.modelDirectory,
      ),
    ).resolveExistingLibraryPath();
  }

  String? resolveModelPath() {
    try {
      return resolveVoskRawModelPath(
        modelConfig: VoskRawModelConfig(
          modelPath: modelConfig.modelPath,
          providerExtras: modelConfig.providerExtras,
        ),
        runtimeConfig: VoskRawRuntimeConfig(
          libraryPath: runtimeConfig.libraryPath,
          librarySearchPaths: runtimeConfig.librarySearchPaths,
          modelDirectory: runtimeConfig.modelDirectory,
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
        message: 'Vosk runtime library was not found in any configured path',
        details: VoskRawLibraryLoader(
          runtimeConfig: VoskRawRuntimeConfig(
            libraryPath: runtimeConfig.libraryPath,
            librarySearchPaths: runtimeConfig.librarySearchPaths,
            modelDirectory: runtimeConfig.modelDirectory,
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
        message: 'Vosk model directory was not found',
        details: <String, dynamic>{
          'model_path': modelConfig.modelPath,
          'model_directory': runtimeConfig.modelDirectory,
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
    final directory = Directory(path);
    if (!directory.existsSync()) {
      return false;
    }
    await directory.delete(recursive: true);
    return true;
  }

  @override
  String get id => 'vosk_flutter';

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

    if (!isAvailable) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message: 'Vosk runtime is not available on this host',
      );
    }

    if (request.audioInput?.resolvedSource == InferenceAudioSource.microphone) {
      return InferenceResult<InferenceResponse>.fail(
        code: errorCodeTaskUnsupported,
        message: 'Microphone input requires VoskRealtimeSttSession',
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

    return _nativeBackend.transcribe(request);
  }
}
