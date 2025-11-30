import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'animation_frame.dart';
import 'sprite_sheet.dart';

/// {@template webp_decoder}
/// Handles WebP animation decoding using isolate-based processing.
///
/// This class implements the "deconstruct and ship" strategy:
/// - Background isolate decodes WebP and creates sprite sheet
/// - Main isolate uploads pixels to GPU once
/// - Zero runtime decoding overhead during playback
/// {@endtemplate}
class WebpDecoder {
  /// Cache for decoded sprite sheets by asset path to avoid re-decoding.
  static final Map<String, Future<SpriteSheet>> _cache = {};

  /// Decodes a WebP animation from an asset path to a sprite sheet.
  ///
  /// Uses isolate-based decoding to prevent UI thread blocking.
  /// Results are cached to avoid re-decoding the same animation.
  ///
  /// @ai Use this method to load WebP animations efficiently.
  static Future<SpriteSheet> decodeFromAsset(String assetPath) {
    return _cache.putIfAbsent(assetPath, () => _decodeFromAsset(assetPath));
  }

  /// Clears the decode cache for all assets.
  ///
  /// Useful for memory management or when assets have changed.
  static void clearCache() {
    _cache.clear();
  }

  /// Internal method to decode a WebP animation from an asset.
  static Future<SpriteSheet> _decodeFromAsset(String assetPath) async {
    // Load raw bytes from assets on main isolate
    final byteData = await rootBundle.load(assetPath);
    final buffer = byteData.buffer.asUint8List();

    // Decode in background isolate
    final decodedData = await Isolate.run(() => _decodeAndCreateSpriteSheet(buffer));

    // Convert to SpriteSheet model
    return SpriteSheet(
      pixels: decodedData.pixels,
      width: decodedData.width,
      height: decodedData.height,
      frameWidth: decodedData.frameWidth,
      frameHeight: decodedData.frameHeight,
      frameCount: decodedData.frameCount,
      frames: decodedData.frames,
    );
  }

  /// Converts a decoded WebP animation to a GPU-ready ui.Image.
  ///
  /// This should be called on the main isolate after decoding.
  /// The resulting image contains the entire sprite sheet.
  ///
  /// @ai Call this after decoding to get a GPU texture for rendering.
  static Future<ui.Image> createImageFromSpriteSheet(SpriteSheet spriteSheet) {
    final completer = Completer<ui.Image>();

    ui.decodeImageFromPixels(
      Uint8List.fromList(spriteSheet.pixels),
      spriteSheet.width,
      spriteSheet.height,
      ui.PixelFormat.rgba8888,
      (image) => completer.complete(image),
    );

    return completer.future;
  }
}

/// Internal data structure passed between isolates.
class _DecodedSpriteSheetData {
  final List<int> pixels;
  final int width;
  final int height;
  final int frameWidth;
  final int frameHeight;
  final int frameCount;
  final List<AnimationFrame> frames;

  _DecodedSpriteSheetData({
    required this.pixels,
    required this.width,
    required this.height,
    required this.frameWidth,
    required this.frameHeight,
    required this.frameCount,
    required this.frames,
  });
}

/// BACKGROUND ISOLATE FUNCTION
/// This does the heavy CPU lifting: decoding WebP and creating sprite sheet.
_DecodedSpriteSheetData _decodeAndCreateSpriteSheet(Uint8List webpBytes) {
  // Decode the WebP animation using the image package
  final animation = img.decodeWebP(webpBytes);

  if (animation == null) {
    throw Exception('Failed to decode WebP animation');
  }

  if (animation.numFrames == 0) {
    throw Exception('WebP animation contains no frames');
  }

  // Calculate sprite sheet dimensions
  // Horizontal strip: width = frame_width * frame_count, height = frame_height
  final totalWidth = animation.width * animation.numFrames;
  final totalHeight = animation.height;

  // Create blank sprite sheet image
  final spriteSheet = img.Image(width: totalWidth, height: totalHeight);

  // Build frame metadata
  final frames = <AnimationFrame>[];
  double cumulativeTime = 0.0;

  for (int i = 0; i < animation.numFrames; i++) {
    final frame = animation.frames[i];

    // Copy frame into sprite sheet at correct position
    img.compositeImage(
      spriteSheet,
      frame,
      dstX: i * animation.width,
      dstY: 0,
    );

    // Calculate frame timing
    // WebP frame delays are in milliseconds, convert to seconds for timestamp
    final frameDelayMs = frame.duration > 0 ? frame.duration : 100; // Default 100ms
    final frameDelaySeconds = frameDelayMs / 1000.0;

    frames.add(AnimationFrame(
      index: i,
      delay: Duration(milliseconds: frameDelayMs),
      timestamp: cumulativeTime,
    ));

    cumulativeTime += frameDelaySeconds;
  }

  // Convert to RGBA bytes for Flutter's ui.decodeImageFromPixels
  final rgbaBytes = spriteSheet.getBytes(order: img.ChannelOrder.rgba);

  return _DecodedSpriteSheetData(
    pixels: rgbaBytes,
    width: totalWidth,
    height: totalHeight,
    frameWidth: animation.width,
    frameHeight: animation.height,
    frameCount: animation.numFrames,
    frames: frames,
  );
}
