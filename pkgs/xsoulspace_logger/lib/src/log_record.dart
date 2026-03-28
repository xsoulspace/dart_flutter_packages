import 'log_level.dart';
import 'trace_context.dart';

/// Immutable log event.
final class LogRecord {
  const LogRecord({
    required this.sequence,
    required this.timestampUtc,
    required this.level,
    required this.category,
    required this.message,
    this.fields = const <String, Object?>{},
    this.error,
    this.stackTrace,
    this.trace,
    this.fingerprint,
  }) : assert(sequence > 0);

  factory LogRecord.fromJson(final Map<String, Object?> json) => LogRecord(
    sequence: (json['sequence'] as num?)?.toInt() ?? 0,
    timestampUtc:
        DateTime.tryParse((json['timestampUtc'] ?? '').toString())?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    level: LogLevel.fromName((json['level'] ?? 'info').toString()),
    category: (json['category'] ?? '').toString(),
    message: (json['message'] ?? '').toString(),
    fields: json['fields'] is Map
        ? Map<String, Object?>.from(json['fields']! as Map<dynamic, dynamic>)
        : const <String, Object?>{},
    error: json['error'],
    stackTrace: json['stackTrace'] == null
        ? null
        : StackTrace.fromString(json['stackTrace']!.toString()),
    trace: json['trace'] is Map
        ? TraceContext.fromJson(
            Map<String, Object?>.from(json['trace']! as Map<dynamic, dynamic>),
          )
        : null,
    fingerprint: json['fingerprint']?.toString(),
  );

  final int sequence;
  final DateTime timestampUtc;
  final LogLevel level;
  final String category;
  final String message;
  final Map<String, Object?> fields;
  final Object? error;
  final StackTrace? stackTrace;
  final TraceContext? trace;
  final String? fingerprint;

  Map<String, Object?> toJson({
    final int schemaVersion = 1,
    final int? maxStackTraceLines,
  }) {
    final serializedStack = stackTrace?.toString();
    final stackForStorage =
        serializedStack == null || maxStackTraceLines == null
        ? serializedStack
        : _truncateStackTrace(serializedStack, maxStackTraceLines);

    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'sequence': sequence,
      'timestampUtc': timestampUtc.toUtc().toIso8601String(),
      'level': level.name,
      'category': category,
      'message': message,
      'fields': fields,
      if (error != null) 'error': error.toString(),
      if (stackForStorage != null) 'stackTrace': stackForStorage,
      if (trace != null) 'trace': trace!.toJson(),
      if (fingerprint != null) 'fingerprint': fingerprint,
    };
  }

  LogRecord copyWith({
    final int? sequence,
    final DateTime? timestampUtc,
    final LogLevel? level,
    final String? category,
    final String? message,
    final Map<String, Object?>? fields,
    final Object? error,
    final StackTrace? stackTrace,
    final TraceContext? trace,
    final String? fingerprint,
  }) => LogRecord(
    sequence: sequence ?? this.sequence,
    timestampUtc: timestampUtc ?? this.timestampUtc,
    level: level ?? this.level,
    category: category ?? this.category,
    message: message ?? this.message,
    fields: fields ?? this.fields,
    error: error ?? this.error,
    stackTrace: stackTrace ?? this.stackTrace,
    trace: trace ?? this.trace,
    fingerprint: fingerprint ?? this.fingerprint,
  );

  static String _truncateStackTrace(
    final String stackTrace,
    final int maxLines,
  ) {
    final lines = stackTrace.split('\n');
    if (lines.length <= maxLines) {
      return stackTrace;
    }
    return lines.take(maxLines).join('\n');
  }
}
