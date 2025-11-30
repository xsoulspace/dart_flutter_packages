# webp_animation_flutter

High-performance WebP animation library for Flutter using game dev principles. Features isolate-based decoding and efficient sprite sheet rendering for smooth animations even with complex WebP files.

## Features

- **Isolate-based decoding**: WebP decoding happens in background isolates, keeping your UI thread smooth
- **Sprite sheet rendering**: All animation frames are packed into a single GPU texture for efficient rendering
- **Batch rendering**: Render multiple animations in a single draw call with `WebpAnimationLayer`
- **Flexible timing**: Respect original WebP frame delays or use custom FPS for consistent playback
- **Simple API**: Two main widgets with intuitive parameters
- **Performance optimized**: Minimal widget tree overhead and efficient repaint cycles

## Getting Started

Add to your `pubspec.yaml`:

```yaml
dependencies:
  webp_animation_flutter: ^0.1.0-dev.1
```

## Usage

### Single Animation

```dart
import 'package:webp_animation_flutter/webp_animation_flutter.dart';

// Simple auto-playing animation
WebpAnimation(
  asset: 'assets/animations/character.webp',
  width: 100,
  height: 100,
  autoPlay: true,
  loop: true,
)

// Custom FPS animation
WebpAnimation(
  asset: 'assets/animations/effect.webp',
  width: 200,
  height: 150,
  respectFrameDelays: false, // Use custom FPS instead of WebP delays
  fps: 24.0,
  speed: 2.0, // 2x speed
)

// With custom loading/error handling
WebpAnimation(
  asset: 'assets/animations/loading.webp',
  width: 50,
  height: 50,
  builder: (context, spriteSheet, error) {
    if (error != null) {
      return Text('Failed to load animation: $error');
    }
    if (spriteSheet == null) {
      return CircularProgressIndicator();
    }
    // Animation renders automatically
    return SizedBox.shrink();
  },
)
```

### Multiple Animations (Batch Rendering)

```dart
WebpAnimationLayer(
  animations: [
    WebpAnimationItem(
      asset: 'assets/char1.webp',
      position: Offset(10, 20),
      size: Size(100, 100),
    ),
    WebpAnimationItem(
      asset: 'assets/char2.webp',
      position: Offset(150, 50),
      size: Size(80, 80),
    ),
  ],
  autoPlay: true,
  loop: true,
  speed: 1.0,
)
```

## API Reference

### WebpAnimation

Widget for rendering a single WebP animation.

**Parameters:**
- `asset`: Asset path to the WebP file (required)
- `width`: Render width (required)
- `height`: Render height (required)
- `autoPlay`: Whether to start playing automatically (default: true)
- `loop`: Whether to loop the animation (default: true)
- `speed`: Playback speed multiplier (default: 1.0)
- `respectFrameDelays`: Use WebP frame delays if true, custom FPS if false (default: true)
- `fps`: Custom frames per second when `respectFrameDelays` is false (default: 24.0)
- `controller`: Optional AnimationController for advanced control
- `builder`: Optional builder for custom loading/error states

### WebpAnimationLayer

Widget for rendering multiple WebP animations in a single draw call.

**Parameters:**
- `animations`: List of `WebpAnimationItem` objects (required)
- `autoPlay`: Whether to start all animations automatically (default: true)
- `loop`: Whether to loop all animations (default: true)
- `speed`: Playback speed multiplier for all animations (default: 1.0)
- `respectFrameDelays`: Use WebP frame delays if true, custom FPS if false (default: true)
- `fps`: Custom frames per second when `respectFrameDelays` is false (default: 24.0)
- `builder`: Optional builder for custom loading/error states

### WebpAnimationItem

Data class representing a single animation in a layer.

**Parameters:**
- `asset`: Asset path to the WebP file (required)
- `position`: Screen position as Offset (required)
- `size`: Render size as Size (required)

## Performance Notes

This library uses game development principles for optimal performance:

1. **Isolate Decoding**: WebP decoding happens in background isolates, preventing UI thread blocking
2. **Sprite Sheet Rendering**: All frames are packed into a single GPU texture, uploaded once
3. **Batch Rendering**: Multiple animations can be rendered in a single draw call
4. **Efficient Repainting**: Widgets only repaint when the frame actually changes
5. **Memory Efficient**: Raw pixel data is uploaded to GPU and can be garbage collected

## Architecture

The library follows a "deconstruct and ship" strategy:

1. **Background Isolate**: Decodes WebP and creates sprite sheet pixel data
2. **Main Isolate**: Uploads pixels to GPU as `ui.Image`, renders frame slices
3. **Zero Runtime Decoding**: CPU work happens once during loading, not every frame

This approach eliminates the heat problems common with frame-by-frame decoding and provides consistent performance even with large animations.

## Requirements

- Flutter 3.3.0+
- Dart 3.8.1+

## License

MIT License. See LICENSE file for details.
