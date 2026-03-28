/// Wrapper-level initialization error codes.
enum SteamInitErrorCode {
  alreadyInitialized,
  restartRequired,
  failedGeneric,
  noSteamClient,
  versionMismatch,
  libraryLoadFailed,
  invalidConfig,
  unknown,
}

/// Input configuration for [SteamClient.initialize].
final class SteamInitConfig {
  const SteamInitConfig({
    required this.appId,
    this.autoPumpCallbacks = true,
    this.callbackInterval = const Duration(milliseconds: 16),
    this.librarySearchPaths = const <String>[],
    this.enableVerboseLogs = false,
  });

  static const Duration maxCallbackInterval = Duration(milliseconds: 100);

  /// Steam AppID used for startup checks.
  final int appId;

  /// Whether callback pumping timer starts automatically after init.
  final bool autoPumpCallbacks;

  /// Callback pump interval. Must be between `1ms` and `100ms`.
  final Duration callbackInterval;

  /// Optional explicit runtime library locations.
  final List<String> librarySearchPaths;

  /// Enables verbose runtime logs.
  final bool enableVerboseLogs;

  void validate() {
    if (appId <= 0) {
      throw ArgumentError.value(
        appId,
        'appId',
        'appId must be greater than 0.',
      );
    }
    if (callbackInterval <= Duration.zero) {
      throw ArgumentError.value(
        callbackInterval,
        'callbackInterval',
        'callbackInterval must be greater than zero.',
      );
    }
    if (callbackInterval > maxCallbackInterval) {
      throw ArgumentError.value(
        callbackInterval,
        'callbackInterval',
        'callbackInterval must be <= ${maxCallbackInterval.inMilliseconds}ms.',
      );
    }
  }
}

/// Result object returned by [SteamClient.initialize].
final class SteamInitResult {
  const SteamInitResult._({
    required this.success,
    this.errorCode,
    this.message,
    this.nativeInitCode,
    this.restartRequired = false,
  });

  factory SteamInitResult.success() => const SteamInitResult._(success: true);

  factory SteamInitResult.failure({
    required final SteamInitErrorCode errorCode,
    final String? message,
    final int? nativeInitCode,
    final bool restartRequired = false,
  }) => SteamInitResult._(
      success: false,
      errorCode: errorCode,
      message: message,
      nativeInitCode: nativeInitCode,
      restartRequired: restartRequired,
    );

  final bool success;
  final SteamInitErrorCode? errorCode;
  final String? message;
  final int? nativeInitCode;
  final bool restartRequired;
}
