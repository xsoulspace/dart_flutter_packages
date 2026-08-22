import 'dart:async';

import 'inference_result.dart';

/// Why an app needs a model. Providers map purposes to concrete model
/// artifacts via their own catalogs; core stays provider-agnostic.
extension type const ModelPurpose(String value) {}

/// Constraints an app places on model provisioning.
///
/// All limits are opt-in: `null` means "no limit". Defaults are conservative
/// so an implicit `ensureReady` call can never silently download gigabytes
/// over cellular data.
class ProvisionConstraints {
  const ProvisionConstraints({
    this.maxDownloadBytes,
    this.storageQuotaBytes,
    this.requireUserConsent = true,
    this.userConsentGranted = false,
    this.isNetworkAllowed,
  });

  /// Reject models larger than this before downloading.
  final int? maxDownloadBytes;

  /// Reject models that would not fit in the remaining storage budget.
  final int? storageQuotaBytes;

  /// When true (default), provisioning fails with `user_consent_required`
  /// unless [userConsentGranted] is also true. Apps surface a dialog and
  /// retry with consent granted.
  final bool requireUserConsent;

  /// Set to true after the user accepted the download.
  final bool userConsentGranted;

  /// Optional network gate (e.g. Wi-Fi-only policy). Return false to block
  /// downloads. When null, the provider assumes the network is allowed.
  final bool Function()? isNetworkAllowed;

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (maxDownloadBytes != null) 'max_download_bytes': maxDownloadBytes,
    if (storageQuotaBytes != null) 'storage_quota_bytes': storageQuotaBytes,
    'require_user_consent': requireUserConsent,
    'user_consent_granted': userConsentGranted,
  };
}

enum ProvisionPhase { idle, checking, downloading, loading, ready, failed }

/// Observable provisioning state, suitable for driving UI directly.
class ProvisionProgress {
  const ProvisionProgress({
    required this.phase,
    this.percent,
    this.downloadedBytes,
    this.totalBytes,
    this.message = '',
  });

  final ProvisionPhase phase;
  final int? percent;
  final int? downloadedBytes;
  final int? totalBytes;
  final String message;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'phase': phase.name,
    if (percent != null) 'percent': percent,
    if (downloadedBytes != null) 'downloaded_bytes': downloadedBytes,
    if (totalBytes != null) 'total_bytes': totalBytes,
    'message': message,
  };
}

/// Handle to a provisioned model artifact.
extension type const ModelHandle(String value) {}

/// Capability interface for clients whose models must be provisioned
/// (downloaded / activated) before inference.
///
/// Deliberately NOT part of [InferenceClient]: cloud providers don't need it,
/// and local providers adopt it optionally. Clients implementing this can be
/// detected via `is ProvisionableInferenceClient`.
abstract interface class ProvisionableInferenceClient {
  /// Ensures a model matching [purpose] is installed and active, honoring
  /// [constraints]. Idempotent: returns immediately when a suitable model is
  /// already ready.
  Future<InferenceResult<ModelHandle>> ensureReady(
    ModelPurpose purpose, {
    ProvisionConstraints constraints,
  });

  /// Progress stream for UI. Emits during [ensureReady]; safe to listen
  /// before or during the call.
  Stream<ProvisionProgress> get provisionProgress;
}
