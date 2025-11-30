import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/sprite_sheet.dart';
import '../core/webp_decoder.dart';
import '../models/webp_animation_item.dart';
import '../painters/layer_painter.dart' show LayerPainter, _AnimationRenderData;
import '../utils/frame_timing.dart';
import 'webp_animation_controller.dart';

/// {@template webp_animation_layer}
/// A widget that efficiently renders multiple WebP animations in a single draw call.
///
/// Batches all animations together for optimal GPU performance, similar to
/// sprite batching in game engines. All animations share the same timing settings.
/// {@endtemplate}
class WebpAnimationLayer extends StatefulWidget {
  /// {@macro webp_animation_layer}
  const WebpAnimationLayer({
    super.key,
    required this.animations,
    this.autoPlay = true,
    this.loop = true,
    this.speed = 1.0,
    this.respectFrameDelays = true,
    this.fps = 24.0,
    this.controllers,
    this.filterQuality = FilterQuality.medium,
    this.builder,
  }) : assert(animations.isNotEmpty, 'animations list cannot be empty'),
       assert(speed > 0, 'speed must be positive'),
       assert(fps > 0, 'fps must be positive'),
       assert(controllers == null || controllers.length == animations.length,
              'controllers length must match animations length');

  /// List of animation items to render.
  final List<WebpAnimationItem> animations;

  /// Whether to start all animations automatically when loaded.
  final bool autoPlay;

  /// Whether to loop all animations continuously.
  final bool loop;

  /// Playback speed multiplier for all animations (1.0 = normal speed).
  final double speed;

  /// Whether to use WebP frame delays (true) or custom FPS (false).
  final bool respectFrameDelays;

  /// Frames per second when respectFrameDelays is false.
  final double fps;

  /// Optional controllers for individual animation control.
  ///
  /// If provided, must have the same length as animations.
  /// Each controller controls one animation independently.
  final List<AnimationController>? controllers;

  /// Quality of filtering when scaling animations.
  final FilterQuality filterQuality;

  /// Optional builder for custom loading/error states.
  ///
  /// Receives lists of sprite sheets and errors for all animations.
  /// Useful for custom loading indicators or error handling.
  final Widget Function(BuildContext context, List<SpriteSheet?> spriteSheets, List<Object?> errors)? builder;

  @override
  State<WebpAnimationLayer> createState() => _WebpAnimationLayerState();
}

class _WebpAnimationLayerState extends State<WebpAnimationLayer> with TickerProviderStateMixin {
  late List<Future<SpriteSheet>> _spriteSheetFutures;
  late List<SpriteSheet?> _spriteSheets;
  late List<ui.Image?> _images;
  late List<Object?> _errors;

  late List<AnimationController> _animationControllers;
  late List<WebpAnimationController?> _webpControllers;

  bool _allLoaded = false;

  @override
  void initState() {
    super.initState();
    _initializeState();
  }

  @override
  void didUpdateWidget(WebpAnimationLayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Check if animations changed
    if (!_areAnimationsEqual(oldWidget.animations, widget.animations)) {
      _disposeControllers();
      _initializeState();
    } else {
      // Update timing parameters if they changed
      if (oldWidget.respectFrameDelays != widget.respectFrameDelays ||
          oldWidget.fps != widget.fps ||
          oldWidget.speed != widget.speed) {
        _updateAnimationControllers();
      }
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _initializeState() {
    final count = widget.animations.length;

    _spriteSheets = List.filled(count, null);
    _images = List.filled(count, null);
    _errors = List.filled(count, null);

    // Load all animations in parallel
    _spriteSheetFutures = widget.animations.map((item) =>
      WebpDecoder.decodeFromAsset(item.asset)
    ).toList();

    // Initialize controllers
    _initializeControllers();

    // Load animations
    _loadAnimations();
  }

  void _initializeControllers() {
    final count = widget.animations.length;

    if (widget.controllers != null) {
      // Use provided controllers
      _animationControllers = widget.controllers!;
      _webpControllers = List.filled(count, null);
    } else {
      // Create our own controllers
      _animationControllers = List.generate(count, (index) =>
        AnimationController(vsync: this)
      );
      _webpControllers = List.generate(count, (index) => null);
    }
  }

  void _disposeControllers() {
    // Only dispose controllers we created
    if (widget.controllers == null) {
      for (final controller in _animationControllers) {
        controller.dispose();
      }
    }

    // Dispose WebpAnimationControllers we created
    for (final controller in _webpControllers) {
      controller?.dispose();
    }
  }

  void _loadAnimations() async {
    final futures = _spriteSheetFutures.asMap().entries.map((entry) async {
      final index = entry.key;
      final future = entry.value;

      try {
        final spriteSheet = await future;
        if (!mounted) return;

        setState(() {
          _spriteSheets[index] = spriteSheet;
          _errors[index] = null;
        });

        // Create GPU image
        final image = await WebpDecoder.createImageFromSpriteSheet(spriteSheet);
        if (!mounted) return;

        setState(() {
          _images[index] = image;
        });

        // Create WebpAnimationController if we own the controller
        if (widget.controllers == null) {
          _webpControllers[index] = WebpAnimationController(
            controller: _animationControllers[index],
            spriteSheet: spriteSheet,
          );
        }

      } catch (error) {
        if (!mounted) return;
        setState(() {
          _errors[index] = error;
        });
      }
    });

    // Wait for all animations to load
    await Future.wait(futures);

    if (!mounted) return;

    setState(() {
      _allLoaded = true;
    });

    // Update controllers with proper durations
    _updateAnimationControllers();

    // Start playback if requested
    if (widget.autoPlay && _allLoaded) {
      for (final controller in _animationControllers) {
        controller.repeat(reverse: false);
      }
    }
  }

  void _updateAnimationControllers() {
    for (int i = 0; i < _animationControllers.length; i++) {
      final spriteSheet = _spriteSheets[i];
      if (spriteSheet != null) {
        final duration = FrameTiming.getTotalDuration(
          spriteSheet: spriteSheet,
          respectFrameDelays: widget.respectFrameDelays,
          fps: widget.fps,
        );

        _animationControllers[i].duration = duration * (1.0 / widget.speed);
      }
    }
  }

  bool _areAnimationsEqual(List<WebpAnimationItem> a, List<WebpAnimationItem> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // Use custom builder if provided
    if (widget.builder != null) {
      return widget.builder!(context, _spriteSheets, _errors);
    }

    // Default rendering
    return _buildLayerWidget();
  }

  Widget _buildLayerWidget() {
    // Check if any animations failed to load
    final hasErrors = _errors.any((error) => error != null);
    if (hasErrors && !_allLoaded) {
      return Container(
        color: Colors.grey[200],
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 8),
              Text(
                'Some animations failed to load',
                style: TextStyle(color: Colors.red[700]),
              ),
            ],
          ),
        ),
      );
    }

    // Show loading state
    if (!_allLoaded) {
      return Container(
        color: Colors.grey[100],
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Render all animations in a single CustomPaint
    return AnimatedBuilder(
      animation: Listenable.merge(_animationControllers),
      builder: (context, child) {
        final animationData = <_AnimationRenderData>[];

        for (int i = 0; i < widget.animations.length; i++) {
          final spriteSheet = _spriteSheets[i];
          final image = _images[i];

          if (spriteSheet != null && image != null) {
            final frameIndex = FrameTiming.getFrameIndex(
              spriteSheet: spriteSheet,
              progress: _animationControllers[i].value,
              respectFrameDelays: widget.respectFrameDelays,
              fps: widget.fps,
            );

            animationData.add(_AnimationRenderData(
              image: image,
              spriteSheet: spriteSheet,
              item: widget.animations[i],
              frameIndex: frameIndex,
            ));
          }
        }

        return CustomPaint(
          painter: LayerPainter(
            animationData: animationData,
            filterQuality: widget.filterQuality,
          ),
        );
      },
    );
  }

  /// Gets the WebpAnimationControllers for all animations.
  ///
  /// Only available when no custom controllers are provided.
  List<WebpAnimationController?> get webpControllers => _webpControllers;
}
