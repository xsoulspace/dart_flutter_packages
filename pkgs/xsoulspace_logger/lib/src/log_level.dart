/// Log severity levels
library;

/// Enumeration of log levels from most verbose to most severe
enum LogLevel {
  /// Detailed diagnostic information for debugging
  verbose(0, 'VERBOSE'),

  /// Debug information for development
  debug(1, 'DEBUG'),

  /// Informational messages about normal operations
  info(2, 'INFO'),

  /// Warning messages for potentially problematic situations
  warning(3, 'WARNING'),

  /// Error messages for serious problems
  error(4, 'ERROR');

  /// Numeric value for comparison
  final int value;

  /// Display name
  final String name;

  const LogLevel(this.value, this.name);

  /// Check if this level is enabled given a minimum level
  bool isEnabled(LogLevel minLevel) => value >= minLevel.value;

  /// Console color emoji for this level
  String get emoji => switch (this) {
    LogLevel.verbose => '⚪',
    LogLevel.debug => '🔵',
    LogLevel.info => '🟢',
    LogLevel.warning => '🟡',
    LogLevel.error => '🔴',
  };
}
