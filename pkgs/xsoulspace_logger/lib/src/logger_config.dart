/// Logger configuration
library;

import 'log_level.dart';

/// Configuration for logger behavior
class LoggerConfig {

  const LoggerConfig({
    required this.minLevel,
    required this.enableConsole,
    required this.enableFile,
    this.logDirectory,
    this.enableRotation = true,
    this.maxFileSizeMB = 10,
    this.maxFileCount = 5,
  });

  /// Debug preset: verbose logging to console and file
  factory LoggerConfig.debug({final String? logDirectory}) => LoggerConfig(
    minLevel: LogLevel.verbose,
    enableConsole: true,
    enableFile: true,
    logDirectory: logDirectory,
  );

  /// Production preset: info level, file only
  factory LoggerConfig.production({final String? logDirectory}) => LoggerConfig(
    minLevel: LogLevel.info,
    enableConsole: false,
    enableFile: true,
    logDirectory: logDirectory,
    maxFileSizeMB: 50,
  );

  /// Verbose preset: all logs to console and file
  factory LoggerConfig.verbose({final String? logDirectory}) => LoggerConfig(
    minLevel: LogLevel.verbose,
    enableConsole: true,
    enableFile: true,
    logDirectory: logDirectory,
    maxFileSizeMB: 100,
  );

  /// Silent preset: errors only to file
  factory LoggerConfig.silent({final String? logDirectory}) => LoggerConfig(
    minLevel: LogLevel.error,
    enableConsole: false,
    enableFile: true,
    logDirectory: logDirectory,
  );

  /// Console-only preset for testing
  factory LoggerConfig.consoleOnly({final LogLevel level = LogLevel.debug}) =>
      LoggerConfig(minLevel: level, enableConsole: true, enableFile: false);
  /// Minimum log level to output
  final LogLevel minLevel;

  /// Enable console output
  final bool enableConsole;

  /// Enable file output
  final bool enableFile;

  /// Directory for log files (null = temp directory)
  final String? logDirectory;

  /// Enable log file rotation
  final bool enableRotation;

  /// Maximum file size in MB before rotation
  final int maxFileSizeMB;

  /// Maximum number of log files to keep
  final int maxFileCount;
}
