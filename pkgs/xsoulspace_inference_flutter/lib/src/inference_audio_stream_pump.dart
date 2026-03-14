import 'dart:async';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

final class InferenceAudioStreamPump {
  InferenceAudioStreamPump({
    required this.audioStream,
    required this.audioSink,
  });

  final Stream<List<int>> audioStream;
  final InferenceRealtimeAudioSink audioSink;

  StreamSubscription<List<int>>? _subscription;

  Future<void> start() async {
    await stop();
    _subscription = audioStream.listen((final chunk) {
      unawaited(audioSink.sendAudioChunk(chunk));
    });
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
