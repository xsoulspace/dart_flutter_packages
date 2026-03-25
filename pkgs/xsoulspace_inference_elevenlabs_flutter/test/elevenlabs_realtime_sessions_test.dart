import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_inference_elevenlabs_flutter/xsoulspace_inference_elevenlabs_flutter.dart';

import 'helpers/fake_web_socket_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ElevenLabsRealtimeTtsSession', () {
    test(
      'connects with bearer token preference and sends helper messages',
      () async {
        final fakeChannel = FakeWebSocketChannel();
        addTearDown(fakeChannel.dispose);

        Uri? capturedUri;
        Map<String, dynamic>? capturedHeaders;

        final session = ElevenLabsRealtimeTtsSession(
          authConfig: ElevenLabsAuthConfig(
            apiKey: 'api-key-fallback',
            bearerTokenProvider: () async => 'bearer-token',
          ),
          webSocketConnector: (final uri, {final headers}) {
            capturedUri = uri;
            capturedHeaders = headers;
            return fakeChannel;
          },
        );
        addTearDown(session.dispose);

        final connectResult = await session.connect(
          voiceId: 'voice_123',
          modelId: 'eleven_multilingual_v2',
        );
        expect(connectResult.success, isTrue);
        expect(capturedUri?.path, '/v1/text-to-speech/voice_123/stream-input');
        expect(
          capturedUri?.queryParameters['model_id'],
          'eleven_multilingual_v2',
        );
        expect(capturedHeaders?['authorization'], 'Bearer bearer-token');
        expect(capturedHeaders?.containsKey('xi-api-key'), isFalse);

        await session.initialize();
        await session.sendText(text: 'Hello ', tryTriggerGeneration: true);
        await session.flush();

        final sentPayloads = fakeChannel.sentMessages
            .whereType<String>()
            .map((final item) => jsonDecode(item) as Map<String, dynamic>)
            .toList();

        expect(sentPayloads[0]['text'], ' ');
        expect(sentPayloads[1]['text'], 'Hello ');
        expect(sentPayloads[1]['try_trigger_generation'], true);
        expect(sentPayloads[2]['flush'], true);
      },
    );

    test('emits decoded audio and final markers', () async {
      final fakeChannel = FakeWebSocketChannel();
      addTearDown(fakeChannel.dispose);

      final session = ElevenLabsRealtimeTtsSession(
        authConfig: const ElevenLabsAuthConfig(apiKey: 'api-key'),
        webSocketConnector: (final uri, {final headers}) => fakeChannel,
      );
      addTearDown(session.dispose);

      final events = <ElevenLabsRealtimeTtsEvent>[];
      final subscription = session.events.listen(events.add);
      addTearDown(subscription.cancel);

      final connectResult = await session.connect(voiceId: 'voice_123');
      expect(connectResult.success, isTrue);

      fakeChannel.emitServerMessage(
        jsonEncode(<String, dynamic>{
          'audio': base64Encode(<int>[1, 2, 3]),
        }),
      );
      fakeChannel.emitServerMessage(
        jsonEncode(<String, dynamic>{'isFinal': true}),
      );

      await pumpEventQueue();

      expect(events.length, 2);
      expect(events.first.audioBytes, <int>[1, 2, 3]);
      expect(events.first.isFinal, isFalse);
      expect(events.last.isFinal, isTrue);
    });
  });

  group('ElevenLabsRealtimeSttSession', () {
    test(
      'falls back to API key auth and sends chunk/commit messages',
      () async {
        final fakeChannel = FakeWebSocketChannel();
        addTearDown(fakeChannel.dispose);

        Uri? capturedUri;
        Map<String, dynamic>? capturedHeaders;

        final session = ElevenLabsRealtimeSttSession(
          authConfig: const ElevenLabsAuthConfig(apiKey: 'api-key'),
          webSocketConnector: (final uri, {final headers}) {
            capturedUri = uri;
            capturedHeaders = headers;
            return fakeChannel;
          },
        );
        addTearDown(session.dispose);

        final connectResult = await session.connect(
          modelId: 'scribe_v1',
          audioFormat: 'pcm_16000',
          sampleRate: 16000,
        );
        expect(connectResult.success, isTrue);
        expect(capturedUri?.path, '/v1/speech-to-text/realtime');
        expect(capturedUri?.queryParameters['model_id'], 'scribe_v1');
        expect(capturedHeaders?['xi-api-key'], 'api-key');

        await session.sendAudioChunk(<int>[1, 2, 3], previousText: 'prefix');
        await session.commit();

        final sentPayloads = fakeChannel.sentMessages
            .whereType<String>()
            .map((final item) => jsonDecode(item) as Map<String, dynamic>)
            .toList();

        expect(sentPayloads[0]['message_type'], 'input_audio_chunk');
        expect(sentPayloads[0]['audio_base_64'], base64Encode(<int>[1, 2, 3]));
        expect(sentPayloads[0]['sample_rate'], 16000);
        expect(sentPayloads[0]['previous_text'], 'prefix');

        expect(sentPayloads[1]['commit'], true);
        expect(sentPayloads[1]['audio_base_64'], '');
      },
    );

    test('parses transcript events and marks error message types', () async {
      final fakeChannel = FakeWebSocketChannel();
      addTearDown(fakeChannel.dispose);

      final session = ElevenLabsRealtimeSttSession(
        authConfig: const ElevenLabsAuthConfig(apiKey: 'api-key'),
        webSocketConnector: (final uri, {final headers}) => fakeChannel,
      );
      addTearDown(session.dispose);

      final events = <ElevenLabsRealtimeSttEvent>[];
      final subscription = session.events.listen(events.add);
      addTearDown(subscription.cancel);

      final connectResult = await session.connect();
      expect(connectResult.success, isTrue);

      fakeChannel.emitServerMessage(
        jsonEncode(<String, dynamic>{
          'message_type': 'partial_transcript',
          'transcript': 'hello',
        }),
      );
      fakeChannel.emitServerMessage(
        jsonEncode(<String, dynamic>{
          'message_type': 'auth_error',
          'error': 'invalid auth',
        }),
      );

      await pumpEventQueue();

      expect(events.length, 2);
      expect(events[0].messageType, 'partial_transcript');
      expect(events[0].transcript, 'hello');
      expect(events[0].isError, isFalse);
      expect(events[1].messageType, 'auth_error');
      expect(events[1].isError, isTrue);
    });
  });
}
