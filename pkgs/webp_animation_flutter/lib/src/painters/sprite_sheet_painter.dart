import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/sprite_sheet.dart';

/// {@template sprite_sheet_painter}
/// CustomPainter that efficiently renders a single frame from a sprite sheet.
///
/// Renders only the active frame slice from the sprite sheet texture,
/// minimizing GPU operations and maximizing performance.
/// {@endtemplate}
class SpriteSheetPainter extends CustomPainter {
  /// {@macro sprite_sheet_painter}
  SpriteSheetPainter({
    required this.image,
    required this.spriteSheet,
    required this.frameIndex,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.medium,
  }) : assert(spriteSheet.isValid, 'SpriteSheet must be valid'),
       assert(frameIndex >= 0, 'frameIndex must be non-negative');

  /// The GPU texture containing the sprite sheet.
  final ui.Image image;

  /// The sprite sheet metadata for frame calculations.
  final SpriteSheet spriteSheet;

  /// The current frame index to render.
  final int frameIndex;

  /// How the frame should be fitted within the available space.
  final BoxFit fit;

  /// How the frame should be aligned within the available space.
  final Alignment alignment;

  /// The quality of filtering to apply when scaling the frame.
  final FilterQuality filterQuality;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // Get the source rectangle for the current frame
    final srcRect = spriteSheet.getFrameRect(frameIndex);

    // Calculate destination rectangle based on fit and alignment
    final dstRect = _calculateDestinationRect(size, srcRect.size);

    // Create paint with filtering quality
    final paint = Paint()
      ..filterQuality = filterQuality
      ..isAntiAlias = true;

    // Draw the frame slice
    canvas.drawImageRect(image, srcRect, dstRect, paint);
  }

  /// Calculates the destination rectangle for rendering based on fit and alignment.
  Rect _calculateDestinationRect(Size canvasSize, Size frameSize) {
    final fittedSize = _applyBoxFit(frameSize, canvasSize);

    final offset = alignment.alongSize(canvasSize - fittedSize);

    return Rect.fromLTWH(
      offset.dx,
      offset.dy,
      fittedSize.width,
      fittedSize.height,
    );
  }

  /// Applies BoxFit logic to calculate fitted size.
  Size _applyBoxFit(Size inputSize, Size outputSize) {
    if (inputSize.isEmpty || outputSize.isEmpty) return Size.zero;

    switch (fit) {
      case BoxFit.fill:
        return outputSize;

      case BoxFit.contain:
        final scale = min(outputSize.width / inputSize.width, outputSize.height / inputSize.height);
        return Size(inputSize.width * scale, inputSize.height * scale);

      case BoxFit.cover:
        final scale = max(outputSize.width / inputSize.width, outputSize.height / inputSize.height);
        return Size(inputSize.width * scale, inputSize.height * scale);

      case BoxFit.fitWidth:
        final scale = outputSize.width / inputSize.width;
        return Size(inputSize.width * scale, inputSize.height * scale);

      case BoxFit.fitHeight:
        final scale = outputSize.height / inputSize.height;
        return Size(inputSize.width * scale, inputSize.height * scale);

      case BoxFit.none:
        return inputSize;

      case BoxFit.scaleDown:
        final scale = min(1.0, min(outputSize.width / inputSize.width, outputSize.height / inputSize.height));
        return Size(inputSize.width * scale, inputSize.height * scale);
    }
  }

  @override
  bool shouldRepaint(SpriteSheetPainter oldDelegate) {
    // Only repaint if the frame actually changed or rendering properties changed
    return oldDelegate.frameIndex != frameIndex ||
           oldDelegate.spriteSheet != spriteSheet ||
           oldDelegate.fit != fit ||
           oldDelegate.alignment != alignment ||
           oldDelegate.filterQuality != filterQuality;
  }

  @override
  bool shouldRebuildSemantics(SpriteSheetPainter oldDelegate) {
    // Semantics don't change for frame updates
    return oldDelegate.spriteSheet != spriteSheet;
  }

  @override
  String toString() {
    return 'SpriteSheetPainter('
        'frameIndex: $frameIndex, '
        'spriteSheet: $spriteSheet, '
        'fit: $fit, '
        'alignment: $alignment)';
  }
}
