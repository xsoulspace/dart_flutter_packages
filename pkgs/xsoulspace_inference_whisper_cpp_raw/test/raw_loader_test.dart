import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_whisper_cpp_raw/xsoulspace_inference_whisper_cpp_raw.dart';

void main() {
  test('candidateLibraryPaths prioritizes explicit file path', () {
    final loader = WhisperCppRawLibraryLoader(
      runtimeConfig: const WhisperCppRawRuntimeConfig(
        libraryPath: '/tmp/custom/libwhisper.dylib',
        librarySearchPaths: <String>['/tmp/search'],
      ),
      platformOverride: WhisperCppRawDesktopPlatform.macos,
    );

    final paths = loader.candidateLibraryPaths();
    expect(paths.first, '/tmp/custom/libwhisper.dylib');
    expect(paths, contains('/tmp/search/libwhisper.dylib'));
  });

  test('upstream lock metadata is present', () {
    final file = File(
      '/Users/anton/xs/dart_flutter_packages/pkgs/xsoulspace_inference_whisper_cpp_raw/tool/upstream_lock.json',
    );
    expect(file.existsSync(), isTrue);
    expect(file.readAsStringSync(), contains('whisper.cpp'));
  });
}
