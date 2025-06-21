import 'dart:async';
import 'dart:math';

import '../storage_exceptions.dart';

/// {@template retryable_operation}
/// Utility class for executing operations with retry logic.
/// Provides exponential backoff and custom retry conditions.
/// {@endtemplate}
mixin RetryableOperation {
  /// Executes an operation with retry logic
  static Future<T> execute<T>(
    final Future<T> Function() operation, {
    final int maxAttempts = 3,
    final Duration initialDelay = const Duration(milliseconds: 500),
    final double backoffMultiplier = 2.0,
    final bool Function(Exception)? retryIf,
  }) async {
    Exception? lastException;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await operation();
        // ignore: avoid_catches_without_on_clauses
      } catch (e, _) {
        lastException = e is Exception ? e : Exception(e.toString());

        // Don't retry on final attempt
        if (attempt >= maxAttempts) break;

        // Check if we should retry this exception
        if (retryIf != null && !retryIf(lastException)) {
          break;
        }

        // Default retry logic for network-related exceptions
        if (!_shouldRetryByDefault(lastException)) {
          break;
        }

        // Calculate delay with exponential backoff
        final ms =
            (initialDelay.inMilliseconds * pow(backoffMultiplier, attempt - 1))
                .round();
        final delay = Duration(milliseconds: ms);

        await Future<void>.delayed(delay);
      }
    }

    throw lastException!;
  }

  /// Default retry condition for common network exceptions
  static bool _shouldRetryByDefault(final Exception exception) {
    final errorString = exception.toString().toLowerCase();

    // Retry on network-related errors
    if (exception is NetworkException || exception is NetworkTimeoutException) {
      return true;
    }

    // Retry on temporary HTTP errors (5xx)
    if (errorString.contains('500') ||
        errorString.contains('502') ||
        errorString.contains('503') ||
        errorString.contains('504') ||
        errorString.contains('timeout') ||
        errorString.contains('connection')) {
      return true;
    }

    // Don't retry on authentication or client errors
    if (exception is AuthenticationException ||
        exception is ConfigurationException ||
        errorString.contains('400') ||
        errorString.contains('401') ||
        errorString.contains('403') ||
        errorString.contains('404')) {
      return false;
    }

    return false;
  }

  /// Wraps GitHub API operations with retry logic
  static Future<T> github<T>(
    final Future<T> Function() operation, {
    final int maxAttempts = 3,
  }) => execute(
    operation,
    maxAttempts: maxAttempts,
    // Don't retry rate limits immediately
    retryIf: (final exception) => switch (exception) {
      // Special handling for GitHub rate limits
      GitHubRateLimitException() => false,
      _ => _shouldRetryByDefault(exception),
    },
  );

  /// Wraps Git operations with retry logic
  static Future<T> git<T>(
    final Future<T> Function() operation, {
    final int maxAttempts = 2,
  }) => execute(
    operation,
    maxAttempts: maxAttempts,
    // Don't retry Git conflicts or authentication failures
    retryIf: (final exception) => switch (exception) {
      GitConflictException() || AuthenticationFailedException() => false,
      _ => _shouldRetryByDefault(exception),
    },
  );
}
