import 'missing_capability_behavior.dart';

/// Options passed to [PlatformClient.init].
final class PlatformInitOptions {
  const PlatformInitOptions({
    this.missingCapabilityBehavior = MissingCapabilityBehavior.strict,
    this.requiredCapabilities = const <Type>{},
    this.context = const <String, Object?>{},
  });

  /// Runtime behavior when a capability is not supported.
  final MissingCapabilityBehavior missingCapabilityBehavior;

  /// Capabilities that should be treated as required at startup.
  final Set<Type> requiredCapabilities;

  /// Adapter-specific options passed through by key.
  final Map<String, Object?> context;

  /// Reads a typed option from [context]. Returns `null` on mismatch.
  T? read<T extends Object>(final String key) {
    final value = context[key];
    return value is T ? value : null;
  }
}

/// Outcome type for platform initialization.
enum PlatformInitResultStatus { success, notAvailable, failure }

/// Result returned from [PlatformClient.init].
final class PlatformInitResult {
  const PlatformInitResult._({required this.status, this.message, this.error});

  factory PlatformInitResult.success({final String? message}) {
    return PlatformInitResult._(
      status: PlatformInitResultStatus.success,
      message: message,
    );
  }

  factory PlatformInitResult.notAvailable({final String? message}) {
    return PlatformInitResult._(
      status: PlatformInitResultStatus.notAvailable,
      message: message,
    );
  }

  factory PlatformInitResult.failure({
    final String? message,
    final Object? error,
  }) {
    return PlatformInitResult._(
      status: PlatformInitResultStatus.failure,
      message: message,
      error: error,
    );
  }

  final PlatformInitResultStatus status;
  final String? message;
  final Object? error;

  bool get isSuccess => status == PlatformInitResultStatus.success;
  bool get isNotAvailable => status == PlatformInitResultStatus.notAvailable;
  bool get isFailure => status == PlatformInitResultStatus.failure;
}
