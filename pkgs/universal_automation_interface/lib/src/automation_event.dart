import 'package:meta/meta.dart';

/// Structured, payload-free automation events.
///
/// Events are metadata only — never frame bytes, never snapshot bodies — so
/// they are safe to log, forward over `--json` surfaces, and assert on in
/// tests. Every event round-trips through [toJson].
sealed class AutomationEvent {
  /// Creates an event.
  const AutomationEvent();

  /// Serializes the event for `--json` surfaces.
  Map<String, Object?> toJson();
}

/// A frame source started emitting.
@immutable
final class SourceStarted extends AutomationEvent {
  /// Creates the event.
  const SourceStarted(this.sourceId);

  /// Identifier of the source that started.
  final String sourceId;

  @override
  Map<String, Object?> toJson() => {
    'type': 'sourceStarted',
    'sourceId': sourceId,
  };

  @override
  String toString() => 'SourceStarted($sourceId)';
}

/// A frame source stopped emitting. [reason] distinguishes requested stops
/// from failures.
@immutable
final class SourceStopped extends AutomationEvent {
  /// Creates the event.
  const SourceStopped(this.sourceId, {this.reason});

  /// Identifier of the source that stopped.
  final String sourceId;

  /// Why it stopped, when not a requested stop.
  final Object? reason;

  @override
  Map<String, Object?> toJson() => {
    'type': 'sourceStopped',
    'sourceId': sourceId,
    if (reason != null) 'reason': reason.toString(),
  };

  @override
  String toString() => 'SourceStopped($sourceId, reason: $reason)';
}

/// A frame was delivered to at least one sink. Carries size metadata, never
/// the bytes themselves.
@immutable
final class FrameDelivered extends AutomationEvent {
  /// Creates the event.
  const FrameDelivered({
    required this.sourceId,
    required this.sequence,
    required this.revision,
    required this.byteLength,
    required this.contentType,
    required this.capturedAt,
  });

  /// Identifier of the source that produced the frame.
  final String sourceId;

  /// Source-side monotonic frame counter.
  final int sequence;

  /// Target revision the frame belongs to.
  final int revision;

  /// Encoded payload size in bytes.
  final int byteLength;

  /// MIME type of the payload, e.g. `image/jpeg`.
  final String contentType;

  /// When the target was captured.
  final DateTime capturedAt;

  @override
  Map<String, Object?> toJson() => {
    'type': 'frameDelivered',
    'sourceId': sourceId,
    'sequence': sequence,
    'revision': revision,
    'byteLength': byteLength,
    'contentType': contentType,
    'capturedAt': capturedAt.toIso8601String(),
  };

  @override
  String toString() =>
      'FrameDelivered(seq: $sequence, $byteLength B $contentType)';
}

/// A sink degraded or left the pipeline; remaining sinks are unaffected.
@immutable
final class SinkDegraded extends AutomationEvent {
  /// Creates the event.
  const SinkDegraded(this.sinkId, this.reason);

  /// Identifier of the sink that degraded.
  final String sinkId;

  /// Human-readable degradation reason.
  final String reason;

  @override
  Map<String, Object?> toJson() => {
    'type': 'sinkDegraded',
    'sinkId': sinkId,
    'reason': reason,
  };

  @override
  String toString() => 'SinkDegraded($sinkId, $reason)';
}

/// Terminal pipeline failure, tagged with a coarse cause category so agents
/// can classify without parsing details.
@immutable
final class PipelineFailed extends AutomationEvent {
  /// Creates the event. [cause] is one of `sourceError`, `composition`,
  /// `allSinksLost`.
  const PipelineFailed(this.cause, {this.detail});

  /// Coarse cause category; see the class docs for the set.
  final String cause;

  /// Optional human-readable detail.
  final String? detail;

  @override
  Map<String, Object?> toJson() => {
    'type': 'pipelineFailed',
    'cause': cause,
    if (detail != null) 'detail': detail,
  };

  @override
  String toString() => 'PipelineFailed($cause, $detail)';
}
