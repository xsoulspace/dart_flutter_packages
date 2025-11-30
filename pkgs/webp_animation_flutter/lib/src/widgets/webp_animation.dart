import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/sprite_sheet.dart';
import '../core/webp_decoder.dart';
import '../painters/sprite_sheet_painter.dart';
import '../utils/frame_timing.dart';
import 'webp_animation_controller.dart';

/// {@template webp_animation}
/// A widget that displays a WebP animation with efficient sprite sheet rendering.
///
/// Features isolate-based decoding, flexible timing control, and smooth performance.
/// Supports both automatic playback and custom AnimationController integration.
/// {@endtemplate}
class WebpAnimation extends StatefulWidget {
  /// {@macro webp_animation}
  const WebpAnimation({
    super.key,
    required this.asset,
    required this.width,
    required this.height,
    this.autoPlay = true,
    this.loop = true,
    this.speed = 1.0,
    this.respectFrameDelays = true,
    this.fps = 24.0,
    this.controller,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.medium,
    this.builder,
  }) : assert(width > 0, 'width must be positive'),
       assert(height > 0, 'height must be positive'),
       assert(speed > 0, 'speed must be positive'),
       assert(fps > 0, 'fps must be positive');

  /// Asset path to the WebP animation file.
  final String asset;

  /// Width of the animation display area.
  final double width;

  /// Height of the animation display area.
  final double height;

  /// Whether to start playing automatically when loaded.
  final bool autoPlay;

  /// Whether to loop the animation continuously.
  final bool loop;

  /// Playback speed multiplier (1.0 = normal speed).
  final double speed;

  /// Whether to use WebP frame delays (true) or custom FPS (false).
  final bool respectFrameDelays;

  /// Frames per second when respectFrameDelays is false.
  final double fps;

  /// Optional custom AnimationController for advanced control.
  final AnimationController? controller;

  /// How the animation should be fitted within the display area.
  final BoxFit fit;

  /// How the animation should be aligned within the display area.
  final Alignment alignment;

  /// Quality of filtering when scaling the animation.
  final FilterQuality filterQuality;

  /// Optional builder for custom loading/error states.
  ///
  /// If provided, returns a widget instead of the default animation rendering.
  /// Useful for custom loading indicators or error handling.
  final Widget Function(BuildContext context, SpriteSheet? spriteSheet, Object? error)? builder;

  @override
  State<WebpAnimation> createState() => _WebpAnimationState();
}

class _WebpAnimationState extends State<WebpAnimation> with TickerProviderStateMixin {
  late Future<SpriteSheet> _spriteSheetFuture;
  SpriteSheet? _spriteSheet;
  ui.Image? _image;
  Object? _error;

  late AnimationController _animationController;
  WebpAnimationController? _webpController;

  @override
  void initState() {
    super.initState();
    _loadAnimation();
  }

  @override
  void didUpdateWidget(WebpAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Reload if asset changed
    if (oldWidget.asset != widget.asset) {
      _loadAnimation();
    }

    // Update controller if timing parameters changed
    if (oldWidget.respectFrameDelays != widget.respectFrameDelays ||
        oldWidget.fps != widget.fps ||
        oldWidget.speed != widget.speed) {
      _updateAnimationController();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _webpController?.dispose();
    super.dispose();
  }

  void _loadAnimation() {
    _spriteSheetFuture = WebpDecoder.decodeFromAsset(widget.asset);

    _spriteSheetFuture.then((spriteSheet) async {
      if (!mounted) return;

      setState(() {
        _spriteSheet = spriteSheet;
        _error = null;
      });

      // Create GPU image
      try {
        final image = await WebpDecoder.createImageFromSpriteSheet(spriteSheet);
        if (!mounted) return;

        setState(() {
          _image = image;
        });

        // Initialize animation controller
        _initializeAnimationController();

        // Start playback if requested
        if (widget.autoPlay) {
          _animationController.repeat(reverse: false);
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = e;
        });
      }
    }).catchError((error) {
      if (!mounted) return;
      setState(() {
        _error = error;
      });
    });
  }

  void _initializeAnimationController() {
    if (_spriteSheet == null) return;

    // Use provided controller or create our own
    _animationController = widget.controller ?? AnimationController(vsync: this);

    // Update duration based on timing mode
    _updateAnimationController();

    // Create WebpAnimationController wrapper if no custom controller provided
    if (widget.controller == null) {
      _webpController = WebpAnimationController(
        controller: _animationController,
        spriteSheet: _spriteSheet!,
      );
    }
  }

  void _updateAnimationController() {
    if (_spriteSheet == null) return;

    final duration = FrameTiming.getTotalDuration(
      spriteSheet: _spriteSheet!,
      respectFrameDelays: widget.respectFrameDelays,
      fps: widget.fps,
    );

    _animationController.duration = duration * (1.0 / widget.speed);
  }

  @override
  Widget build(BuildContext context) {
    // Use custom builder if provided
    if (widget.builder != null) {
      return widget.builder!(context, _spriteSheet, _error);
    }

    // Default rendering
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: _buildAnimationWidget(),
    );
  }

  Widget _buildAnimationWidget() {
    // Show error state
    if (_error != null) {
      return Container(
        color: Colors.grey[200],
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 8),
              Text(
                'Failed to load animation',
                style: TextStyle(color: Colors.red[700]),
              ),
            ],
          ),
        ),
      );
    }

    // Show loading state
    if (_spriteSheet == null || _image == null) {
      return Container(
        color: Colors.grey[100],
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Render animation
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        final frameIndex = FrameTiming.getFrameIndex(
          spriteSheet: _spriteSheet!,
          progress: _animationController.value,
          respectFrameDelays: widget.respectFrameDelays,
          fps: widget.fps,
        );

        return CustomPaint(
          painter: SpriteSheetPainter(
            image: _image!,
            spriteSheet: _spriteSheet!,
            frameIndex: frameIndex,
            fit: widget.fit,
            alignment: widget.alignment,
            filterQuality: widget.filterQuality,
          ),
        );
      },
    );
  }

  /// Gets the WebpAnimationController for this animation.
  ///
  /// Only available when no custom controller is provided.
  WebpAnimationController? get webpController => _webpController;
}
