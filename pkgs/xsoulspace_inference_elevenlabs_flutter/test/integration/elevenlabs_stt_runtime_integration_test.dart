import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_elevenlabs_flutter/xsoulspace_inference_elevenlabs_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final apiKey = Platform.environment['ELEVENLABS_API_KEY']?.trim();
  final audioPath = Platform.environment['ELEVENLABS_STT_AUDIO_PATH']?.trim();
  final enabled =
      (Platform.environment['ELEVENLABS_RUNTIME_INTEGRATION']?.trim() == '1') &&
      (apiKey?.isNotEmpty == true) &&
      (audioPath?.isNotEmpty == true);

  test('runtime STT integration (env gated)', () async {
    final client = ElevenLabsSttInferenceClient(
      authConfig: ElevenLabsAuthConfig(apiKey: apiKey),
    );

    final result = await client.infer(
      InferenceRequest.speechToText(
        audioInput: InferenceAudioInput.filePath(
          filePath: audioPath!,
          mimeType: 'audio/wav',
        ),
      ),
    );

    expect(result.success, isTrue);
    expect((result.data?.transcript ?? '').trim().isNotEmpty, isTrue);
  }, skip: !enabled);
}
