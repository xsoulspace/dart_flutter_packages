import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_whisper_cpp_raw/xsoulspace_inference_whisper_cpp_raw.dart';

import 'whisper_cpp_models.dart';

class WhisperCppAvailabilityProbe implements InferenceReadinessProbe {
  WhisperCppAvailabilityProbe({
    this.runtimeConfig = const WhisperCppRuntimeConfig(),
    this.modelPathResolver,
    this.platformProbe = WhisperCppRawLibraryLoader.isSupportedPlatform,
    this.loadProbe,
  });

  final WhisperCppRuntimeConfig runtimeConfig;
  final String? Function()? modelPathResolver;
  final bool Function() platformProbe;
  final bool Function(WhisperCppRuntimeConfig runtimeConfig)? loadProbe;

  bool isPlatformSupported() => platformProbe();

  bool isConfigured(final WhisperCppRuntimeConfig runtimeConfig) =>
      (runtimeConfig.libraryPath ?? '').trim().isNotEmpty ||
      runtimeConfig.librarySearchPaths.isNotEmpty ||
      runtimeConfig.ownsRuntimeResolution;

  bool canLoad(final WhisperCppRuntimeConfig runtimeConfig) {
    if (!isPlatformSupported() || !isConfigured(runtimeConfig)) {
      return false;
    }
    final override = loadProbe;
    if (override != null) {
      return override(runtimeConfig);
    }
    try {
      WhisperCppRawBindings.load(
        WhisperCppRawRuntimeConfig(
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
    final modelPath = modelPathResolver?.call();

    if (!isPlatformSupported()) {
      issues.add(
        const InferenceReadinessIssue(
          code: errorCodeTaskUnsupported,
          message: 'whisper.cpp is unsupported on this host',
        ),
      );
    }
    if (!canLoad(runtimeConfig)) {
      issues.add(
        const InferenceReadinessIssue(
          code: 'runtime_missing',
          message: 'whisper.cpp runtime library is unavailable',
          remediation: 'Configure libraryPath or librarySearchPaths.',
        ),
      );
    }
    if ((modelPath ?? '').trim().isEmpty) {
      issues.add(
        const InferenceReadinessIssue(
          code: 'model_missing',
          message: 'whisper.cpp model file is unavailable',
          remediation: 'Configure modelsDirectory or modelPath.',
        ),
      );
    }

    return InferenceReadinessSnapshot(
      state: issues.isEmpty
          ? InferenceReadinessState.ready
          : InferenceReadinessState.unavailable,
      summary: issues.isEmpty ? 'whisper.cpp is ready' : issues.first.message,
      issues: issues,
      metadata: <String, dynamic>{
        'provider': 'whisper_cpp',
        'runtime_configured': isConfigured(runtimeConfig),
        'model_path': ?modelPath,
      },
    );
  }
}
