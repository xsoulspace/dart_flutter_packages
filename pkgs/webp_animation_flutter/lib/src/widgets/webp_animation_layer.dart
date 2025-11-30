import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/sprite_sheet.dart';
import '../core/webp_decoder.dart';
import '../models/webp_animation_item.dart';
import '../painters/layer_painter.dart' show AnimationRenderData, LayerPainter;
import 'webp_animation_layer_controller.dart';

/// {@template webp_animation_layer}
/// A widget that efficiently renders multiple WebP animations
/// in a single draw call.
///
/// Batches all animations together for optimal GPU performance, similar to
/// sprite batching in game engines. All animations share
/// the same timing settings.
/// {@endtemplate}
class WebpAnimationLayer extends StatefulWidget {
  /// {@macro webp_animation_layer}
  const WebpAnimationLayer({
    required this.animations,
    super.key,
    this.autoPlay = true,
    this.loop = true,
    this.speed = 1.0,
    this.respectFrameDelays = true,
    this.fps = 24.0,
    this.filterQuality = FilterQuality.medium,
    this.builder,
  }) : assert(animations.length > 0, 'animations list must be non-empty'),
       assert(speed > 0, 'speed must be positive'),
       assert(fps > 0, 'fps must be positive');

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

  /// Quality of filtering when scaling animations.
  final FilterQuality filterQuality;

  /// Optional builder for custom loading/error states.
  ///
  /// Receives lists of sprite sheets and errors for all animations.
  /// Useful for custom loading indicators or error handling.
  final Widget Function(
    BuildContext context,
    List<SpriteSheet?> spriteSheets,
    List<Object?> errors,
  )?
  builder;

  @override
  State<WebpAnimationLayer> createState() => _WebpAnimationLayerState();
}

class _WebpAnimationLayerState extends State<WebpAnimationLayer>
    with TickerProviderStateMixin {
  late List<Future<SpriteSheet>> _spriteSheetFutures;
  late List<SpriteSheet?> _spriteSheets;
  late List<ui.Image?> _images;
  late List<Object?> _errors;

  WebpAnimationLayerController? _layerController;

  bool _allLoaded = false;

  @override
  Widget build(final BuildContext context) {
    // Use custom builder if provided
    if (widget.builder != null) {
      return widget.builder!(context, _spriteSheets, _errors);
    }

    // Default rendering
    return _buildLayerWidget();
  }

  @override
  void didUpdateWidget(final WebpAnimationLayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Check if animations changed
    if (!_areAnimationsEqual(oldWidget.animations, widget.animations)) {
      _layerController?.dispose();
      _layerController = null;
      _initializeState();
    } else {
      // Update timing parameters if they changed
      if (oldWidget.respectFrameDelays != widget.respectFrameDelays ||
          oldWidget.fps != widget.fps ||
          oldWidget.speed != widget.speed) {
        _updateLayerController();
      }
    }
  }

  @override
  void dispose() {
    _layerController?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _initializeState();
  }

  bool _areAnimationsEqual(
    final List<WebpAnimationItem> a,
    final List<WebpAnimationItem> b,
  ) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Widget _buildLayerWidget() {
    // Check if any animations failed to load
    final hasErrors = _errors.any((final error) => error != null);
    if (hasErrors && !_allLoaded) {
      return Container(
        color: Colors.grey[200],
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
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
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    // Render all animations in a single CustomPaint
    return AnimatedBuilder(
      animation:
          _layerController?.controller ?? const AlwaysStoppedAnimation(0),
      builder: (final context, final child) {
        final frameIndices = _layerController?.getCurrentFrameIndices() ?? [];
        final animationData = <AnimationRenderData>[];

        for (int i = 0; i < widget.animations.length; i++) {
          final spriteSheet = _spriteSheets[i];
          final image = _images[i];
          final frameIndex = i < frameIndices.length ? frameIndices[i] : 0;

          if (spriteSheet != null && image != null) {
            animationData.add(
              AnimationRenderData(
                image: image,
                spriteSheet: spriteSheet,
                item: widget.animations[i],
                frameIndex: frameIndex,
              ),
            );
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

  void _initializeState() {
    final count = widget.animations.length;

    _spriteSheets = List.filled(count, null);
    _images = List.filled(count, null);
    _errors = List.filled(count, null);

    // Load all animations in parallel
    _spriteSheetFutures = widget.animations
        .map((final item) => WebpDecoder.decodeFromAsset(item.asset))
        .toList();

    // Load animations
    unawaited(_loadAnimations());
  }

  Future<void> _loadAnimations() async {
    final futures = _spriteSheetFutures.asMap().entries.map((
      final entry,
    ) async {
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

    // Initialize layer controller with loaded sprite sheets
    _layerController = WebpAnimationLayerController(vsync: this);
    _updateLayerController();

    // Start playback if requested
    if (widget.autoPlay && _allLoaded) {
      await _layerController!.play();
    }
  }

  void _updateLayerController() {
    final controller = _layerController;
    if (controller == null) return;
    controller.initialize(
      spriteSheets: _spriteSheets,
      respectFrameDelays: widget.respectFrameDelays,
      fps: widget.fps,
      speed: widget.speed,
    );
  }
}
