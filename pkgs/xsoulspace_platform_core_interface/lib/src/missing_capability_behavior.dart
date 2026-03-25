/// Defines how runtime handles missing capabilities.
enum MissingCapabilityBehavior {
  /// Throw a typed exception for unsupported capabilities.
  strict,

  /// Try to resolve no-op/fallback capabilities where possible.
  permissive,
}
