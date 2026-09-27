import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_capture_macos/universal_capture_macos.dart';
import 'package:universal_screencast/universal_screencast.dart';

void main() {
  test(
    'streams jpeg frames over ScreenCaptureKit',
    () async {
      if (!Platform.isMacOS) return;
      CaptureBridge.ensureLoaded();
      if (!CaptureBridge.screenPermissionPreflight) {
        // Unattended environments have no consent path; skip.
        return;
      }
      final source = CaptureKitFrameSource(fps: 10);
      final frames = source.start().take(3).toList().timeout(
            const Duration(seconds: 20),
          );
      final received = await frames;
      await source.stop();
      expect(received, hasLength(3));
      for (final frame in received) {
        expect(frame.contentType, 'image/jpeg');
        // JPEG SOI marker.
        expect(frame.bytes[0], 0xFF);
        expect(frame.bytes[1], 0xD8);
        expect(frame.bytes.length, greaterThan(500));
      }
    },
    skip: Platform.isMacOS ? false : 'macOS only (native-assets bridge)',
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('frame source refuses off macOS', () {
    if (Platform.isMacOS) return;
    final source = CaptureKitFrameSource();
    expect(source.start, throwsA(isA<Object>()));
  });
}
