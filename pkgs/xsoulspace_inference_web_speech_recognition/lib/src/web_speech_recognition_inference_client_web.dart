import 'web_speech_recognition_adapter.dart';
import 'web_speech_recognition_adapter_web.dart';
import 'web_speech_recognition_inference_client_base.dart';

export 'web_speech_recognition_adapter.dart';
export 'web_speech_recognition_adapter_web.dart'
    show
        BrowserWebSpeechRecognitionAdapter,
        BrowserWebSpeechRecognitionTrackProvider,
        WebSpeechRecognitionAudioTrackHandle,
        WebSpeechRecognitionTrackProvider;

class WebSpeechRecognitionInferenceClient
    extends WebSpeechRecognitionInferenceClientBase {
  WebSpeechRecognitionInferenceClient({
    final WebSpeechRecognitionAdapter? adapter,
  }) : super(adapter: adapter ?? BrowserWebSpeechRecognitionAdapter());
}
