import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'web_speech_recognition_adapter.dart';

class NonWebSpeechRecognitionAdapter implements WebSpeechRecognitionAdapter {
  const NonWebSpeechRecognitionAdapter();

  @override
  bool get hasSpeechRecognitionApi => false;

  @override
  bool get isChromiumFamily => false;

  @override
  Future<String> recognize({
    required final InferenceAudioInput audioInput,
    final String? language,
  }) async {
    throw const WebSpeechRecognitionAdapterException(
      kind: WebSpeechRecognitionFailureKind.unsupported,
      reason: 'non_web_runtime',
      message: 'SpeechRecognition is available only on web runtimes.',
    );
  }
}
