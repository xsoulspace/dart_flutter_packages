import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:universal_automation_interface/universal_automation_interface.dart';

import 'capture_bridge_api.dart' show CaptureBridge;
import 'capture_exceptions.dart';
import 'capture_stream_bindings.dart';

/// One live display frame.
class CaptureFrame {
  /// Creates a frame.
  const CaptureFrame(this.bytes, this.timestampUs);

  /// JPEG-encoded payload.
  final Uint8List bytes;

  /// Presentation timestamp in microseconds.
  final int timestampUs;
}

/// Continuous display capture over ScreenCaptureKit.
///
/// Frames arrive as JPEG at up to [start]'s [fps] cap — the native side
/// paces delivery, matching the family rule that pacing lives at the
/// source. `start` once per instance; [stop] is idempotent and ends the
/// stream.
class CaptureStream {
  final _frames = StreamController<CaptureFrame>.broadcast();
  NativeCallable<XsStreamFrameCallbackNative>? _callable;
  int _handle = 0;
  bool _stopped = false;

  /// Starts capture; [displayId] 0 means the first available display.
  ///
  /// Throws [CapturePermissionDeniedException] when screen recording is
  /// not permitted, and [CaptureBridgeException] for other native
  /// failures.
  Stream<CaptureFrame> start({int displayId = 0, int fps = 5}) {
    CaptureBridge.ensureLoaded();
    if (_stopped) throw StateError('CaptureStream is stopped');
    if (_callable != null) return _frames.stream;
    final callable = NativeCallable<XsStreamFrameCallbackNative>.listener(
      (
        Pointer<Uint8> bytes,
        int length,
        int timestampUs,
        Pointer<Void> userData,
      ) {
        if (bytes == nullptr || length <= 0) return;
        if (_frames.isClosed) return;
        _frames.add(
          CaptureFrame(
            Uint8List.fromList(bytes.asTypedList(length)),
            timestampUs,
          ),
        );
      },
    );
    _callable = callable;
    final handle = streamStartNative(
      displayId,
      fps,
      callable.nativeFunction,
      nullptr,
    );
    if (handle == 10) throw CapturePermissionDeniedException();
    if (handle <= 0) {
      throw CaptureBridgeException('stream start failed', code: handle);
    }
    _handle = handle;
    return _frames.stream;
  }

  /// Stops capture. Idempotent.
  ///
  /// The 250 ms drain before closing the native callable is load-bearing:
  /// SCStream's delivery queue can hold an in-flight frame callback that
  /// outlives `stop` itself, and closing the [NativeCallable] under it
  /// crashes the VM ("callback invoked after it has been deleted").
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    if (_handle > 0) {
      final code = streamStopNative(_handle);
      if (code != 0) {
        throw CaptureBridgeException('stream stop failed', code: code);
      }
    }
    await _frames.close();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _callable?.close();
    _callable = null;
  }
}
