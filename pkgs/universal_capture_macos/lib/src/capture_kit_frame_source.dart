import 'dart:async';

import 'package:universal_capture_macos/universal_capture_macos.dart';
import 'package:universal_screencast/universal_screencast.dart';

/// macOS-native [FrameSource]: ScreenCaptureKit frames as JPEG, flowing
/// into the family's declarative pipeline (audience policies, sinks,
/// events) like any other source.
///
/// macOS-only — [start] refuses elsewhere with the family's typed
/// exception.
class CaptureKitFrameSource implements FrameSource {
  /// Creates a source capturing at up to [fps].
  CaptureKitFrameSource({this.displayId = 0, this.fps = 5});

  /// Display to capture; 0 = first available.
  final int displayId;

  /// Frames-per-second cap.
  final int fps;

  final CaptureStream _stream = CaptureStream();
  final _frames = StreamController<Frame>.broadcast();
  StreamSubscription<CaptureFrame>? _subscription;
  int _sequence = 0;
  bool _started = false;
  bool _stopped = false;

  @override
  String get id => 'capturekit-macos';

  @override
  SourceCapabilities get capabilities => SourceCapabilities(
        contentTypes: const ['image/jpeg'],
        maxFps: fps,
      );

  @override
  Stream<Frame> start() {
    if (_stopped) throw StateError('CaptureKitFrameSource is stopped');
    if (_started) return _frames.stream;
    _started = true;
    _subscription = _stream.start(displayId: displayId, fps: fps).listen(
      (captureFrame) {
        _frames.add(
          Frame(
            sourceId: id,
            sequence: ++_sequence,
            revision: 0,
            bytes: captureFrame.bytes,
            contentType: 'image/jpeg',
            capturedAt: DateTime.fromMicrosecondsSinceEpoch(
              captureFrame.timestampUs,
              isUtc: true,
            ),
          ),
        );
      },
      onError: _frames.addError,
    );
    return _frames.stream;
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _subscription?.cancel();
    await _stream.stop();
    await _frames.close();
  }
}
