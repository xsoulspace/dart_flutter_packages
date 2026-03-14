import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_vosk_raw/xsoulspace_inference_vosk_raw.dart';

import 'vosk_models.dart';

class VoskAvailabilityProbe implements InferenceReadinessProbe {
  VoskAvailabilityProbe({
    this.runtimeConfig = const VoskRuntimeConfig(),
    this.modelPathResolver,
    this.platformProbe = VoskRawLibraryLoader.isSupportedPlatform,
    this.loadProbe,
  });

  final VoskRuntimeConfig runtimeConfig;
  final String? Function()? modelPathResolver;
  final bool Function() platformProbe;
  final bool Function(VoskRuntimeConfig runtimeConfig)? loadProbe;

  bool isPlatformSupported() => platformProbe();

  bool isConfigured(final VoskRuntimeConfig runtimeConfig) =>
      (runtimeConfig.libraryPath ?? '').trim().isNotEmpty ||
      runtimeConfig.librarySearchPaths.isNotEmpty ||
      runtimeConfig.ownsRuntimeResolution;

  bool canLoad(final VoskRuntimeConfig runtimeConfig) {
    if (!isPlatformSupported() || !isConfigured(runtimeConfig)) {
      return false;
    }
    final override = loadProbe;
    if (override != null) {
      return override(runtimeConfig);
    }
    try {
      VoskRawBindings.load(
        VoskRawRuntimeConfig(
          libraryPath: runtimeConfig.libraryPath,
          librarySearchPaths: runtimeConfig.librarySearchPaths,
          modelDirectory: runtimeConfig.modelDirectory,
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
    final modelPath = modelPathResolver?.call();

    if (!isPlatformSupported()) {
      issues.add(
        const InferenceReadinessIssue(
          code: errorCodeTaskUnsupported,
          message: 'Vosk is unsupported on this host',
        ),
      );
    }
    if (!canLoad(runtimeConfig)) {
      issues.add(
        const InferenceReadinessIssue(
          code: 'runtime_missing',
          message: 'Vosk runtime library is unavailable',
          remediation: 'Configure libraryPath or librarySearchPaths.',
        ),
      );
    }
    if ((modelPath ?? '').trim().isEmpty) {
      issues.add(
        const InferenceReadinessIssue(
          code: 'model_missing',
          message: 'Vosk model directory is unavailable',
          remediation: 'Configure modelDirectory or modelPath.',
        ),
      );
    }

    return InferenceReadinessSnapshot(
      state: issues.isEmpty
          ? InferenceReadinessState.ready
          : InferenceReadinessState.unavailable,
      summary: issues.isEmpty ? 'Vosk is ready' : issues.first.message,
      issues: issues,
      metadata: <String, dynamic>{
        'provider': 'vosk',
        'runtime_configured': isConfigured(runtimeConfig),
        if (modelPath != null) 'model_path': modelPath,
      },
    );
  }
}
