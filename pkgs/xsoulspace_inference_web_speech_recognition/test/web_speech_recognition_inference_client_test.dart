import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_web_speech_recognition/xsoulspace_inference_web_speech_recognition.dart';

class _FakeAdapter implements WebSpeechRecognitionAdapter {
  _FakeAdapter({
    required this.hasSpeechRecognitionApi,
    required this.isChromiumFamily,
    this.transcript = 'Hello, world!',
    this.error,
  });

  @override
  bool hasSpeechRecognitionApi;

  @override
  bool isChromiumFamily;

  String transcript;
  WebSpeechRecognitionAdapterException? error;

  InferenceAudioInput? lastAudioInput;
  String? lastLanguage;

  @override
  Future<String> recognize({
    required final InferenceAudioInput audioInput,
    final String? language,
  }) async {
    lastAudioInput = audioInput;
    lastLanguage = language;

    final failure = error;
    if (failure != null) {
      throw failure;
    }

    return transcript;
  }

  @override
  WebSpeechLiveRecognitionSession? startLiveRecognition({String? language}) {
    // TODO: implement startLiveRecognition
    throw UnimplementedError();
  }
}

void main() {
  group('WebSpeechRecognitionInferenceClient', () {
    test('supports only speechToText task', () {
      final client = WebSpeechRecognitionInferenceClient(
        adapter: _FakeAdapter(
          hasSpeechRecognitionApi: true,
          isChromiumFamily: true,
        ),
      );

      expect(client.supportedTasks, const <InferenceTask>{
        InferenceTask.speechToText,
      });
    });

    test('returns task_unsupported for non-STT tasks', () async {
      final client = WebSpeechRecognitionInferenceClient(
        adapter: _FakeAdapter(
          hasSpeechRecognitionApi: true,
          isChromiumFamily: true,
        ),
      );

      final result = await client.infer(
        InferenceRequest.textToSpeech(text: 'hello'),
      );

      expect(result.success, isFalse);
      expect(result.error?.code, errorCodeTaskUnsupported);
    });

    test('returns task_unsupported when speech API is unavailable', () async {
      final client = WebSpeechRecognitionInferenceClient(
        adapter: _FakeAdapter(
          hasSpeechRecognitionApi: false,
          isChromiumFamily: true,
        ),
      );

      final result = await client.infer(
        InferenceRequest.speechToText(
          audioInput: const InferenceAudioInput.microphone(
            mimeType: 'audio/webm',
          ),
        ),
      );

      expect(result.success, isFalse);
      expect(result.error?.code, errorCodeTaskUnsupported);
    });

    test(
      'returns task_unsupported when browser is not chromium-family',
      () async {
        final client = WebSpeechRecognitionInferenceClient(
          adapter: _FakeAdapter(
            hasSpeechRecognitionApi: true,
            isChromiumFamily: false,
          ),
        );

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

    test(
      'maps successful transcript with normalized text and synthetic segment',
      () async {
        final adapter = _FakeAdapter(
          hasSpeechRecognitionApi: true,
          isChromiumFamily: true,
          transcript: 'Hello,   world!',
        );
        final client = WebSpeechRecognitionInferenceClient(adapter: adapter);

        final result = await client.infer(
          InferenceRequest.speechToText(
            audioInput: const InferenceAudioInput.microphone(
              mimeType: 'audio/webm',
            ),
            metadata: const <String, dynamic>{'language': 'en-US'},
          ),
        );

        expect(result.success, isTrue);
        expect(result.data?.task, InferenceTask.speechToText);
        expect(result.data?.transcript, 'Hello,   world!');
        expect(result.data?.normalizedTranscript, 'Hello world');
        expect(result.data?.segments, hasLength(1));
        expect(result.data?.segments.first.startMs, 0);
        expect(result.data?.segments.first.endMs, 0);
        expect(result.data?.segments.first.text, 'Hello,   world!');

        expect(adapter.lastLanguage, 'en-US');
        expect(
          adapter.lastAudioInput?.resolvedSource,
          InferenceAudioSource.microphone,
        );
      },
    );

    test('passes file-path source to adapter', () async {
      final adapter = _FakeAdapter(
        hasSpeechRecognitionApi: true,
        isChromiumFamily: true,
        transcript: 'file transcript',
      );
      final client = WebSpeechRecognitionInferenceClient(adapter: adapter);

      final result = await client.infer(
        InferenceRequest.speechToText(
          audioInput: const InferenceAudioInput.filePath(
            filePath: 'https://example.com/sample.wav',
            mimeType: 'audio/wav',
          ),
        ),
      );

      expect(result.success, isTrue);
      expect(result.data?.transcript, 'file transcript');
      expect(
        adapter.lastAudioInput?.resolvedSource,
        InferenceAudioSource.filePath,
      );
    });

    test(
      'maps permission/service blocked failures to task_unsupported',
      () async {
        final client = WebSpeechRecognitionInferenceClient(
          adapter: _FakeAdapter(
            hasSpeechRecognitionApi: true,
            isChromiumFamily: true,
            error: const WebSpeechRecognitionAdapterException(
              kind: WebSpeechRecognitionFailureKind.permissionOrServiceBlocked,
              reason: 'permission_or_service_blocked',
              message: 'blocked',
            ),
          ),
        );

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

    test('maps invalid input failures to audio_input_invalid', () async {
      final client = WebSpeechRecognitionInferenceClient(
        adapter: _FakeAdapter(
          hasSpeechRecognitionApi: true,
          isChromiumFamily: true,
          error: const WebSpeechRecognitionAdapterException(
            kind: WebSpeechRecognitionFailureKind.invalidCaptureOrInput,
            reason: 'audio_input_or_capture_invalid',
            message: 'invalid input',
          ),
        ),
      );

      final result = await client.infer(
        InferenceRequest.speechToText(
          audioInput: const InferenceAudioInput.bytes(
            bytes: <int>[1, 2, 3],
            mimeType: 'audio/webm',
          ),
        ),
      );

      expect(result.success, isFalse);
      expect(result.error?.code, errorCodeAudioInputInvalid);
    });

    test('maps runtime failures to engine_unavailable', () async {
      final client = WebSpeechRecognitionInferenceClient(
        adapter: _FakeAdapter(
          hasSpeechRecognitionApi: true,
          isChromiumFamily: true,
          error: const WebSpeechRecognitionAdapterException(
            kind: WebSpeechRecognitionFailureKind
                .runtimeEngineOrNetworkOrLanguage,
            reason: 'runtime_engine_or_network_failure',
            message: 'runtime failure',
          ),
        ),
      );

      final result = await client.infer(
        InferenceRequest.speechToText(
          audioInput: const InferenceAudioInput.microphone(
            mimeType: 'audio/webm',
          ),
        ),
      );

      expect(result.success, isFalse);
      expect(result.error?.code, 'engine_unavailable');
    });

    test(
      'maps unsupported audio-track start failures to task_unsupported',
      () async {
        final client = WebSpeechRecognitionInferenceClient(
          adapter: _FakeAdapter(
            hasSpeechRecognitionApi: true,
            isChromiumFamily: true,
            error: const WebSpeechRecognitionAdapterException(
              kind: WebSpeechRecognitionFailureKind.unsupported,
              reason: 'audio_track_start_unsupported',
              message: 'start(audioTrack) unsupported',
            ),
          ),
        );

        final result = await client.infer(
          InferenceRequest.speechToText(
            audioInput: const InferenceAudioInput.filePath(
              filePath: 'https://example.com/audio.wav',
              mimeType: 'audio/wav',
            ),
          ),
        );

        expect(result.success, isFalse);
        expect(result.error?.code, errorCodeTaskUnsupported);
        final details = result.error?.details as Map<String, dynamic>?;
        expect(details?['reason'], 'audio_track_start_unsupported');
      },
    );
  });
}
