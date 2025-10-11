/// Core logger implementation
library;

import 'dart:io';

import 'file_writer.dart';
import 'log_level.dart';
import 'logger_config.dart';

/// Main logger class with singleton pattern
class Logger {
  static Logger? _instance;

  final LoggerConfig config;
  final FileWriter? _fileWriter;

  Logger._internal(this.config)
    : _fileWriter = config.enableFile ? FileWriter(config) : null;

  /// Get or create logger instance
  factory Logger([LoggerConfig? config]) {
    if (_instance == null && config != null) {
      _instance = Logger._internal(config);
    } else
      _instance ??= Logger._internal(LoggerConfig.consoleOnly());
    return _instance!;
  }

  /// Reset logger with new configuration
  static Future<void> reset([LoggerConfig? config]) async {
    if (_instance?._fileWriter != null) {
      await _instance!._fileWriter!.dispose();
    }
    _instance = config != null ? Logger._internal(config) : null;
  }

  /// Log a message at specified level
  void log(
    LogLevel level,
    String category,
    String message, {
    Map<String, dynamic>? data,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!level.isEnabled(config.minLevel)) return;

    final timestamp = DateTime.now();
    final formattedMessage = _formatMessage(
      timestamp,
      level,
      category,
      message,
      data: data,
      error: error,
      stackTrace: stackTrace,
    );

    // Console output
    if (config.enableConsole) {
      _writeToConsole(level, formattedMessage);
    }

    // File output
    if (config.enableFile) {
      final fileMessage = _formatFileMessage(
        timestamp,
        level,
        category,
        message,
        data: data,
        error: error,
        stackTrace: stackTrace,
      );
      _fileWriter?.write(fileMessage);
    }
  }

  /// Log verbose message
  void verbose(String category, String message, {Map<String, dynamic>? data}) =>
      log(LogLevel.verbose, category, message, data: data);

  /// Log debug message
  void debug(String category, String message, {Map<String, dynamic>? data}) =>
      log(LogLevel.debug, category, message, data: data);

  /// Log info message
  void info(String category, String message, {Map<String, dynamic>? data}) =>
      log(LogLevel.info, category, message, data: data);

  /// Log warning message
  void warning(String category, String message, {Map<String, dynamic>? data}) =>
      log(LogLevel.warning, category, message, data: data);

  /// Log error message
  void error(
    String category,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) => log(
    LogLevel.error,
    category,
    message,
    error: error,
    stackTrace: stackTrace,
  );

  /// Format message for console (concise, colored)
  String _formatMessage(
    DateTime timestamp,
    LogLevel level,
    String category,
    String message, {
    Map<String, dynamic>? data,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final time = _formatTime(timestamp);
    final emoji = level.emoji;
    var result =
        '[$time] $emoji ${level.name.padRight(7)} [$category] $message';

    if (data != null && data.isNotEmpty) {
      result += ' | ${_formatData(data)}';
    }

    if (error != null) {
      result += '\n  Error: $error';
    }

    return result;
  }

  /// Format message for file (detailed, structured)
  String _formatFileMessage(
    DateTime timestamp,
    LogLevel level,
    String category,
    String message, {
    Map<String, dynamic>? data,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final time = timestamp.toIso8601String();
    final buffer = StringBuffer();

    buffer.writeln('[$time] [${level.name}] [$category] $message');

    if (data != null && data.isNotEmpty) {
      data.forEach((key, value) {
        // Truncate very long values
        final valueStr = value.toString();
        final truncated = valueStr.length > 1000
            ? '${valueStr.substring(0, 1000)}...'
            : valueStr;
        buffer.writeln('  $key: $truncated');
      });
    }

    if (error != null) {
      buffer.writeln('  error: $error');
    }

    if (stackTrace != null) {
      buffer.writeln('  stackTrace:');
      buffer.writeln(
        stackTrace.toString().split('\n').map((line) => '    $line').join('\n'),
      );
    }

    return buffer.toString().trimRight();
  }

  /// Format time for console (HH:mm:ss)
  String _formatTime(DateTime timestamp) {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  /// Format data map concisely
  String _formatData(Map<String, dynamic> data) {
    return data.entries.map((e) => '${e.key}=${e.value}').join(', ');
  }

  /// Write to console with appropriate output stream
  void _writeToConsole(LogLevel level, String message) {
    if (level == LogLevel.error) {
      stderr.writeln(message);
    } else {
      stdout.writeln(message);
    }
  }

  /// Flush and cleanup
  Future<void> dispose() async {
    await _fileWriter?.dispose();
  }
}
