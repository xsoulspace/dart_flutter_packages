
/// Distributed tracing context attached to a log record.
final class TraceContext {
  const TraceContext({
    required this.traceId,
    required this.spanId,
    this.parentSpanId,
  });

  factory TraceContext.fromJson(final Map<String, Object?> json) =>
      TraceContext(
        traceId: (json['traceId'] ?? '').toString(),
        spanId: (json['spanId'] ?? '').toString(),
        parentSpanId: json['parentSpanId']?.toString(),
      );

  final String traceId;
  final String spanId;
  final String? parentSpanId;

  Map<String, Object?> toJson() => <String, Object?>{
    'traceId': traceId,
    'spanId': spanId,
    if (parentSpanId != null) 'parentSpanId': parentSpanId,
  };
}
