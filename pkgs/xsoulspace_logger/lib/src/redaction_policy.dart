import 'dart:convert';

/// Callback that marks whether [key] should be redacted for [path].
typedef RedactKeyPredicate = bool Function(String key, List<String> path);

/// Callback that marks whether [key] is explicitly allowed for [path].
typedef AllowKeyPredicate = bool Function(String key, List<String> path);

/// Safe-by-default redaction and size/depth guards.
final class RedactionPolicy {
  const RedactionPolicy({
    this.sensitiveKeys = _defaultSensitiveKeys,
    this.maxFieldDepth = 6,
    this.maxSerializedValueBytes = 4096,
    this.maxStackTraceLines = 120,
    this.redactKey,
    this.allowKey,
  }) : assert(maxFieldDepth > 0),
       assert(maxSerializedValueBytes > 0),
       assert(maxStackTraceLines > 0);

  static const Set<String> _defaultSensitiveKeys = <String>{
    'password',
    'token',
    'secret',
    'authorization',
    'cookie',
    'session',
    'apikey',
    'email',
    'phone',
  };

  final Set<String> sensitiveKeys;
  final int maxFieldDepth;
  final int maxSerializedValueBytes;
  final int maxStackTraceLines;
  final RedactKeyPredicate? redactKey;
  final AllowKeyPredicate? allowKey;

  /// Returns a recursively sanitized map suitable for persistence.
  Map<String, Object?> sanitizeFields(final Map<String, Object?> fields) {
    if (fields.isEmpty) {
      return const <String, Object?>{};
    }

    final seen = <Object>{};
    final sanitized = <String, Object?>{};

    fields.forEach((final key, final value) {
      final path = <String>[key];
      if (_shouldRedact(key, path)) {
        sanitized[key] = '[REDACTED]';
      } else {
        sanitized[key] = _sanitizeValue(
          value,
          depth: 1,
          path: path,
          seen: seen,
        );
      }
    });

    return Map<String, Object?>.unmodifiable(sanitized);
  }

  /// Returns a stack trace trimmed for persistence-safe storage.
  StackTrace? sanitizeStackTrace(final StackTrace? stackTrace) {
    if (stackTrace == null) {
      return null;
    }

    final lines = stackTrace.toString().split('\n');
    if (lines.length <= maxStackTraceLines) {
      return stackTrace;
    }

    return StackTrace.fromString(lines.take(maxStackTraceLines).join('\n'));
  }

  Object? _sanitizeValue(
    final Object? value, {
    required final int depth,
    required final List<String> path,
    required final Set<Object> seen,
  }) {
    if (value == null || value is num || value is bool) {
      return value;
    }

    if (depth > maxFieldDepth) {
      return '[MAX_DEPTH]';
    }

    if (value is String) {
      return _truncateSerialized(value);
    }

    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }

    if (value is Map) {
      if (!seen.add(value)) {
        return '[CIRCULAR]';
      }

      final result = <String, Object?>{};
      value.forEach((final rawKey, final nestedValue) {
        final key = rawKey.toString();
        final nestedPath = List<String>.from(path)..add(key);
        if (_shouldRedact(key, nestedPath)) {
          result[key] = '[REDACTED]';
        } else {
          result[key] = _sanitizeValue(
            nestedValue,
            depth: depth + 1,
            path: nestedPath,
            seen: seen,
          );
        }
      });

      seen.remove(value);
      return result;
    }

    if (value is Iterable) {
      if (!seen.add(value)) {
        return '[CIRCULAR]';
      }

      final result = <Object?>[];
      var index = 0;
      for (final item in value) {
        final nestedPath = List<String>.from(path)..add('[$index]');
        result.add(
          _sanitizeValue(item, depth: depth + 1, path: nestedPath, seen: seen),
        );
        index++;
      }

      seen.remove(value);
      return result;
    }

    return _truncateSerialized(value.toString());
  }

  bool _shouldRedact(final String key, final List<String> path) {
    if (allowKey?.call(key, path) == true) {
      return false;
    }
    if (redactKey?.call(key, path) == true) {
      return true;
    }

    final normalized = key.toLowerCase();
    for (final candidate in sensitiveKeys) {
      if (candidate.toLowerCase() == normalized) {
        return true;
      }
    }

    return false;
  }

  String _truncateSerialized(final String value) {
    final bytes = utf8.encode(value);
    if (bytes.length <= maxSerializedValueBytes) {
      return value;
    }

    final head = bytes.sublist(0, maxSerializedValueBytes);
    final decoded = utf8.decode(head, allowMalformed: true);
    return '$decoded...[TRUNCATED]';
  }
}
