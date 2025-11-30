import 'package:flutter/material.dart';

import '../core/sprite_sheet.dart';

/// {@template webp_animation_controller}
/// Convenience wrapper around AnimationController for WebP animation control.
///
/// Provides high-level methods for controlling animation playback while
/// maintaining access to the underlying AnimationController for advanced use.
/// {@endtemplate}
class WebpAnimationController {
  /// {@macro webp_animation_controller}
  WebpAnimationController({
    required this.controller,
    required this.spriteSheet,
  });

  /// The underlying AnimationController that drives the animation.
  final AnimationController controller;

  /// The sprite sheet containing animation data.
  final SpriteSheet spriteSheet;

  /// Gets the current frame index being displayed.
  ///
  /// @ai Use this to track which frame is currently visible.
  int get currentFrame {
    final progress = controller.value;
    return (progress * (spriteSheet.frameCount - 1)).round().clamp(
      0,
      spriteSheet.frameCount - 1,
    );
  }

  /// Whether the animation has completed its full cycle.
  ///
  /// @ai Use this to detect animation completion.
  bool get isCompleted => controller.value >= 1.0;

  /// Whether the animation is currently playing.
  ///
  /// @ai Check this to determine animation state.
  bool get isPlaying => controller.isAnimating;

  /// Disposes of the controller and cleans up resources.
  ///
  /// @ai Always call this when the controller is no longer needed.
  void dispose() {
    controller.dispose();
  }

  /// Pauses the animation at the current frame.
  ///
  /// @ai Call this to pause animation playback.
  void pause() {
    controller.stop();
  }

  /// Starts the animation from the beginning.
  ///
  /// @ai Call this to begin animation playback.
  Future<void> play() => controller.forward(from: 0);

  /// Resets the animation to the first frame and stops playback.
  ///
  /// @ai Call this to return to the beginning of the animation.
  void reset() {
    controller.reset();
  }

  /// Seeks to a specific frame index.
  ///
  /// @ai Use this for frame-based navigation.
  void seekToFrame(final int frameIndex) {
    final clampedFrame = frameIndex.clamp(0, spriteSheet.frameCount - 1);
    final progress = clampedFrame / (spriteSheet.frameCount - 1);
    controller.value = progress;
  }

  /// Sets the playback speed multiplier.
  ///
  /// Values > 1.0 play faster, values < 1.0 play slower.
  ///
  /// @ai Use this to control animation speed dynamically.
  void setSpeed(final double speed) {
    controller.duration = spriteSheet.totalDuration * (1.0 / speed);
  }

  @override
  String toString() =>
      'WebpAnimationController('
      'currentFrame: $currentFrame, '
      'isPlaying: $isPlaying, '
      'isCompleted: $isCompleted)';
}
