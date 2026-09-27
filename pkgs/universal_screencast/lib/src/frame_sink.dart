import 'dart:async';

import 'frame.dart';

/// Consumes frames.
///
/// Sinks must be cheap and never throw from transient failures inside
/// [push] without surfacing them — the pipeline treats a throwing [push]
/// as a sink failure and degrades that sink. [close] is idempotent; an
/// [error] close means the sink must surface the failure to its own
/// consumers before terminating (error-frame-then-close, never silence).
abstract interface class FrameSink {
  /// Stable identifier used in events.
  String get id;

  /// MIME types this sink accepts; `*` accepts anything.
  List<String> get acceptedContentTypes;

  /// Delivers one frame.
  Future<void> push(Frame frame);

  /// Terminates the sink. Idempotent.
  Future<void> close({Object? error});
}
