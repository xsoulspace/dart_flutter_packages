import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_elevenlabs_flutter/xsoulspace_inference_elevenlabs_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ElevenLabsTtsInferenceClient', () {
    test('supports only textToSpeech task', () {
      final client = ElevenLabsTtsInferenceClient(
        authConfig: const ElevenLabsAuthConfig(apiKey: 'key'),
        httpClient: MockClient((final request) async => http.Response('', 500)),
      );

      expect(client.supportedTasks, const <InferenceTask>{
        InferenceTask.textToSpeech,
      });
    });

    test('returns task_unsupported for non-TTS request', () async {
      final client = ElevenLabsTtsInferenceClient(
        authConfig: const ElevenLabsAuthConfig(apiKey: 'key'),
        httpClient: MockClient((final request) async => http.Response('', 500)),
      );

      final result = await client.infer(
        InferenceRequest.speechToText(
          audioInput: const InferenceAudioInput.bytes(
            bytes: <int>[1, 2],
            mimeType: 'audio/wav',
          ),
        ),
      );

      expect(result.success, isFalse);
      expect(result.error?.code, errorCodeTaskUnsupported);
    });

    test('returns auth_failed when api key is missing', () async {
      final client = ElevenLabsTtsInferenceClient(
        authConfig: const ElevenLabsAuthConfig(),
        httpClient: MockClient((final request) async => http.Response('', 500)),
      );

      final result = await client.infer(
        InferenceRequest.textToSpeech(
          text: 'Hello',
          voiceOptions: const InferenceVoiceOptions(voiceId: 'voice_1'),
        ),
      );

      expect(result.success, isFalse);
      expect(result.error?.code, 'auth_failed');
    });

    test('returns request_invalid when voiceId is missing', () async {
      final client = ElevenLabsTtsInferenceClient(
        authConfig: const ElevenLabsAuthConfig(apiKey: 'key'),
        httpClient: MockClient((final request) async => http.Response('', 500)),
      );

      final result = await client.infer(
        InferenceRequest.textToSpeech(
          text: 'Hello',
          voiceOptions: const InferenceVoiceOptions(),
        ),
      );

      expect(result.success, isFalse);
      expect(result.error?.code, 'request_invalid');
      expect(result.error?.details, const <String, dynamic>{
        'reason': 'voice_id_missing',
      });
    });

    test('writes artifact and returns metadata on success', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'xs_elevenlabs_tts_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final expectedBytes = <int>[1, 2, 3, 4];
      late Uri requestUri;
      late Map<String, String> requestHeaders;
      late Map<String, dynamic> requestBody;

      final client = ElevenLabsTtsInferenceClient(
        authConfig: const ElevenLabsAuthConfig(apiKey: 'test-api-key'),
        endpointConfig: ElevenLabsEndpointConfig(
          baseHttp: Uri.parse('https://api.elevenlabs.io'),
          timeout: const Duration(seconds: 5),
        ),
        httpClient: MockClient((final request) async {
          requestUri = request.url;
          requestHeaders = request.headers;
          requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response.bytes(
            expectedBytes,
            200,
            headers: <String, String>{'request-id': 'req_123'},
          );
        }),
      );

      final outputPath = '${tempDir.path}/result.mp3';
      final result = await client.infer(
        InferenceRequest.textToSpeech(
          text: 'Hello from ElevenLabs',
          workingDirectory: tempDir.path,
          metadata: <String, dynamic>{'output_file_path': outputPath},
          voiceOptions: const InferenceVoiceOptions(
            voiceId: 'voice_abc',
            providerExtras: <String, dynamic>{
              'model_id': 'eleven_multilingual_v2',
              'stability': 0.4,
              'similarity_boost': 0.9,
              'style': 0.1,
              'use_speaker_boost': true,
              'speed': 1.1,
              'output_format': 'mp3_44100_128',
              'optimize_streaming_latency': 2,
            },
          ),
        ),
      );

      expect(requestUri.path, '/v1/text-to-speech/voice_abc');
      expect(requestUri.queryParameters['output_format'], 'mp3_44100_128');
      expect(requestUri.queryParameters['optimize_streaming_latency'], '2');
      expect(requestHeaders['xi-api-key'], 'test-api-key');
      expect(requestBody['text'], 'Hello from ElevenLabs');
      expect(requestBody['model_id'], 'eleven_multilingual_v2');
      expect(
        (requestBody['voice_settings'] as Map<String, dynamic>)['stability'],
        0.4,
      );

      expect(result.success, isTrue);
      expect(result.data?.task, InferenceTask.textToSpeech);
      expect(result.data?.audioArtifact?.filePath, outputPath);
      expect(result.data?.audioArtifact?.mimeType, 'audio/mpeg');
      expect(result.data?.meta['request_id'], 'req_123');
      expect(await File(outputPath).readAsBytes(), expectedBytes);
    });

    test('maps HTTP 401 to auth_failed', () async {
      final client = ElevenLabsTtsInferenceClient(
        authConfig: const ElevenLabsAuthConfig(apiKey: 'test-api-key'),
        httpClient: MockClient(
          (final request) async => http.Response(
            jsonEncode(<String, dynamic>{'detail': 'Invalid key'}),
            401,
            headers: <String, String>{'content-type': 'application/json'},
          ),
        ),
      );

      final result = await client.infer(
        InferenceRequest.textToSpeech(
          text: 'hello',
          voiceOptions: const InferenceVoiceOptions(voiceId: 'voice_1'),
        ),
      );

      expect(result.success, isFalse);
      expect(result.error?.code, 'auth_failed');
      expect(result.error?.message, 'Invalid key');
    });
  });
}
