import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_inference_flutter_tts/xsoulspace_inference_flutter_tts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final runtimeEnabled =
      Platform.environment['FLUTTER_TTS_RUNTIME_INTEGRATION'] == '1';
  final platformSupported = Platform.isAndroid || Platform.isIOS;

  test(
    'runtime availability smoke (gated)',
    () async {
      final client = FlutterTtsInferenceClient();
      expect(client.supportedTasks.length, 1);
    },
    skip: !runtimeEnabled || !platformSupported,
  );
}
