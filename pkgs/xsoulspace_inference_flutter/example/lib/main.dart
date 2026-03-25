import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_flutter/xsoulspace_inference_flutter.dart';

void main() {
  runApp(const _ExampleApp());
}

class _ExampleApp extends StatefulWidget {
  const _ExampleApp();

  @override
  State<_ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<_ExampleApp> {
  late final _ExampleSession _session;
  late final InferenceTranscriptNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _session = _ExampleSession();
    _notifier = InferenceTranscriptNotifier(session: _session);
    unawaited(_session.emitDemo());
  }

  @override
  void dispose() {
    _notifier.dispose();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    const readiness = InferenceReadinessSnapshot(
      state: InferenceReadinessState.ready,
      summary: 'Inject any provider package here',
    );
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Inference Flutter Example')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: AnimatedBuilder(
            animation: _notifier,
            builder: (final context, final _) {
              return InferenceDiagnosticsPresenter(
                readiness: readiness,
                transcript: _notifier.snapshot,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ExampleSession
    implements InferenceRealtimeSession<InferenceTranscriptEvent> {
  final StreamController<InferenceTranscriptEvent> _controller =
      StreamController<InferenceTranscriptEvent>.broadcast();

  @override
  bool get isConnected => true;

  @override
  Stream<InferenceTranscriptEvent> get events => _controller.stream;

  Future<void> emitDemo() async {
    _controller.add(
      InferenceTranscriptEvent(
        type: InferenceTranscriptEventType.partialTranscript,
        timestamp: DateTime.now().toUtc(),
        transcript: 'Injected provider transcript',
        sessionState: InferenceRealtimeSessionState.streaming,
      ),
    );
  }

  @override
  Future<InferenceResult<void>> connect() async =>
      InferenceResult<void>.ok(null);

  @override
  Future<void> close() async {}

  @override
  Future<void> dispose() async => _controller.close();
}
