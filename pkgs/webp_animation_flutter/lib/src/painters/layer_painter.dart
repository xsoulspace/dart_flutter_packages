import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/sprite_sheet.dart';
import '../models/webp_animation_item.dart';

/// {@template layer_painter}
/// CustomPainter that efficiently renders multiple WebP animations in a single draw call.
///
/// Batches all animations into one paint operation for optimal GPU performance,
/// similar to sprite batching in game engines.
/// {@endtemplate}
class LayerPainter extends CustomPainter {
  /// {@macro layer_painter}
  LayerPainter({
    required this.animationData,
    this.filterQuality = FilterQuality.medium,
  });

  /// List of animation data containing images, sprite sheets, positions, and current frame indices.
  final List<_AnimationRenderData> animationData;

  /// The quality of filtering to apply when scaling animations.
  final FilterQuality filterQuality;

  @override
  void paint(Canvas canvas, Size size) {
    if (animationData.isEmpty) return;

    final paint = Paint()
      ..filterQuality = filterQuality
      ..isAntiAlias = true;

    // Render all animations in a single batch
    for (final data in animationData) {
      if (data.image == null) continue;

      // Get source rectangle for current frame
      final srcRect = data.spriteSheet.getFrameRect(data.frameIndex);

      // Calculate destination rectangle based on item position and size
      final dstRect = Rect.fromLTWH(
        data.item.position.dx,
        data.item.position.dy,
        data.item.size.width,
        data.item.size.height,
      );

      // Draw the frame slice at the specified position and size
      canvas.drawImageRect(data.image!, srcRect, dstRect, paint);
    }
  }

  @override
  bool shouldRepaint(LayerPainter oldDelegate) {
    // Repaint if the animation data has changed
    if (animationData.length != oldDelegate.animationData.length) {
      return true;
    }

    // Check if any frame indices have changed
    for (int i = 0; i < animationData.length; i++) {
      if (animationData[i].frameIndex != oldDelegate.animationData[i].frameIndex ||
          animationData[i].image != oldDelegate.animationData[i].image ||
          animationData[i].item != oldDelegate.animationData[i].item) {
        return true;
      }
    }

    return filterQuality != oldDelegate.filterQuality;
  }

  @override
  bool shouldRebuildSemantics(LayerPainter oldDelegate) {
    // Semantics change if the number of animations changes
    return animationData.length != oldDelegate.animationData.length;
  }

  @override
  String toString() {
    return 'LayerPainter(animationCount: ${animationData.length}, filterQuality: $filterQuality)';
  }
}

/// Internal data structure for rendering a single animation in a layer.
class _AnimationRenderData {
  const _AnimationRenderData({
    required this.image,
    required this.spriteSheet,
    required this.item,
    required this.frameIndex,
  });

  final ui.Image? image;
  final SpriteSheet spriteSheet;
  final WebpAnimationItem item;
  final int frameIndex;

  @override
  String toString() {
    return '_AnimationRenderData('
        'image: ${image != null ? "loaded" : "null"}, '
        'frameIndex: $frameIndex, '
        'item: $item)';
  }
}
