import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_ggml/whisper_ggml.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_whisper_ggml_flutter/xsoulspace_inference_whisper_ggml_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WhisperGgmlFlutterInferenceClient', () {
    test('supports only speechToText task', () {
      final client = WhisperGgmlFlutterInferenceClient();
      expect(client.supportedTasks, const <InferenceTask>{
        InferenceTask.speechToText,
      });
    });

    test('file-path transcription maps transcript and segments', () async {
      final tempDir = await Directory.systemTemp.createTemp('xs_whisper_test_');
      addTearDown(() => tempDir.delete(recursive: true));

      final audioFile = File('${tempDir.path}/sample.wav');
      await audioFile.writeAsBytes(<int>[1, 2, 3], flush: true);

      final modelFile = File('${tempDir.path}/ggml-base.bin');
      await modelFile.writeAsString('model', flush: true);

      final client = WhisperGgmlFlutterInferenceClient(
        resolveModelPath: (_) async => modelFile.path,
        initModel: (_) async {},
        transcribe:
            ({
              required WhisperModel model,
              required String modelPath,
              required String audioPath,
              required String language,
            }) async {
              expect(audioPath, audioFile.path);
              expect(modelPath, modelFile.path);
              expect(language, 'en');
              return WhisperTranscribeResponse(
                type: 'transcription',
                text: 'Hello, world!',
                segments: <WhisperTranscribeSegment>[
                  WhisperTranscribeSegment(
                    fromTs: const Duration(milliseconds: 0),
                    toTs: const Duration(milliseconds: 900),
                    text: 'Hello, world!',
                  ),
                ],
              );
            },
      );

      final result = await client.infer(
        InferenceRequest.speechToText(
          audioInput: InferenceAudioInput.filePath(
            filePath: audioFile.path,
            mimeType: 'audio/wav',
          ),
        ),
      );

      expect(result.success, isTrue);
      expect(result.data?.task, InferenceTask.speechToText);
      expect(result.data?.transcript, 'Hello, world!');
      expect(result.data?.normalizedTranscript, 'Hello world');
      expect(result.data?.segments.length, 1);
      expect(result.data?.segments.first.startMs, 0);
      expect(result.data?.segments.first.endMs, 900);
    });

    test('bytes input is materialized to temp file and cleaned up', () async {
      final tempDir = await Directory.systemTemp.createTemp('xs_whisper_test_');
      addTearDown(() => tempDir.delete(recursive: true));

      final modelFile = File('${tempDir.path}/ggml-base.bin');
      await modelFile.writeAsString('model', flush: true);

      String? capturedAudioPath;
      final client = WhisperGgmlFlutterInferenceClient(
        resolveModelPath: (_) async => modelFile.path,
        initModel: (_) async {},
        transcribe:
            ({
              required WhisperModel model,
              required String modelPath,
              required String audioPath,
              required String language,
            }) async {
              capturedAudioPath = audioPath;
              expect(File(audioPath).existsSync(), isTrue);
              return WhisperTranscribeResponse(
                type: 'transcription',
                text: 'bytes transcript',
                segments: const <WhisperTranscribeSegment>[],
              );
            },
      );

      final result = await client.infer(
        InferenceRequest.speechToText(
          audioInput: const InferenceAudioInput.bytes(
            bytes: <int>[9, 8, 7, 6],
            mimeType: 'audio/wav',
          ),
        ),
      );

      expect(result.success, isTrue);
      expect(capturedAudioPath, isNotNull);
      expect(File(capturedAudioPath!).existsSync(), isFalse);
    });

    test('returns engine_unavailable when selected model is missing', () async {
      final tempDir = await Directory.systemTemp.createTemp('xs_whisper_test_');
      addTearDown(() => tempDir.delete(recursive: true));

      final missingModelPath = '${tempDir.path}/ggml-base.bin';
      final client = WhisperGgmlFlutterInferenceClient(
        resolveModelPath: (_) async => missingModelPath,
        initModel: (_) async {},
      );

      final result = await client.infer(
        InferenceRequest.speechToText(
          audioInput: const InferenceAudioInput.filePath(
            filePath: '/tmp/audio.wav',
            mimeType: 'audio/wav',
          ),
        ),
      );

      expect(result.success, isFalse);
      expect(result.error?.code, 'engine_unavailable');
    });

    test(
      'returns audio_input_invalid when provider fails to transcribe',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'xs_whisper_test_',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        final audioFile = File('${tempDir.path}/sample.wav');
        await audioFile.writeAsBytes(<int>[1, 2, 3], flush: true);
        final modelFile = File('${tempDir.path}/ggml-base.bin');
        await modelFile.writeAsString('model', flush: true);

        final client = WhisperGgmlFlutterInferenceClient(
          resolveModelPath: (_) async => modelFile.path,
          initModel: (_) async {},
          transcribe:
              ({
                required WhisperModel model,
                required String modelPath,
                required String audioPath,
                required String language,
              }) async {
                throw StateError('decode failed');
              },
        );

        final result = await client.infer(
          InferenceRequest.speechToText(
            audioInput: InferenceAudioInput.filePath(
              filePath: audioFile.path,
              mimeType: 'audio/wav',
            ),
          ),
        );

        expect(result.success, isFalse);
        expect(result.error?.code, errorCodeAudioInputInvalid);
      },
    );

    test('returns task_unsupported for non-STT request', () async {
      final client = WhisperGgmlFlutterInferenceClient();
      final result = await client.infer(
        InferenceRequest.textToSpeech(text: 'hello'),
      );

      expect(result.success, isFalse);
      expect(result.error?.code, errorCodeTaskUnsupported);
    });
  });
}
