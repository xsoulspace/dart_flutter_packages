import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_sherpa_onnx_raw/xsoulspace_inference_sherpa_onnx_raw.dart';

import 'sherpa_onnx_models.dart';

class SherpaOnnxAvailabilityProbe implements InferenceReadinessProbe {
  SherpaOnnxAvailabilityProbe({
    this.runtimeConfig = const SherpaOnnxRuntimeConfig(),
    this.modelPathResolver,
    this.platformProbe = SherpaOnnxRawLibraryLoader.isSupportedPlatform,
    this.loadProbe,
  });

  final SherpaOnnxRuntimeConfig runtimeConfig;
  final String? Function()? modelPathResolver;
  final bool Function() platformProbe;
  final bool Function(SherpaOnnxRuntimeConfig runtimeConfig)? loadProbe;

  bool isPlatformSupported() => platformProbe();

  bool isConfigured(final SherpaOnnxRuntimeConfig runtimeConfig) =>
      (runtimeConfig.libraryPath ?? '').trim().isNotEmpty ||
      runtimeConfig.librarySearchPaths.isNotEmpty ||
      runtimeConfig.ownsRuntimeResolution;

  bool canLoad(final SherpaOnnxRuntimeConfig runtimeConfig) {
    if (!isPlatformSupported() || !isConfigured(runtimeConfig)) {
      return false;
    }
    final override = loadProbe;
    if (override != null) {
      return override(runtimeConfig);
    }
    try {
      SherpaOnnxRawBindings.load(
        SherpaOnnxRawRuntimeConfig(
          libraryPath: runtimeConfig.libraryPath,
          librarySearchPaths: runtimeConfig.librarySearchPaths,
          modelsDirectory: runtimeConfig.modelsDirectory,
        ),
      );
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<InferenceReadinessSnapshot> probe() async {
    final issues = <InferenceReadinessIssue>[];
    final modelRoot = modelPathResolver?.call();

    if (!isPlatformSupported()) {
      issues.add(
        const InferenceReadinessIssue(
          code: errorCodeTaskUnsupported,
          message: 'Sherpa-ONNX is unsupported on this host',
        ),
      );
    }
    if (!canLoad(runtimeConfig)) {
      issues.add(
        const InferenceReadinessIssue(
          code: 'runtime_missing',
          message: 'Sherpa-ONNX runtime library is unavailable',
          remediation: 'Configure libraryPath or librarySearchPaths.',
        ),
      );
    }
    if ((modelRoot ?? '').trim().isEmpty) {
      issues.add(
        const InferenceReadinessIssue(
          code: 'model_missing',
          message: 'Sherpa-ONNX model files are unavailable',
          remediation: 'Configure modelsDirectory and model file paths.',
        ),
      );
    }

    return InferenceReadinessSnapshot(
      state: issues.isEmpty
          ? InferenceReadinessState.ready
          : InferenceReadinessState.unavailable,
      summary: issues.isEmpty ? 'Sherpa-ONNX is ready' : issues.first.message,
      issues: issues,
      metadata: <String, dynamic>{
        'provider': 'sherpa_onnx',
        'runtime_configured': isConfigured(runtimeConfig),
        'model_root': ?modelRoot,
      },
    );
  }
}
