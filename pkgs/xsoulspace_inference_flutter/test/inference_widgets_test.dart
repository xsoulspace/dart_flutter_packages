import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_flutter/xsoulspace_inference_flutter.dart';

class _FakeSession
    implements
        InferenceRealtimeSession<InferenceTranscriptEvent>,
        InferenceRealtimeAudioSink {
  final StreamController<InferenceTranscriptEvent> controller =
      StreamController<InferenceTranscriptEvent>.broadcast();

  @override
  bool get isConnected => true;

  @override
  Stream<InferenceTranscriptEvent> get events => controller.stream;

  @override
  Future<InferenceResult<void>> commit() async =>
      InferenceResult<void>.ok(null);

  @override
  Future<InferenceResult<void>> connect() async =>
      InferenceResult<void>.ok(null);

  @override
  Future<void> close() async {}

  @override
  Future<void> dispose() async => controller.close();

  @override
  Future<InferenceResult<void>> sendAudioChunk(
    final List<int> audioBytes,
  ) async => InferenceResult<void>.ok(null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('InferencePreflightPanel renders readiness summary', (
    final WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: InferencePreflightPanel(
            snapshot: InferenceReadinessSnapshot(
              state: InferenceReadinessState.unavailable,
              summary: 'Runtime missing',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Runtime missing'), findsOneWidget);
  });

  testWidgets('InferenceTranscriptNotifier updates transcript widgets', (
    final WidgetTester tester,
  ) async {
    final session = _FakeSession();
    final notifier = InferenceTranscriptNotifier(session: session);
    addTearDown(notifier.dispose);
    addTearDown(session.dispose);

    session.controller.add(
      InferenceTranscriptEvent(
        type: InferenceTranscriptEventType.partialTranscript,
        timestamp: DateTime.now().toUtc(),
        transcript: 'hello there',
        sessionState: InferenceRealtimeSessionState.streaming,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: notifier,
            builder: (final context, final _) {
              return InferenceTranscriptPanel(snapshot: notifier.snapshot);
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('hello there'), findsOneWidget);
  });
}
