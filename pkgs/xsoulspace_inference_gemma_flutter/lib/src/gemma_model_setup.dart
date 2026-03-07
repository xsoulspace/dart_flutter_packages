import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// Default model profile: FunctionGemma 270M .litertlm (desktop).
const String kDefaultGemmaModelProfileId = 'function_gemma_270m_litertlm';

/// Default download URL for FunctionGemma 270M .litertlm.
const String kDefaultGemmaModelUrl =
    'https://huggingface.co/sasha-denisov/function-gemma-270M-it/resolve/main/functiongemma-270M-it.litertlm';

/// Result of a model install (URL or file).
class GemmaModelInstallResult {
  const GemmaModelInstallResult({
    required this.success,
    this.modelId,
    this.errorCode,
    this.message,
    this.details,
  });

  final bool success;
  final String? modelId;
  final String? errorCode;
  final String? message;
  final Object? details;

  InferenceResult<String> toInferenceResult() {
    if (success && modelId != null) {
      return InferenceResult<String>.ok(modelId!);
    }
    return InferenceResult<String>.fail(
      code: errorCode ?? 'model_install_failed',
      message: message ?? 'Model installation failed',
      details: details,
    );
  }
}

/// Status of the Gemma model (readiness, install source).
class GemmaModelStatus {
  const GemmaModelStatus({
    required this.ready,
    this.modelId,
    this.installSource,
    this.errorCode,
    this.message,
  });

  final bool ready;
  final String? modelId;
  final String? installSource;
  final String? errorCode;
  final String? message;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'ready': ready,
        if (modelId != null) 'model_id': modelId,
        if (installSource != null) 'install_source': installSource,
        if (errorCode != null) 'error_code': errorCode,
        if (message != null) 'message': message,
      };
}

/// Model setup APIs: URL download, local file, status.
class GemmaModelSetup {
  GemmaModelSetup({
    this.defaultModelUrl = kDefaultGemmaModelUrl,
    this.defaultProfileId = kDefaultGemmaModelProfileId,
  });

  final String defaultModelUrl;
  final String defaultProfileId;

  /// Install model from [url]. Returns install result with modelId on success.
  Future<GemmaModelInstallResult> installFromUrl({
    required String url,
    void Function(int percent)? onProgress,
    String? profileId,
  }) async {
    try {
      final id = profileId ?? defaultProfileId;
      await FlutterGemma.installModel(modelType: ModelType.functionGemma)
          .fromNetwork(url.trim())
          .withProgress(onProgress ?? (_) {})
          .install();
      final ready = await FlutterGemma.hasActiveModel();
      return GemmaModelInstallResult(
        success: ready,
        modelId: ready ? id : null,
        message: ready ? null : 'Model installed but not active',
      );
    } on Exception catch (e) {
      return GemmaModelInstallResult(
        success: false,
        errorCode: 'engine_unavailable',
        message: e.toString(),
        details: e.toString(),
      );
    }
  }

  /// Install model from local file at [path].
  Future<GemmaModelInstallResult> installFromFile({
    required String path,
    String? profileId,
  }) async {
    try {
      final id = profileId ?? defaultProfileId;
      await FlutterGemma.installModel(modelType: ModelType.functionGemma)
          .fromFile(path.trim())
          .install();
      final ready = await FlutterGemma.hasActiveModel();
      return GemmaModelInstallResult(
        success: ready,
        modelId: ready ? id : null,
        message: ready ? null : 'Model installed but not active',
      );
    } on Exception catch (e) {
      return GemmaModelInstallResult(
        success: false,
        errorCode: 'engine_unavailable',
        message: e.toString(),
        details: e.toString(),
      );
    }
  }

  /// Report whether a model is ready and optional status details.
  Future<GemmaModelStatus> getStatus() async {
    try {
      final hasModel = await FlutterGemma.hasActiveModel();
      if (!hasModel) {
        return const GemmaModelStatus(
          ready: false,
          errorCode: 'model_missing',
          message: 'No Gemma model installed or active',
        );
      }
      final list = await FlutterGemma.listInstalledModels();
      final modelId = list.isNotEmpty ? list.first : defaultProfileId;
      return GemmaModelStatus(
        ready: true,
        modelId: modelId,
        installSource: 'flutter_gemma',
      );
    } on Exception catch (e) {
      return GemmaModelStatus(
        ready: false,
        errorCode: 'engine_unavailable',
        message: e.toString(),
      );
    }
  }
}
