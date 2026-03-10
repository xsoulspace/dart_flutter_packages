import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_web_speech_recognition/raw.dart' as raw;
import 'package:xsoulspace_inference_web_speech_recognition/xsoulspace_inference_web_speech_recognition.dart';

void main() {
  test(
    'default client reports unavailable and returns task_unsupported',
    () async {
      final client = WebSpeechRecognitionInferenceClient();

      expect(client.isAvailable, isFalse);

      final result = await client.infer(
        InferenceRequest.speechToText(
          audioInput: const InferenceAudioInput.microphone(
            mimeType: 'audio/webm',
          ),
        ),
      );

      expect(result.success, isFalse);
      expect(result.error?.code, errorCodeTaskUnsupported);
    },
  );

  test('raw constructors are guarded on non-web', () {
    expect(
      () => raw.speechRecognitionConstructor,
      throwsA(isA<UnsupportedError>()),
    );
    expect(
      () => raw.webkitSpeechRecognitionConstructor,
      throwsA(isA<UnsupportedError>()),
    );
  });
}
