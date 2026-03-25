import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

final class InferenceTranscriptNotifier extends ChangeNotifier {
  InferenceTranscriptNotifier({
    final InferenceRealtimeSession<InferenceTranscriptEvent>? session,
  }) : _controller = InferenceTranscriptController(session: session) {
    _subscription = _controller.snapshots.listen(
      (final _) => notifyListeners(),
    );
  }

  final InferenceTranscriptController _controller;
  StreamSubscription<InferenceTranscriptSnapshot>? _subscription;

  InferenceTranscriptSnapshot get snapshot => _controller.snapshot;

  void attach(
    final InferenceRealtimeSession<InferenceTranscriptEvent> session,
  ) {
    _controller.attach(session);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    unawaited(_controller.dispose());
    super.dispose();
  }
}
