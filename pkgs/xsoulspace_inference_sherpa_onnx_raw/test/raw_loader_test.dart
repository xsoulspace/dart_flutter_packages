import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_sherpa_onnx_raw/xsoulspace_inference_sherpa_onnx_raw.dart';

void main() {
  test('candidateLibraryPaths prioritizes explicit file path', () {
    final loader = SherpaOnnxRawLibraryLoader(
      runtimeConfig: const SherpaOnnxRawRuntimeConfig(
        libraryPath: '/tmp/custom/libsherpa-onnx-c-api.dylib',
        librarySearchPaths: <String>['/tmp/search'],
      ),
      platformOverride: SherpaOnnxRawDesktopPlatform.macos,
    );

    final paths = loader.candidateLibraryPaths();
    expect(paths.first, '/tmp/custom/libsherpa-onnx-c-api.dylib');
    expect(paths, contains('/tmp/search/libsherpa-onnx-c-api.dylib'));
  });

  test('upstream lock metadata is present', () {
    final file = File(
      '/Users/anton/xs/dart_flutter_packages/pkgs/xsoulspace_inference_sherpa_onnx_raw/tool/upstream_lock.json',
    );
    expect(file.existsSync(), isTrue);
    expect(file.readAsStringSync(), contains('sherpa-onnx'));
  });
}
