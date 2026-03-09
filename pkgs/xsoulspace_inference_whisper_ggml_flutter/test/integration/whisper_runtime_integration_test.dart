import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_ggml/whisper_ggml.dart';
import 'package:xsoulspace_inference_whisper_ggml_flutter/xsoulspace_inference_whisper_ggml_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final runtimeEnabled =
      Platform.environment['WHISPER_RUNTIME_INTEGRATION'] == '1';
  final platformSupported =
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  test(
    'runtime model lifecycle smoke (gated)',
    () async {
      final client = WhisperGgmlFlutterInferenceClient();
      final installed = await client.getInstalledModels();
      expect(installed, isA<List<WhisperModel>>());
    },
    skip: !runtimeEnabled || !platformSupported,
  );
}
