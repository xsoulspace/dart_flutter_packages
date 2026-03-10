import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

void main() {
  test('InferenceRequest STT serialization round-trips', () {
    final request = InferenceRequest.speechToText(
      audioInput: const InferenceAudioInput.bytes(
        bytes: <int>[1, 2, 3, 4],
        mimeType: 'audio/wav',
        sampleRateHz: 16000,
        channelCount: 1,
      ),
      workingDirectory: '/tmp',
      metadata: const <String, dynamic>{'source': 'unit_test'},
    );

    final decoded = InferenceRequest.fromJson(request.toJson());

    expect(decoded.task, InferenceTask.speechToText);
    expect(decoded.audioInput, isNotNull);
    expect(decoded.audioInput!.source, InferenceAudioSource.bytes);
    expect(decoded.audioInput!.bytes, <int>[1, 2, 3, 4]);
    expect(decoded.audioInput!.mimeType, 'audio/wav');
    expect(decoded.metadata['source'], 'unit_test');
  });

  test('InferenceAudioInput microphone serialization round-trips', () {
    const input = InferenceAudioInput.microphone(
      mimeType: 'audio/webm',
      sampleRateHz: 48000,
      channelCount: 1,
    );

    final decoded = InferenceAudioInput.fromJson(input.toJson());

    expect(decoded.source, InferenceAudioSource.microphone);
    expect(decoded.filePath, isNull);
    expect(decoded.bytes, isNull);
    expect(decoded.mimeType, 'audio/webm');
    expect(decoded.sampleRateHz, 48000);
    expect(decoded.channelCount, 1);
  });

  test(
    'InferenceAudioInput infers source when source discriminant is absent',
    () {
      final decoded = InferenceAudioInput.fromJson(const <String, dynamic>{
        'file_path': 'https://example.com/audio.wav',
        'mime_type': 'audio/wav',
      });

      expect(decoded.source, isNull);
      expect(decoded.resolvedSource, InferenceAudioSource.filePath);
      expect(decoded.filePath, 'https://example.com/audio.wav');
    },
  );

  test('InferenceRequest TTS serialization round-trips', () {
    final request = InferenceRequest.textToSpeech(
      text: 'Hello there',
      workingDirectory: '/tmp',
      voiceOptions: const InferenceVoiceOptions(
        voiceId: 'voice-a',
        locale: 'en-US',
        speechRate: 0.9,
        pitch: 1.1,
        providerExtras: <String, dynamic>{'engine': 'system'},
      ),
    );

    final decoded = InferenceRequest.fromJson(request.toJson());

    expect(decoded.task, InferenceTask.textToSpeech);
    expect(decoded.prompt, 'Hello there');
    expect(decoded.voiceOptions, isNotNull);
    expect(decoded.voiceOptions!.voiceId, 'voice-a');
    expect(decoded.voiceOptions!.providerExtras['engine'], 'system');
  });

  test('InferenceResponse speech payload serialization round-trips', () {
    final response = InferenceResponse(
      task: InferenceTask.speechToText,
      output: const <String, dynamic>{},
      transcript: 'Hello, world.',
      normalizedTranscript: 'Hello world',
      segments: const <InferenceSpeechSegment>[
        InferenceSpeechSegment(text: 'Hello', startMs: 0, endMs: 300),
        InferenceSpeechSegment(text: 'world', startMs: 300, endMs: 700),
      ],
      meta: const <String, dynamic>{'provider': 'whisper'},
    );

    final decoded = InferenceResponse.fromJson(response.toJson());

    expect(decoded.task, InferenceTask.speechToText);
    expect(decoded.transcript, 'Hello, world.');
    expect(decoded.normalizedTranscript, 'Hello world');
    expect(decoded.segments.length, 2);
    expect(decoded.segments.first.startMs, 0);
  });

  test('InferenceClient lifecycle methods are callable', () async {
    final client = _FakeInferenceClient();
    expect(client.isAvailable, isFalse);

    final refreshed = await client.refreshAvailability();
    expect(refreshed, isTrue);
    expect(client.isAvailable, isTrue);

    client.resetAvailabilityCache();
    expect(client.isAvailable, isFalse);
  });
}

final class _FakeInferenceClient implements InferenceClient {
  bool _available = false;

  @override
  String get id => 'fake';

  @override
  bool get isAvailable => _available;

  @override
  Set<InferenceTask> get supportedTasks => const <InferenceTask>{
    InferenceTask.structuredText,
  };

  @override
  Future<bool> refreshAvailability() async {
    _available = true;
    return _available;
  }

  @override
  void resetAvailabilityCache() {
    _available = false;
  }

  @override
  Future<InferenceResult<InferenceResponse>> infer(
    final InferenceRequest request,
  ) async {
    return InferenceResult<InferenceResponse>.fail(
      code: 'unsupported',
      message: 'Not implemented in fake',
    );
  }
}
