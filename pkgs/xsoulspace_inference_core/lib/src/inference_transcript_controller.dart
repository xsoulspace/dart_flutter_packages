import 'dart:async';

import 'inference_realtime.dart';
import 'inference_result.dart';

abstract interface class InferenceRealtimeAudioSink {
  Future<InferenceResult<void>> sendAudioChunk(List<int> audioBytes);

  Future<InferenceResult<void>> commit();
}

final class InferenceTranscriptSnapshot {
  const InferenceTranscriptSnapshot({
    this.lastTranscript,
    this.partialTranscript,
    this.finalTranscript,
    this.lastEvent,
    this.error,
    this.sessionState = InferenceRealtimeSessionState.idle,
    this.metadata = const <String, dynamic>{},
  });

  final String? lastTranscript;
  final String? partialTranscript;
  final String? finalTranscript;
  final InferenceTranscriptEvent? lastEvent;
  final InferenceError? error;
  final InferenceRealtimeSessionState sessionState;
  final Map<String, dynamic> metadata;

  InferenceTranscriptSnapshot copyWith({
    final String? lastTranscript,
    final String? partialTranscript,
    final String? finalTranscript,
    final InferenceTranscriptEvent? lastEvent,
    final InferenceError? error,
    final InferenceRealtimeSessionState? sessionState,
    final Map<String, dynamic>? metadata,
    final bool clearPartialTranscript = false,
    final bool clearError = false,
  }) {
    return InferenceTranscriptSnapshot(
      lastTranscript: lastTranscript ?? this.lastTranscript,
      partialTranscript: clearPartialTranscript
          ? null
          : partialTranscript ?? this.partialTranscript,
      finalTranscript: finalTranscript ?? this.finalTranscript,
      lastEvent: lastEvent ?? this.lastEvent,
      error: clearError ? null : error ?? this.error,
      sessionState: sessionState ?? this.sessionState,
      metadata: metadata ?? this.metadata,
    );
  }
}

final class InferenceTranscriptController {
  InferenceTranscriptController({
    final InferenceRealtimeSession<InferenceTranscriptEvent>? session,
  }) {
    if (session != null) {
      attach(session);
    }
  }

  final StreamController<InferenceTranscriptSnapshot> _snapshotsController =
      StreamController<InferenceTranscriptSnapshot>.broadcast();

  StreamSubscription<InferenceTranscriptEvent>? _subscription;
  InferenceTranscriptSnapshot _snapshot = const InferenceTranscriptSnapshot();

  InferenceTranscriptSnapshot get snapshot => _snapshot;

  Stream<InferenceTranscriptSnapshot> get snapshots =>
      _snapshotsController.stream;

  void attach(
    final InferenceRealtimeSession<InferenceTranscriptEvent> session,
  ) {
    _subscription?.cancel();
    _subscription = session.events.listen(_consumeEvent);
  }

  Future<void> detach() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> dispose() async {
    await detach();
    await _snapshotsController.close();
  }

  void _consumeEvent(final InferenceTranscriptEvent event) {
    final nextState = event.sessionState ?? _snapshot.sessionState;
    switch (event.type) {
      case InferenceTranscriptEventType.partialTranscript:
        _snapshot = _snapshot.copyWith(
          lastTranscript: event.transcript,
          partialTranscript: event.transcript,
          lastEvent: event,
          sessionState: nextState,
          metadata: event.metadata,
          clearError: true,
        );
      case InferenceTranscriptEventType.finalTranscript:
        _snapshot = _snapshot.copyWith(
          lastTranscript: event.transcript,
          partialTranscript: null,
          finalTranscript: event.transcript,
          lastEvent: event,
          sessionState: nextState,
          metadata: event.metadata,
          clearPartialTranscript: true,
          clearError: true,
        );
      case InferenceTranscriptEventType.sessionStateChanged:
      case InferenceTranscriptEventType.metrics:
        _snapshot = _snapshot.copyWith(
          lastEvent: event,
          sessionState: nextState,
          metadata: event.metadata,
          clearError: true,
        );
      case InferenceTranscriptEventType.warning:
      case InferenceTranscriptEventType.error:
        _snapshot = _snapshot.copyWith(
          lastEvent: event,
          error: event.error,
          sessionState: nextState,
          metadata: event.metadata,
        );
    }
    _snapshotsController.add(_snapshot);
  }
}
