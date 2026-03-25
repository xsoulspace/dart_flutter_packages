import 'inference_result.dart';

enum InferenceTranscriptEventType {
  partialTranscript,
  finalTranscript,
  sessionStateChanged,
  warning,
  error,
  metrics,
}

enum InferenceRealtimeSessionState {
  idle,
  connecting,
  streaming,
  finalizing,
  closed,
}

class InferenceTranscriptEvent {
  const InferenceTranscriptEvent({
    required this.type,
    required this.timestamp,
    this.transcript,
    this.isFinal = false,
    this.sessionState,
    this.metrics = const <String, num>{},
    this.metadata = const <String, dynamic>{},
    this.error,
  });

  final InferenceTranscriptEventType type;
  final DateTime timestamp;
  final String? transcript;
  final bool isFinal;
  final InferenceRealtimeSessionState? sessionState;
  final Map<String, num> metrics;
  final Map<String, dynamic> metadata;
  final InferenceError? error;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': type.name,
    'timestamp': timestamp.toIso8601String(),
    if (transcript != null) 'transcript': transcript,
    'is_final': isFinal,
    if (sessionState != null) 'session_state': sessionState!.name,
    'metrics': metrics,
    'metadata': metadata,
    if (error != null) 'error': error!.toJson(),
  };

  factory InferenceTranscriptEvent.fromJson(final Map<String, dynamic> json) {
    final typeName = json['type'] as String?;
    final stateName = json['session_state'] as String?;

    return InferenceTranscriptEvent(
      type: InferenceTranscriptEventType.values.firstWhere(
        (final value) => value.name == typeName,
        orElse: () => InferenceTranscriptEventType.warning,
      ),
      timestamp:
          DateTime.tryParse((json['timestamp'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      transcript: json['transcript'] as String?,
      isFinal: json['is_final'] as bool? ?? false,
      sessionState: stateName == null
          ? null
          : InferenceRealtimeSessionState.values.firstWhere(
              (final value) => value.name == stateName,
              orElse: () => InferenceRealtimeSessionState.idle,
            ),
      metrics:
          (json['metrics'] as Map?)
              ?.map(
                (final key, final value) =>
                    MapEntry('$key', value is num ? value : 0),
              )
              .cast<String, num>() ??
          const <String, num>{},
      metadata:
          (json['metadata'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
      error: switch (json['error']) {
        final Map value => InferenceError(
          code: '${value['code'] ?? 'error'}',
          message: '${value['message'] ?? 'Inference realtime error'}',
          details: value['details'],
        ),
        _ => null,
      },
    );
  }
}

abstract interface class InferenceRealtimeSession<TEvent> {
  bool get isConnected;

  Stream<TEvent> get events;

  Future<InferenceResult<void>> connect();

  Future<void> close();

  Future<void> dispose();
}
