import 'dart:io';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_sherpa_onnx_raw/xsoulspace_inference_sherpa_onnx_raw.dart';

import 'sherpa_onnx_availability_probe.dart';
import 'sherpa_onnx_models.dart';
import 'sherpa_onnx_native_runtime.dart';

typedef SherpaOnnxTranscribeFn =
    Future<InferenceResult<InferenceResponse>> Function({
      required InferenceRequest request,
      required SherpaOnnxModelConfig modelConfig,
      required SherpaOnnxRuntimeConfig runtimeConfig,
    });

class SherpaOnnxInferenceClient implements InferenceClient {
  SherpaOnnxInferenceClient({
    this.modelConfig =
        const SherpaOnnxModelConfig.streamingZipformerEn20230626(),
    this.runtimeConfig = const SherpaOnnxRuntimeConfig(),
    SherpaOnnxAvailabilityProbe? availabilityProbe,
    SherpaOnnxTranscribeFn? transcribe,
  }) : _availabilityProbe =
           availabilityProbe ??
           SherpaOnnxAvailabilityProbe(
             runtimeConfig: runtimeConfig,
             modelPathResolver: () => runtimeConfig.modelsDirectory,
           ),
       _transcribe = transcribe,
       _nativeBackend = NativeSherpaOnnxBatchBackend(
         runtimeConfig: runtimeConfig,
         modelConfig: modelConfig,
       );

  final SherpaOnnxModelConfig modelConfig;
  final SherpaOnnxRuntimeConfig runtimeConfig;
  final SherpaOnnxAvailabilityProbe _availabilityProbe;
  final SherpaOnnxTranscribeFn? _transcribe;
  final NativeSherpaOnnxBatchBackend _nativeBackend;

  String? resolveRuntimeLibraryPath() {
    return SherpaOnnxRawLibraryLoader(
      runtimeConfig: SherpaOnnxRawRuntimeConfig(
        libraryPath: runtimeConfig.libraryPath,
        librarySearchPaths: runtimeConfig.librarySearchPaths,
        modelsDirectory: runtimeConfig.modelsDirectory,
      ),
    ).resolveExistingLibraryPath();
  }

  String? resolveModelPath() {
    return resolveSherpaOnnxRawModelRoot(
      modelConfig: SherpaOnnxRawModelConfig(
        preset: SherpaOnnxRawPreset.streamingZipformerEn20230626,
        encoderPath: modelConfig.encoderPath,
        decoderPath: modelConfig.decoderPath,
        joinerPath: modelConfig.joinerPath,
        tokensPath: modelConfig.tokensPath,
        providerExtras: modelConfig.providerExtras,
      ),
      runtimeConfig: SherpaOnnxRawRuntimeConfig(
        libraryPath: runtimeConfig.libraryPath,
        librarySearchPaths: runtimeConfig.librarySearchPaths,
        modelsDirectory: runtimeConfig.modelsDirectory,
      ),
    );
  }

  Future<InferenceResult<String>> ensureRuntimeReady() async {
    final path = resolveRuntimeLibraryPath();
    if (path == null) {
      return InferenceResult<String>.fail(
        code: 'engine_unavailable',
        message:
            'Sherpa-ONNX runtime library was not found in any configured path',
        details: SherpaOnnxRawLibraryLoader(
          runtimeConfig: SherpaOnnxRawRuntimeConfig(
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
        message: 'Sherpa-ONNX model files were not fully resolved',
        details: <String, dynamic>{
          'encoder': modelConfig.encoderPath,
          'decoder': modelConfig.decoderPath,
          'joiner': modelConfig.joinerPath,
          'tokens': modelConfig.tokensPath,
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
    final directory = Directory(path);
    if (!directory.existsSync()) {
      return false;
    }
    await directory.delete(recursive: true);
    return true;
  }

  @override
  String get id => 'sherpa_onnx_flutter';

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
        message: 'Microphone input requires SherpaOnnxRealtimeSttSession',
      );
    }

    if (!isAvailable) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message: 'Sherpa-ONNX runtime is not available on this host',
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
