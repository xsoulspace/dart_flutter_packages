import 'package:flutter/material.dart';

import '../core/sprite_sheet.dart';
import '../utils/frame_timing.dart';

/// {@template webp_animation_layer_controller}
/// Internal controller that manages a single AnimationController for the game
/// loop pattern in WebpAnimationLayer. Encapsulates frame calculation logic
/// and provides unified control over all animations in the layer.
/// {@endtemplate}
class WebpAnimationLayerController {
  /// {@macro webp_animation_layer_controller}
  WebpAnimationLayerController({
    required final TickerProvider vsync,
    this.fps = 24,
    this.speed = 1,
    this.respectFrameDelays = true,
  }) : _animationController = AnimationController(vsync: vsync);

  /// The underlying AnimationController that drives all animations.
  final AnimationController _animationController;

  /// Current sprite sheets for all animations.
  List<SpriteSheet?> _spriteSheets = [];

  /// Current timing configuration.
  bool respectFrameDelays;

  double fps;
  double speed;

  /// Whether the controller has been initialized.
  bool _initialized = false;

  /// Gets the AnimationController for use in AnimatedBuilder.
  AnimationController get controller => _animationController;

  /// Whether the animation loop has completed
  /// (only meaningful for non-looping).
  bool get isCompleted => _animationController.value >= 1.0;

  /// Whether any animations are currently playing.
  bool get isPlaying => _animationController.isAnimating;

  /// Disposes of the controller and cleans up resources.
  void dispose() {
    _animationController.dispose();
  }

  /// Calculates and returns the current frame indices for all animations.
  ///
  /// Returns a list where each index corresponds to the current frame
  /// for that animation in the layer. Returns empty list if not initialized.
  List<int> getCurrentFrameIndices() {
    if (!_initialized || _spriteSheets.isEmpty) {
      return [];
    }

    final currentProgress = _animationController.value;
    final frameIndices = <int>[];

    for (final spriteSheet in _spriteSheets) {
      if (spriteSheet != null) {
        final frameIndex = FrameTiming.getFrameIndex(
          spriteSheet: spriteSheet,
          progress: currentProgress,
          respectFrameDelays: respectFrameDelays,
          fps: fps,
        );
        frameIndices.add(frameIndex);
      } else {
        frameIndices.add(0); // Default frame for unloaded animations
      }
    }

    return frameIndices;
  }

  /// Initializes the controller with animation data and timing configuration.
  ///
  /// Must be called after all sprite sheets are loaded.
  void initialize({
    required final List<SpriteSheet?> spriteSheets,
    required final bool respectFrameDelays,
    required final double fps,
    required final double speed,
  }) {
    _spriteSheets = spriteSheets.nonNulls.toList();
    this.respectFrameDelays = respectFrameDelays;
    this.fps = fps;
    this.speed = speed;

    // Calculate the maximum duration among all animations
    // This ensures all animations complete at the same time in the unified loop
    Duration maxDuration = Duration.zero;
    for (int i = 0; i < _spriteSheets.length; i++) {
      final spriteSheet = _spriteSheets[i];
      if (spriteSheet != null) {
        final duration = FrameTiming.getTotalDuration(
          spriteSheet: spriteSheet,
          respectFrameDelays: this.respectFrameDelays,
          fps: this.fps,
        );
        if (duration > maxDuration) {
          maxDuration = duration;
        }
      }
    }

    // Set controller duration, adjusted for speed
    _animationController.duration = maxDuration * (1.0 / this.speed);
    _initialized = true;
  }

  /// Pauses all animations at their current frames.
  void pause() => _animationController.stop();

  /// Starts playing all animations.
  ///
  /// Animations will loop continuously.
  Future<void> play() => _animationController.repeat();

  /// Resets all animations to their first frames and stops playback.
  void reset() => _animationController.reset();

  /// Seeks to a specific progress point (0.0 to 1.0).
  ///
  /// All animations will jump to the corresponding frame.
  void seek(final double progress) {
    _animationController.value = progress.clamp(0.0, 1.0);
  }

  /// Updates the timing configuration.
  ///
  /// Should be called when timing parameters change.
  void updateTiming({
    required final bool respectFrameDelays,
    required final double fps,
    required final double speed,
  }) {
    if (!_initialized) return;

    this.respectFrameDelays = respectFrameDelays;
    this.fps = fps;
    this.speed = speed;

    // Recalculate duration
    Duration maxDuration = Duration.zero;
    for (final spriteSheet in _spriteSheets) {
      if (spriteSheet != null) {
        final duration = FrameTiming.getTotalDuration(
          spriteSheet: spriteSheet,
          respectFrameDelays: this.respectFrameDelays,
          fps: this.fps,
        );
        if (duration > maxDuration) {
          maxDuration = duration;
        }
      }
    }

    _animationController.duration = maxDuration * (1.0 / this.speed);
  }
}
