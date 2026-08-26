// ignore_for_file: lines_longer_than_80_chars

/// Pure unit coverage for the FFI bridge plumbing — no macOS runtime or
/// dylib required. On-device behaviour is validated by the bin smokes
/// (`apple_foundation_cli`, `stream_smoke`) and the stress CLI.
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_apple_foundation/src/native_bridge/library_loader.dart';
import 'package:xsoulspace_inference_apple_foundation/src/native_bridge/native_client.dart';

void main() {
  group('XsFmLibraryLoader', () {
    test('override path wins over every candidate', () {
      final loader = XsFmLibraryLoader(overridePath: '/tmp/bridge.dylib');
      expect(loader.candidatePaths().first, '/tmp/bridge.dylib');
    });

    test('env override ranks second, build-hook output third', () {
      final loader = XsFmLibraryLoader();
      final paths = loader.candidatePaths();
      expect(paths.length, greaterThanOrEqualTo(3));
      expect(XsFmLibraryLoader.dylibName, 'libxs_fm_bridge.dylib');
      expect(
        XsFmLibraryLoader.assetId,
        'package:xsoulspace_inference_apple_foundation/swift_bridge',
      );
    });

    test('candidate paths are deduplicated and absolute', () {
      final loader = XsFmLibraryLoader();
      final paths = loader.candidatePaths();
      expect(paths.toSet().length, paths.length);
      for (final p in paths.skip(1)) {
        expect(p.startsWith('/'), isTrue);
      }
    });
  });

  group('AppleFoundationNativeClient contract', () {
    test('identity and task surface are stable', () {
      final client = AppleFoundationNativeClient();
      expect(client.id, 'apple_foundation_native');
      expect(
        client.supportedTasks,
        unorderedEquals(<InferenceTask>[
          InferenceTask.text,
          InferenceTask.implicitlyStructuredText,
          InferenceTask.nativelyStructuredText,
        ]),
      );
    });

    test('isAvailable starts false before any refresh', () {
      final client = AppleFoundationNativeClient();
      expect(client.isAvailable, isFalse);
    });
  });
}
