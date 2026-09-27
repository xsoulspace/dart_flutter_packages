import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_automation_conformance/universal_automation_conformance.dart';
import 'package:universal_capture_flutter/universal_capture_flutter.dart';
import 'package:universal_screencast/universal_screencast.dart';

final Uint8List _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3, 4,
]);

void main() {
  group('ToolkitFrameSource', () {
    test('emits PNG frames stamped with the toolkit source id', () async {
      var grabs = 0;
      final source = ToolkitFrameSource(
        grab: () async {
          grabs++;
          return _png;
        },
        interval: const Duration(milliseconds: 5),
      );
      final frames = await source.start().take(3).toList();
      expect(frames, hasLength(3));
      expect(grabs, 3);
      for (final frame in frames) {
        expect(frame.sourceId, 'toolkit-flutter');
        expect(frame.contentType, 'image/png');
        expect(frame.bytes, _png);
      }
      await source.stop();
    });

    test('stop is idempotent and start after stop refuses', () async {
      final source = ToolkitFrameSource(grab: () async => _png);
      source.start();
      await source.stop();
      await source.stop();
      expect(source.start, throwsStateError);
    });

    test('normalizeWsUri turns run announcements into WS endpoints', () {
      expect(
        VmScreenshotGrabber.normalizeWsUri(
          Uri.parse('http://127.0.0.1:8123/AuthCode=/'),
        ).toString(),
        'ws://127.0.0.1:8123/AuthCode=/ws',
      );
      expect(
        VmScreenshotGrabber.normalizeWsUri(
          Uri.parse('ws://127.0.0.1:8123/ws'),
        ).toString(),
        'ws://127.0.0.1:8123/ws',
      );
    });
  });

  frameSourceConformanceTests(
    'ToolkitFrameSource',
    createSource: () async => ToolkitFrameSource(
      grab: () async => _png,
      interval: const Duration(milliseconds: 5),
    ),
  );
}
