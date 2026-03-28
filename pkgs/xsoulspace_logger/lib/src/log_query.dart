import 'log_level.dart';
import 'log_record.dart';

/// Query filters for programmatic log inspection.
final class LogQuery {
  const LogQuery({
    this.fromUtc,
    this.toUtc,
    this.levels,
    this.categories,
    this.text,
    this.traceId,
    this.fingerprint,
    this.limit,
  }) : assert(limit == null || limit >= 0);

  final DateTime? fromUtc;
  final DateTime? toUtc;
  final Set<LogLevel>? levels;
  final Set<String>? categories;
  final String? text;
  final String? traceId;
  final String? fingerprint;
  final int? limit;

  bool matches(final LogRecord record) {
    if (fromUtc != null && record.timestampUtc.isBefore(fromUtc!.toUtc())) {
      return false;
    }
    if (toUtc != null && record.timestampUtc.isAfter(toUtc!.toUtc())) {
      return false;
    }
    if (levels != null &&
        levels!.isNotEmpty &&
        !levels!.contains(record.level)) {
      return false;
    }
    if (categories != null &&
        categories!.isNotEmpty &&
        !categories!.contains(record.category)) {
      return false;
    }
    if (traceId != null && record.trace?.traceId != traceId) {
      return false;
    }
    if (fingerprint != null && record.fingerprint != fingerprint) {
      return false;
    }
    if (text != null && text!.isNotEmpty) {
      final needle = text!.toLowerCase();
      final haystack = StringBuffer()
        ..write(record.message)
        ..write(' ')
        ..write(record.category)
        ..write(' ')
        ..write(record.error?.toString() ?? '');

      record.fields.forEach((final key, final value) {
        haystack
          ..write(' ')
          ..write(key)
          ..write('=')
          ..write(value);
      });

      if (!haystack.toString().toLowerCase().contains(needle)) {
        return false;
      }
    }

    return true;
  }
}
