import 'inference_client.dart';
import 'inference_models.dart';
import 'inference_result.dart';

enum InferenceStructuredTextStreamEventType {
  lifecycle,
  progress,
  partialOutput,
  raw,
  warning,
  error,
  completion,
}

enum InferenceStructuredTextLifecycleState {
  started,
  retrying,
  running,
  timedOut,
  completed,
  failed,
}

enum InferenceStructuredTextRawChannel { stdout, stderr }

InferenceStructuredTextStreamEventType
inferenceStructuredTextStreamEventTypeFromJsonValue(final Object? value) {
  if (value is! String) {
    return InferenceStructuredTextStreamEventType.progress;
  }
  return InferenceStructuredTextStreamEventType.values.firstWhere(
    (final candidate) => candidate.name == value,
    orElse: () => InferenceStructuredTextStreamEventType.progress,
  );
}

InferenceStructuredTextLifecycleState?
inferenceStructuredTextLifecycleStateFromJsonValue(final Object? value) {
  if (value is! String) {
    return null;
  }
  for (final candidate in InferenceStructuredTextLifecycleState.values) {
    if (candidate.name == value) {
      return candidate;
    }
  }
  return null;
}

InferenceStructuredTextRawChannel?
inferenceStructuredTextRawChannelFromJsonValue(final Object? value) {
  if (value is! String) {
    return null;
  }
  for (final candidate in InferenceStructuredTextRawChannel.values) {
    if (candidate.name == value) {
      return candidate;
    }
  }
  return null;
}

class InferenceStructuredTextCompletion {
  const InferenceStructuredTextCompletion({
    required this.result,
    this.attemptCount,
  });

  final InferenceResult<InferenceResponse> result;
  final int? attemptCount;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'result': result.toJson((final value) => value.toJson()),
    if (attemptCount != null) 'attempt_count': attemptCount,
  };

  factory InferenceStructuredTextCompletion.fromJson(
    final Map<String, dynamic> json,
  ) {
    final resultJson =
        (json['result'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final success = resultJson['success'] == true;
    final dataJson = (resultJson['data'] as Map?)?.cast<String, dynamic>();
    final errorJson = (resultJson['error'] as Map?)?.cast<String, dynamic>();
    final warnings =
        (resultJson['warnings'] as List?)?.cast<String>() ?? const <String>[];
    final meta =
        (resultJson['meta'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final result = success
        ? InferenceResult<InferenceResponse>.ok(
            InferenceResponse.fromJson(dataJson ?? const <String, dynamic>{}),
            warnings: warnings,
            meta: meta,
          )
        : InferenceResult<InferenceResponse>.fail(
            code: '${errorJson?['code'] ?? 'stream_failed'}',
            message:
                '${errorJson?['message'] ?? 'Structured text stream failed'}',
            details: errorJson?['details'],
            warnings: warnings,
            meta: meta,
          );
    return InferenceStructuredTextCompletion(
      result: result,
      attemptCount: switch (json['attempt_count']) {
        final int value => value,
        final num value => value.toInt(),
        _ => null,
      },
    );
  }
}

class InferenceStructuredTextStreamEvent {
  const InferenceStructuredTextStreamEvent({
    required this.type,
    required this.timestamp,
    this.lifecycleState,
    this.message,
    this.textDelta,
    this.rawText,
    this.rawChannel,
    this.attempt,
    this.isTransient = false,
    this.error,
    this.completion,
    this.metadata = const <String, dynamic>{},
  });

  final InferenceStructuredTextStreamEventType type;
  final DateTime timestamp;
  final InferenceStructuredTextLifecycleState? lifecycleState;
  final String? message;
  final String? textDelta;
  final String? rawText;
  final InferenceStructuredTextRawChannel? rawChannel;
  final int? attempt;
  final bool isTransient;
  final InferenceError? error;
  final InferenceStructuredTextCompletion? completion;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': type.name,
    'timestamp': timestamp.toIso8601String(),
    if (lifecycleState != null) 'lifecycle_state': lifecycleState!.name,
    if (message != null) 'message': message,
    if (textDelta != null) 'text_delta': textDelta,
    if (rawText != null) 'raw_text': rawText,
    if (rawChannel != null) 'raw_channel': rawChannel!.name,
    if (attempt != null) 'attempt': attempt,
    'is_transient': isTransient,
    if (error != null) 'error': error!.toJson(),
    if (completion != null) 'completion': completion!.toJson(),
    'metadata': metadata,
  };

  factory InferenceStructuredTextStreamEvent.fromJson(
    final Map<String, dynamic> json,
  ) => InferenceStructuredTextStreamEvent(
    type: inferenceStructuredTextStreamEventTypeFromJsonValue(json['type']),
    timestamp:
        DateTime.tryParse('${json['timestamp'] ?? ''}') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    lifecycleState: inferenceStructuredTextLifecycleStateFromJsonValue(
      json['lifecycle_state'],
    ),
    message: json['message'] as String?,
    textDelta: json['text_delta'] as String?,
    rawText: json['raw_text'] as String?,
    rawChannel: inferenceStructuredTextRawChannelFromJsonValue(
      json['raw_channel'],
    ),
    attempt: switch (json['attempt']) {
      final int value => value,
      final num value => value.toInt(),
      _ => null,
    },
    isTransient: json['is_transient'] as bool? ?? false,
    error: switch (json['error']) {
      final Map value => InferenceError(
        code: '${value['code'] ?? 'stream_error'}',
        message: '${value['message'] ?? 'Structured text streaming error'}',
        details: value['details'],
      ),
      _ => null,
    },
    completion: switch (json['completion']) {
      final Map value => InferenceStructuredTextCompletion.fromJson(
        value.cast<String, dynamic>(),
      ),
      _ => null,
    },
    metadata:
        (json['metadata'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{},
  );
}

abstract interface class InferenceStructuredTextStreamSession {
  Stream<InferenceStructuredTextStreamEvent> get events;

  Future<InferenceResult<InferenceResponse>> get result;

  Future<void> cancel();

  Future<void> dispose();
}

abstract interface class StructuredTextStreamingInferenceClient
    implements InferenceClient {
  Future<InferenceStructuredTextStreamSession> streamStructuredText(
    InferenceRequest request,
  );
}

extension InferenceStructuredTextStreamingClientX on InferenceClient {
  bool get supportsStructuredTextStreaming =>
      this is StructuredTextStreamingInferenceClient;

  Future<InferenceStructuredTextStreamSession> streamStructuredText(
    final InferenceRequest request,
  ) {
    final client = this;
    if (client is StructuredTextStreamingInferenceClient) {
      return client.streamStructuredText(request);
    }
    throw UnsupportedError(
      'Client $id does not support structured-text streaming.',
    );
  }
}
