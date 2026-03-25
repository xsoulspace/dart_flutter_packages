import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_elevenlabs_flutter/xsoulspace_inference_elevenlabs_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ElevenLabsSttInferenceClient', () {
    test('supports only speechToText task', () {
      final client = ElevenLabsSttInferenceClient(
        authConfig: const ElevenLabsAuthConfig(apiKey: 'key'),
        httpClient: MockClient((final request) async => http.Response('', 500)),
      );

      expect(client.supportedTasks, const <InferenceTask>{
        InferenceTask.speechToText,
      });
    });

    test('returns task_unsupported for non-STT request', () async {
      final client = ElevenLabsSttInferenceClient(
        authConfig: const ElevenLabsAuthConfig(apiKey: 'key'),
        httpClient: MockClient((final request) async => http.Response('', 500)),
      );

      final result = await client.infer(
        InferenceRequest.textToSpeech(
          text: 'hello',
          voiceOptions: const InferenceVoiceOptions(voiceId: 'voice_1'),
        ),
      );

      expect(result.success, isFalse);
      expect(result.error?.code, errorCodeTaskUnsupported);
    });

    test('returns auth_failed when API key is missing', () async {
      final client = ElevenLabsSttInferenceClient(
        authConfig: const ElevenLabsAuthConfig(),
        httpClient: MockClient((final request) async => http.Response('', 500)),
      );

      final result = await client.infer(
        InferenceRequest.speechToText(
          audioInput: const InferenceAudioInput.bytes(
            bytes: <int>[1, 2, 3],
            mimeType: 'audio/wav',
          ),
        ),
      );

      expect(result.success, isFalse);
      expect(result.error?.code, 'auth_failed');
    });

    test('returns task_unsupported for microphone source', () async {
      final client = ElevenLabsSttInferenceClient(
        authConfig: const ElevenLabsAuthConfig(apiKey: 'key'),
        httpClient: MockClient((final request) async => http.Response('', 500)),
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
      expect(result.error?.details, const <String, dynamic>{
        'reason': 'microphone_requires_realtime_session',
      });
    });

    test('returns transcript and segments for bytes source', () async {
      late Uri requestUri;
      late Map<String, String> requestHeaders;
      late String requestBody;

      final client = ElevenLabsSttInferenceClient(
        authConfig: const ElevenLabsAuthConfig(apiKey: 'test-api-key'),
        httpClient: MockClient((final request) async {
          requestUri = request.url;
          requestHeaders = request.headers;
          requestBody = request.body;

          return http.Response(
            jsonEncode(<String, dynamic>{
              'text': 'Hello world',
              'language_code': 'eng',
              'transcription_id': 'tr_123',
              'words': <Map<String, dynamic>>[
                <String, dynamic>{'text': 'Hello', 'start': 0.0, 'end': 0.3},
                <String, dynamic>{'text': 'world', 'start': 0.3, 'end': 0.6},
              ],
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );

      final result = await client.infer(
        InferenceRequest.speechToText(
          audioInput: const InferenceAudioInput.bytes(
            bytes: <int>[10, 11, 12],
            mimeType: 'audio/wav',
          ),
          metadata: const <String, dynamic>{
            'model_id': 'scribe_v1',
            'language_code': 'eng',
            'diarize': true,
            'tag_audio_events': true,
            'timestamps_granularity': 'word',
          },
        ),
      );

      expect(requestUri.path, '/v1/speech-to-text');
      expect(requestHeaders['xi-api-key'], 'test-api-key');
      expect(
        requestHeaders['content-type']?.startsWith(
          'multipart/form-data; boundary=',
        ),
        isTrue,
      );
      expect(requestBody, contains('name="model_id"'));
      expect(requestBody, contains('scribe_v1'));
      expect(requestBody, contains('name="language_code"'));
      expect(requestBody, contains('name="diarize"'));
      expect(requestBody, contains('name="tag_audio_events"'));

      expect(result.success, isTrue);
      expect(result.data?.task, InferenceTask.speechToText);
      expect(result.data?.transcript, 'Hello world');
      expect(result.data?.normalizedTranscript, 'Hello world');
      expect(result.data?.segments.length, 2);
      expect(result.data?.segments.first.startMs, 0);
      expect(result.data?.segments.last.endMs, 600);
      expect(result.data?.meta['transcription_id'], 'tr_123');
    });

    test('maps HTTP 404 to resource_not_found', () async {
      final client = ElevenLabsSttInferenceClient(
        authConfig: const ElevenLabsAuthConfig(apiKey: 'key'),
        httpClient: MockClient(
          (final request) async => http.Response(
            jsonEncode(<String, dynamic>{'detail': 'Model not found'}),
            404,
            headers: <String, String>{'content-type': 'application/json'},
          ),
        ),
      );

      final result = await client.infer(
        InferenceRequest.speechToText(
          audioInput: const InferenceAudioInput.bytes(
            bytes: <int>[1, 2, 3],
            mimeType: 'audio/wav',
          ),
        ),
      );

      expect(result.success, isFalse);
      expect(result.error?.code, 'resource_not_found');
      expect(result.error?.message, 'Model not found');
    });
  });
}
