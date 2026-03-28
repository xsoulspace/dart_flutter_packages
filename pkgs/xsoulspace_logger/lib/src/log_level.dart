/// Log severity from least to most severe.
enum LogLevel {
  trace,
  debug,
  info,
  warning,
  error,
  critical;

  /// Whether this level is enabled by [minimum].
  bool isAtLeast(final LogLevel minimum) => index >= minimum.index;

  /// Parses a level name, defaulting to [LogLevel.info].
  static LogLevel fromName(final String value) {
    for (final level in LogLevel.values) {
      if (level.name == value) {
        return level;
      }
    }
    return LogLevel.info;
  }
}
