import 'web_speech_recognition_adapter.dart';
import 'web_speech_recognition_adapter_stub.dart';
import 'web_speech_recognition_inference_client_base.dart';

export 'web_speech_recognition_adapter.dart';

class WebSpeechRecognitionInferenceClient
    extends WebSpeechRecognitionInferenceClientBase {
  WebSpeechRecognitionInferenceClient({
    final WebSpeechRecognitionAdapter? adapter,
  }) : super(adapter: adapter ?? const NonWebSpeechRecognitionAdapter());
}
