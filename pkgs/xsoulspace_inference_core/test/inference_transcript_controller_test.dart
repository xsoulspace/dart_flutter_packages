import 'dart:async';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

class _FakeSession
    implements InferenceRealtimeSession<InferenceTranscriptEvent> {
  final StreamController<InferenceTranscriptEvent> controller =
      StreamController<InferenceTranscriptEvent>.broadcast();

  @override
  bool get isConnected => true;

  @override
  Stream<InferenceTranscriptEvent> get events => controller.stream;

  @override
  Future<InferenceResult<void>> connect() async =>
      InferenceResult<void>.ok(null);

  @override
  Future<void> close() async {}

  @override
  Future<void> dispose() async {
    await controller.close();
  }
}

void main() {
  test(
    'InferenceTranscriptController tracks partial and final transcript',
    () async {
      final session = _FakeSession();
      final controller = InferenceTranscriptController(session: session);
      addTearDown(controller.dispose);
      addTearDown(session.dispose);

      session.controller.add(
        InferenceTranscriptEvent(
          type: InferenceTranscriptEventType.partialTranscript,
          timestamp: DateTime.now().toUtc(),
          transcript: 'hello',
          sessionState: InferenceRealtimeSessionState.streaming,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.snapshot.partialTranscript, 'hello');

      session.controller.add(
        InferenceTranscriptEvent(
          type: InferenceTranscriptEventType.finalTranscript,
          timestamp: DateTime.now().toUtc(),
          transcript: 'hello world',
          isFinal: true,
          sessionState: InferenceRealtimeSessionState.finalizing,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.snapshot.finalTranscript, 'hello world');
      expect(controller.snapshot.partialTranscript, isNull);
    },
  );
}
