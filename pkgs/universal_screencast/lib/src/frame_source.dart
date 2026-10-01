import 'dart:async';

import 'frame.dart';

/// Produces frames from an automation target.
///
/// Implementations own their capture loop and keep pacing/single-flight at
/// the source (the source-pacing rule: the source paces, never the
/// consumers). [start] may be called once per source lifecycle; [stop] is
/// idempotent and ends the returned stream without further frames.
abstract interface class FrameSource {
  /// Stable identifier used in events.
  String get id;

  /// Declared production capabilities.
  SourceCapabilities get capabilities;

  /// Starts capture and returns the frame stream.
  Stream<Frame> start();

  /// Stops capture. Idempotent; no frames arrive after this completes.
  Future<void> stop();
}
