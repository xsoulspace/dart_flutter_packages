import 'package:xsoulspace_logger/xsoulspace_logger.dart';

/// {@template review_logger_config}
/// Provides environment-aware logger configuration for xsoulspace_review.
///
/// Manages logging levels and output destinations based on build mode
/// and runtime environment.
///
/// This class only provides configuration presets. The consuming application
/// is responsible for initializing the logger with these configurations.
///
/// Example:
/// ```dart
/// final config = ReviewLoggerConfig.getConfig(
///   isDebugMode: kDebugMode,
///   enableFileLogging: !kDebugMode,
/// );
/// final logger = Logger(config);
/// await logger.init();
/// ```
/// {@endtemplate}
class ReviewLoggerConfig {
  /// {@macro review_logger_config}
  const ReviewLoggerConfig._();

  /// Gets appropriate logger configuration based on environment
  ///
  /// Returns debug configuration when [isDebugMode] is true,
  /// otherwise returns production-optimized configuration.
  ///
  /// - [isDebugMode] - Enable verbose logging for development
  /// - [enableFileLogging] - Enable file output (default: false)
  static LoggerConfig getConfig({
    bool isDebugMode = false,
    bool enableFileLogging = false,
  }) {
    if (isDebugMode) {
      return LoggerConfig.debug();
    }

    return LoggerConfig(
      minLevel: LogLevel.info,
      enableConsole: false,
      enableFile: enableFileLogging,
      enableRotation: true,
      maxFileSizeMB: 10,
      maxFileCount: 5,
    );
  }

  /// Console-only configuration for testing
  ///
  /// Logs warnings and above to console only, no file output.
  /// Useful for unit and integration tests.
  static LoggerConfig get testing =>
      LoggerConfig.consoleOnly(level: LogLevel.warning);
}
