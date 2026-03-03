/// Marker contract for a platform capability module.
abstract interface class PlatformCapability {
  /// Stable capability name used in diagnostics and telemetry.
  String get capabilityName;
}
