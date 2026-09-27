import 'dart:typed_data';

import 'package:meta/meta.dart';

/// One captured frame.
///
/// Frames are pixels only. Semantic truth lives in
/// `universal_automation_interface`'s [Snapshot-like] trees; a frame never
/// claims to be more than an image (`frames != semantics`).
@immutable
class Frame {
  /// Creates a frame.
  const Frame({
    required this.sourceId,
    required this.sequence,
    required this.revision,
    required this.bytes,
    required this.contentType,
    required this.capturedAt,
  });

  /// Identifier of the producing source.
  final String sourceId;

  /// Source-side monotonic counter, strictly increasing.
  final int sequence;

  /// Target revision the frame belongs to (bumps on navigation).
  final int revision;

  /// Encoded payload bytes.
  final Uint8List bytes;

  /// Payload MIME type: `image/jpeg` or `image/png`.
  final String contentType;

  /// When the target was captured.
  final DateTime capturedAt;

  @override
  String toString() =>
      'Frame($sourceId#$sequence, ${bytes.length} B, $contentType)';
}

/// What a frame source can produce, declared before composition.
@immutable
class SourceCapabilities {
  /// Creates capabilities.
  const SourceCapabilities({
    this.contentTypes = const ['image/jpeg'],
    this.damageDriven = false,
    this.maxFps,
  });

  /// MIME types this source can emit.
  final List<String> contentTypes;

  /// True when frames arrive on target damage only (idle target = idle
  /// stream), as with CDP screencast.
  final bool damageDriven;

  /// Upper bound on frames per second, when known.
  final int? maxFps;

  /// Whether [contentType] is producible.
  bool produces(String contentType) =>
      contentTypes.contains(contentType) || contentTypes.contains('*');

  @override
  String toString() =>
      'SourceCapabilities(${contentTypes.join('|')}, damage: $damageDriven)';
}
