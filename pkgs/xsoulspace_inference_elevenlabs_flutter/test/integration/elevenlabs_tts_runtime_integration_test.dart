import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_elevenlabs_flutter/xsoulspace_inference_elevenlabs_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final apiKey = Platform.environment['ELEVENLABS_API_KEY']?.trim();
  final voiceId = Platform.environment['ELEVENLABS_TEST_VOICE_ID']?.trim();
  final enabled =
      (Platform.environment['ELEVENLABS_RUNTIME_INTEGRATION']?.trim() == '1') &&
      (apiKey?.isNotEmpty == true) &&
      (voiceId?.isNotEmpty == true);

  test('runtime TTS integration (env gated)', () async {
    final tempDir = await Directory.systemTemp.createTemp('elevenlabs_tts_it_');
    addTearDown(() => tempDir.delete(recursive: true));

    final client = ElevenLabsTtsInferenceClient(
      authConfig: ElevenLabsAuthConfig(apiKey: apiKey),
    );

    final result = await client.infer(
      InferenceRequest.textToSpeech(
        text: 'Hello from xsoulspace integration test.',
        workingDirectory: tempDir.path,
        voiceOptions: InferenceVoiceOptions(voiceId: voiceId),
      ),
    );

    expect(result.success, isTrue);
    expect(result.data?.audioArtifact, isNotNull);
    final artifactPath = result.data!.audioArtifact!.filePath;
    expect(await File(artifactPath).exists(), isTrue);
  }, skip: !enabled);
}
