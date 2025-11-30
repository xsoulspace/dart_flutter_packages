/// {@template animation_frame}
/// Represents a single frame in a WebP animation with timing information.
///
/// Contains the frame index, delay from WebP metadata, and calculated timestamp
/// for efficient animation playback.
/// {@endtemplate}
class AnimationFrame {
  /// The zero-based frame index in the animation sequence.
  final int index;

  /// The delay duration for this frame as specified in the WebP metadata.
  final Duration delay;

  /// The cumulative timestamp when this frame should be displayed,
  /// calculated as the sum of all previous frame delays.
  final double timestamp;

  /// {@macro animation_frame}
  const AnimationFrame({
    required this.index,
    required this.delay,
    required this.timestamp,
  });

  @override
  int get hashCode => Object.hash(index, delay, timestamp);

  @override
  bool operator ==(covariant AnimationFrame other) {
    if (identical(this, other)) return true;
    return other.index == index &&
        other.delay == delay &&
        other.timestamp == timestamp;
  }

  /// Creates a copy of this frame with modified properties.
  AnimationFrame copyWith({int? index, Duration? delay, double? timestamp}) {
    return AnimationFrame(
      index: index ?? this.index,
      delay: delay ?? this.delay,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  String toString() =>
      'AnimationFrame(index: $index, delay: $delay, timestamp: $timestamp)';
}
