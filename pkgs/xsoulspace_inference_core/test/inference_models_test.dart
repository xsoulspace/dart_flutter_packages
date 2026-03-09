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
    expect(decoded.audioInput!.bytes, <int>[1, 2, 3, 4]);
    expect(decoded.audioInput!.mimeType, 'audio/wav');
    expect(decoded.metadata['source'], 'unit_test');
  });

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
}
