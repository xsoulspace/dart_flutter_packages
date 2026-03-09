import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_flutter_tts/xsoulspace_inference_flutter_tts.dart';

class _FakeFlutterTtsDriver implements FlutterTtsDriver {
  String? language;
  double? speechRate;
  double? pitch;
  Map<String, String>? voice;
  bool awaitSynthCalled = false;
  dynamic synthesizeResult = 1;
  Future<void> Function(String text, String filePath)? onSynthesize;

  @override
  Future<dynamic> awaitSynthCompletion(final bool awaitCompletion) async {
    awaitSynthCalled = awaitCompletion;
    return 1;
  }

  @override
  Future<dynamic> setLanguage(final String language) async {
    this.language = language;
    return 1;
  }

  @override
  Future<dynamic> setPitch(final double pitch) async {
    this.pitch = pitch;
    return 1;
  }

  @override
  Future<dynamic> setSpeechRate(final double rate) async {
    speechRate = rate;
    return 1;
  }

  @override
  Future<dynamic> setVoice(final Map<String, String> voice) async {
    this.voice = voice;
    return 1;
  }

  @override
  Future<dynamic> synthesizeToFile(
    final String text,
    final String fileName,
    final bool isFullPath,
  ) async {
    await onSynthesize?.call(text, fileName);
    return synthesizeResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FlutterTtsInferenceClient', () {
    test('supports only textToSpeech task', () {
      final client = FlutterTtsInferenceClient(
        driver: _FakeFlutterTtsDriver(),
        isSupportedPlatform: () => true,
      );

      expect(client.supportedTasks, const <InferenceTask>{
        InferenceTask.textToSpeech,
      });
    });

    test(
      'returns artifact metadata for successful synthesis on supported platform',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('xs_tts_test_');
        addTearDown(() => tempDir.delete(recursive: true));

        final outputFile = File('${tempDir.path}/reply.wav');
        final driver = _FakeFlutterTtsDriver()
          ..onSynthesize = (final text, final filePath) async {
            expect(text, 'Hello from TTS');
            expect(filePath, outputFile.path);
            await File(filePath).writeAsBytes(<int>[1, 2, 3], flush: true);
          };

        final client = FlutterTtsInferenceClient(
          driver: driver,
          isSupportedPlatform: () => true,
        );

        final result = await client.infer(
          InferenceRequest.textToSpeech(
            text: 'Hello from TTS',
            workingDirectory: tempDir.path,
            metadata: <String, dynamic>{
              'output_file_path': outputFile.path,
              'output_mime_type': 'audio/wav',
            },
          ),
        );

        expect(result.success, isTrue);
        expect(result.data?.task, InferenceTask.textToSpeech);
        expect(result.data?.audioArtifact?.filePath, outputFile.path);
        expect(result.data?.audioArtifact?.mimeType, 'audio/wav');
        expect(driver.awaitSynthCalled, isTrue);
      },
    );

    test(
      'returns task_unsupported on unsupported platform (including macOS v1 artifact-only)',
      () async {
        final client = FlutterTtsInferenceClient(
          driver: _FakeFlutterTtsDriver(),
          isSupportedPlatform: () => false,
        );

        final result = await client.infer(
          InferenceRequest.textToSpeech(text: 'Hi'),
        );

        expect(result.success, isFalse);
        expect(result.error?.code, errorCodeTaskUnsupported);
      },
    );

    test('voice options are propagated to provider calls', () async {
      final tempDir = await Directory.systemTemp.createTemp('xs_tts_test_');
      addTearDown(() => tempDir.delete(recursive: true));

      final outputFile = File('${tempDir.path}/voice.wav');
      final driver = _FakeFlutterTtsDriver()
        ..onSynthesize = (final text, final filePath) async {
          await File(filePath).writeAsBytes(<int>[4, 5, 6], flush: true);
        };

      final client = FlutterTtsInferenceClient(
        driver: driver,
        isSupportedPlatform: () => true,
      );

      final result = await client.infer(
        InferenceRequest.textToSpeech(
          text: 'Voice test',
          workingDirectory: tempDir.path,
          metadata: <String, dynamic>{'output_file_path': outputFile.path},
          voiceOptions: const InferenceVoiceOptions(
            voiceId: 'voice-id-1',
            locale: 'en-US',
            speechRate: 0.85,
            pitch: 1.2,
          ),
        ),
      );

      expect(result.success, isTrue);
      expect(driver.language, 'en-US');
      expect(driver.speechRate, 0.85);
      expect(driver.pitch, 1.2);
      expect(driver.voice, isNotNull);
      expect(driver.voice?['name'], 'voice-id-1');
      expect(driver.voice?['locale'], 'en-US');
    });

    test(
      'returns audio_output_unavailable when synth does not produce file',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('xs_tts_test_');
        addTearDown(() => tempDir.delete(recursive: true));

        final outputFile = File('${tempDir.path}/missing.wav');
        final driver = _FakeFlutterTtsDriver();

        final client = FlutterTtsInferenceClient(
          driver: driver,
          isSupportedPlatform: () => true,
        );

        final result = await client.infer(
          InferenceRequest.textToSpeech(
            text: 'No file',
            workingDirectory: tempDir.path,
            metadata: <String, dynamic>{'output_file_path': outputFile.path},
          ),
        );

        expect(result.success, isFalse);
        expect(result.error?.code, errorCodeAudioOutputUnavailable);
      },
    );

    test('returns task_unsupported for non-TTS request', () async {
      final client = FlutterTtsInferenceClient(
        driver: _FakeFlutterTtsDriver(),
        isSupportedPlatform: () => true,
      );

      final result = await client.infer(
        InferenceRequest.speechToText(
          audioInput: const InferenceAudioInput.filePath(
            filePath: '/tmp/a.wav',
            mimeType: 'audio/wav',
          ),
        ),
      );

      expect(result.success, isFalse);
      expect(result.error?.code, errorCodeTaskUnsupported);
    });
  });
}
