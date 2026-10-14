import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'gemma_model_catalog.dart';

/// Host platform detection for catalog selection.
GemmaPlatform _currentPlatform() {
  if (kIsWeb) return GemmaPlatform.web;
  return switch (Platform.operatingSystem) {
    'android' => GemmaPlatform.android,
    'ios' => GemmaPlatform.ios,
    'macos' => GemmaPlatform.macos,
    'windows' => GemmaPlatform.windows,
    'linux' => GemmaPlatform.linux,
    _ => GemmaPlatform.android,
  };
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

/// Model setup: purpose-driven provisioning with constraint checks, plus
/// explicit URL/file installs for advanced use.
class GemmaModelSetup {
  GemmaModelSetup({this.catalog = defaultCatalog});

  final List<GemmaModelEntry> catalog;

  CancelToken? _activeCancelToken;
  final _progressController = StreamController<ProvisionProgress>.broadcast();
  ProvisionProgress _lastProgress = const ProvisionProgress(
    phase: ProvisionPhase.idle,
  );

  /// Progress stream for UI. Broadcast — late listeners get nothing; use
  /// [lastProgress] for current state.
  Stream<ProvisionProgress> get provisionProgress => _progressController.stream;

  /// Latest known progress snapshot.
  ProvisionProgress get lastProgress => _lastProgress;

  void _emit(final ProvisionProgress progress) {
    _lastProgress = progress;
    if (!_progressController.isClosed) {
      _progressController.add(progress);
    }
  }

  /// Ensures a model serving [purpose] is installed and active, honoring
  /// [constraints]. Idempotent: returns immediately when a suitable model is
  /// already active.
  ///
  /// [platform] selects the artifact variant; defaults to the current host
  /// platform. Only Android and macOS are validated targets today.
  Future<InferenceResult<ModelHandle>> ensureReady(
    final GemmaPurpose purpose, {
    final ProvisionConstraints constraints = const ProvisionConstraints(),
    final GemmaPlatform? platform,
  }) async {
    final target = platform ?? _currentPlatform();
    final entry = GemmaModelEntry.bestFor(
      purpose,
      platform: target,
      catalog: catalog,
    );
    if (entry == null) {
      return InferenceResult<ModelHandle>.fail(
        code: 'model_not_found',
        message:
            'No catalog entry serves purpose "${purpose.name}" on '
            '${target.name}',
        details: <String, dynamic>{
          'purpose': purpose.value,
          'platform': target.name,
          'covered_platforms': catalog
              .expand((final e) => e.platforms)
              .map((final p) => p.name)
              .toSet()
              .toList(),
        },
      );
    }

    try {
      final status = await getStatus();
      if (status.ready && status.modelId == entry.id) {
        _emit(ProvisionProgress(phase: ProvisionPhase.ready));
        return InferenceResult<ModelHandle>.ok(ModelHandle(entry.id));
      }
      // A different model is active — replace only when it doesn't serve the
      // requested purpose. Same-model re-activation is a no-op above.
      if (constraints.requireUserConsent && !constraints.userConsentGranted) {
        return InferenceResult<ModelHandle>.fail(
          code: 'user_consent_required',
          message:
              'Downloading ${entry.id} (~${entry.sizeBytes ~/ 1000000} MB) '
              'requires user consent',
          details: <String, dynamic>{
            'model_id': entry.id,
            'size_bytes': entry.sizeBytes,
          },
        );
      }

      final networkAllowed = constraints.isNetworkAllowed?.call() ?? true;
      if (!networkAllowed) {
        return InferenceResult<ModelHandle>.fail(
          code: 'network_not_allowed',
          message: 'Network policy blocks downloading ${entry.id}',
        );
      }

      final maxBytes = constraints.maxDownloadBytes;
      if (maxBytes != null && entry.sizeBytes > maxBytes) {
        return InferenceResult<ModelHandle>.fail(
          code: 'model_too_large',
          message:
              '${entry.id} (${entry.sizeBytes} bytes) exceeds '
              'maxDownloadBytes ($maxBytes)',
        );
      }

      _emit(
        ProvisionProgress(
          phase: ProvisionPhase.checking,
          totalBytes: entry.sizeBytes,
          message: 'Checking ${entry.id}',
        ),
      );

      final installResult = await _installEntry(entry);
      return installResult;
    } on Exception catch (e) {
      _emit(
        ProvisionProgress(phase: ProvisionPhase.failed, message: e.toString()),
      );
      return InferenceResult<ModelHandle>.fail(
        code: 'provision_failed',
        message: 'Gemma provisioning failed',
        details: e.toString(),
      );
    }
  }

  /// Installs and activates [entry] with progress + cancellation support.
  Future<InferenceResult<ModelHandle>> _installEntry(
    final GemmaModelEntry entry,
  ) async {
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;
    _emit(
      ProvisionProgress(
        phase: ProvisionPhase.downloading,
        percent: 0,
        downloadedBytes: 0,
        totalBytes: entry.sizeBytes,
        message: 'Downloading ${entry.id}',
      ),
    );
    try {
      await FlutterGemma.installModel(modelType: entry.modelType)
          .fromNetwork(entry.url)
          .withProgress(
            (final percent) => _emit(
              ProvisionProgress(
                phase: ProvisionPhase.downloading,
                percent: percent,
                downloadedBytes: entry.sizeBytes * percent ~/ 100,
                totalBytes: entry.sizeBytes,
              ),
            ),
          )
          .withCancelToken(cancelToken)
          .install();

      _emit(
        ProvisionProgress(
          phase: ProvisionPhase.loading,
          percent: 100,
          totalBytes: entry.sizeBytes,
          message: 'Activating ${entry.id}',
        ),
      );

      final ready = FlutterGemma.hasActiveModel();
      if (!ready) {
        return InferenceResult<ModelHandle>.fail(
          code: 'model_install_failed',
          message: 'Installed but not active: ${entry.id}',
        );
      }
      _emit(ProvisionProgress(phase: ProvisionPhase.ready, percent: 100));
      return InferenceResult<ModelHandle>.ok(ModelHandle(entry.id));
    } on Exception catch (e) {
      _emit(
        ProvisionProgress(phase: ProvisionPhase.failed, message: e.toString()),
      );
      return InferenceResult<ModelHandle>.fail(
        code: 'model_install_failed',
        message: 'Failed to install ${entry.id}',
        details: e.toString(),
      );
    } finally {
      _activeCancelToken = null;
    }
  }

  /// Cancels an in-flight download. No-op when idle.
  void cancel() {
    _activeCancelToken?.cancel('Cancelled by caller');
  }

  /// Install model from an arbitrary URL (advanced use — prefer
  /// [ensureReady] for production).
  Future<InferenceResult<ModelHandle>> installFromUrl({
    required final String url,
    required final ModelType modelType,
    final void Function(int percent)? onProgress,
  }) async {
    try {
      await FlutterGemma.installModel(
        modelType: modelType,
      ).fromNetwork(url.trim()).withProgress(onProgress ?? (_) {}).install();
      final ready = FlutterGemma.hasActiveModel();
      if (!ready) {
        return InferenceResult<ModelHandle>.fail(
          code: 'model_install_failed',
          message: 'Model installed but not active',
        );
      }
      return InferenceResult<ModelHandle>.ok(ModelHandle(url));
    } on Exception catch (e) {
      return InferenceResult<ModelHandle>.fail(
        code: 'model_install_failed',
        message: e.toString(),
        details: e.toString(),
      );
    }
  }

  /// Install model from local file at [path] (advanced use).
  Future<InferenceResult<ModelHandle>> installFromFile({
    required final String path,
    required final ModelType modelType,
  }) async {
    try {
      await FlutterGemma.installModel(
        modelType: modelType,
      ).fromFile(path.trim()).install();
      final ready = FlutterGemma.hasActiveModel();
      if (!ready) {
        return InferenceResult<ModelHandle>.fail(
          code: 'model_install_failed',
          message: 'Model installed but not active',
        );
      }
      return InferenceResult<ModelHandle>.ok(ModelHandle(path));
    } on Exception catch (e) {
      return InferenceResult<ModelHandle>.fail(
        code: 'model_install_failed',
        message: e.toString(),
        details: e.toString(),
      );
    }
  }

  /// Report whether a model is ready and optional status details.
  ///
  /// Note: flutter_gemma persists only the active spec's name, so we match
  /// against catalog ids derived from the URL filename.
  Future<GemmaModelStatus> getStatus() async {
    try {
      final hasModel = FlutterGemma.hasActiveModel();
      if (!hasModel) {
        return const GemmaModelStatus(
          ready: false,
          errorCode: 'model_missing',
          message: 'No Gemma model installed or active',
        );
      }
      final list = await FlutterGemma.listInstalledModels();
      final activeId = list.isNotEmpty ? list.first : null;
      return GemmaModelStatus(
        ready: true,
        modelId: activeId,
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

  Future<void> dispose() => _progressController.close();
}
