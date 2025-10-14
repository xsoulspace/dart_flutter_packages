import 'package:xsoulspace_logger/xsoulspace_logger.dart';

/// {@template review_logger_extensions}
/// Convenient extension methods for optional logger usage.
///
/// Provides null-safe logging helpers that gracefully handle
/// cases where logger is not provided. All methods work correctly
/// when called on a null logger instance.
///
/// Example:
/// ```dart
/// Logger? logger;
/// logger.logReviewError('Operation failed', error, stackTrace);
/// // Works fine even when logger is null
/// ```
/// {@endtemplate}
extension ReviewLoggerExtensions on Logger? {
  /// Log review-related error with context
  ///
  /// Logs to 'REVIEW' category with full error details including
  /// stack trace. Safe to call on null logger.
  void logReviewError(String message, Object error, [StackTrace? stackTrace]) {
    this?.error(
      'REVIEW',
      message,
      error: error,
      stackTrace: stackTrace ?? StackTrace.current,
    );
  }

  /// Log feedback-related event
  ///
  /// Logs to 'FEEDBACK' category at info level.
  /// Safe to call on null logger.
  ///
  /// - [message] - Description of feedback event
  /// - [data] - Optional structured data
  void logFeedback(String message, {Map<String, dynamic>? data}) {
    this?.info('FEEDBACK', message, data: data);
  }

  /// Log consent decision
  ///
  /// Logs to 'CONSENT' category at info level.
  /// Safe to call on null logger.
  ///
  /// - [message] - Description of consent event
  /// - [data] - Optional structured data (e.g., consent state)
  void logConsent(String message, {Map<String, dynamic>? data}) {
    this?.info('CONSENT', message, data: data);
  }

  /// Log debug information for review operations
  ///
  /// Logs to 'REVIEW' category at debug level.
  /// Safe to call on null logger.
  ///
  /// - [message] - Debug message
  /// - [data] - Optional structured data
  void logReviewDebug(String message, {Map<String, dynamic>? data}) {
    this?.debug('REVIEW', message, data: data);
  }

  /// Log review-related warning
  ///
  /// Logs to 'REVIEW' category at warning level.
  /// Safe to call on null logger.
  ///
  /// - [message] - Warning message
  /// - [data] - Optional structured data
  void logReviewWarning(String message, {Map<String, dynamic>? data}) {
    this?.warning('REVIEW', message, data: data);
  }
}
