import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_vosk_raw/xsoulspace_inference_vosk_raw.dart';

void main() {
  test('candidateLibraryPaths prioritizes explicit file path', () {
    final loader = VoskRawLibraryLoader(
      runtimeConfig: const VoskRawRuntimeConfig(
        libraryPath: '/tmp/custom/libvosk.dylib',
        librarySearchPaths: <String>['/tmp/search'],
      ),
      platformOverride: VoskRawDesktopPlatform.macos,
    );

    final paths = loader.candidateLibraryPaths();
    expect(paths.first, '/tmp/custom/libvosk.dylib');
    expect(paths, contains('/tmp/search/libvosk.dylib'));
  });

  test('upstream lock metadata is present', () {
    final file = File(
      '/Users/anton/xs/dart_flutter_packages/pkgs/xsoulspace_inference_vosk_raw/tool/upstream_lock.json',
    );
    expect(file.existsSync(), isTrue);
    expect(file.readAsStringSync(), contains('vosk-api'));
  });
}
