import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/sprite_sheet.dart';
import '../core/webp_decoder.dart';
import '../models/webp_animation_item.dart';
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

/// {@template efficient_layer_painter}
/// Optimized CustomPainter that calculates frame indices internally
/// without requiring AnimatedBuilder, eliminating expensive object creation
/// on every frame.
/// {@endtemplate}
class _EfficientLayerPainter extends CustomPainter {
  /// {@macro efficient_layer_painter}
  _EfficientLayerPainter({
    required this.spriteSheets,
    required this.images,
    required this.animations,
    required this.layerController,
    required this.filterQuality,
  }) : super(repaint: layerController?.controller);

  final List<SpriteSheet?> spriteSheets;
  final List<ui.Image?> images;
  final List<WebpAnimationItem> animations;
  final WebpAnimationLayerController? layerController;
  final FilterQuality filterQuality;

  @override
  void paint(final Canvas canvas, final Size size) {
    if (animations.isEmpty) return;

    final paint = Paint()
      ..filterQuality = filterQuality
      ..isAntiAlias = true;

    // Get current frame indices for all animations
    final frameIndices = layerController?.getCurrentFrameIndices() ?? [];

    // Render all animations in a single batch
    for (int i = 0; i < animations.length; i++) {
      final spriteSheet = spriteSheets[i];
      final image = images[i];
      if (spriteSheet == null || image == null) continue;

      final frameIndex = i < frameIndices.length ? frameIndices[i] : 0;

      // Get source rectangle for current frame
      final srcRect = spriteSheet.getFrameRect(frameIndex);

      // Calculate destination rectangle based on item position and size
      final dstRect = Rect.fromLTWH(
        animations[i].position.dx,
        animations[i].position.dy,
        animations[i].size.width,
        animations[i].size.height,
      );

      // Draw the frame slice at the specified position and size
      canvas.drawImageRect(image, srcRect, dstRect, paint);
    }
  }

  @override
  bool shouldRepaint(final _EfficientLayerPainter oldDelegate) {
    // Check basic properties first
    if (spriteSheets.length != oldDelegate.spriteSheets.length ||
        images.length != oldDelegate.images.length ||
        animations.length != oldDelegate.animations.length ||
        filterQuality != oldDelegate.filterQuality) {
      return true;
    }

    // Check if any sprite sheets changed
    for (int i = 0; i < spriteSheets.length; i++) {
      if (spriteSheets[i] != oldDelegate.spriteSheets[i]) return true;
    }

    // Check if any images changed
    for (int i = 0; i < images.length; i++) {
      if (images[i] != oldDelegate.images[i]) return true;
    }

    // Check if any animation items changed
    for (int i = 0; i < animations.length; i++) {
      if (animations[i] != oldDelegate.animations[i]) return true;
    }

    // Controller changes will trigger repaint via repaint parameter
    return false;
  }
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

    // Render all animations in a single CustomPaint with direct repaint
    return CustomPaint(
      isComplex: true,
      painter: _EfficientLayerPainter(
        spriteSheets: _spriteSheets,
        images: _images,
        animations: widget.animations,
        layerController: _layerController,
        filterQuality: widget.filterQuality,
      ),
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
