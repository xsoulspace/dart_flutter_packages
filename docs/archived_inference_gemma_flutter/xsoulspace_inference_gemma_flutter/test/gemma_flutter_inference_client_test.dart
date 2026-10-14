import 'package:flutter_gemma/flutter_gemma.dart' show ModelFileType, ModelType;
import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_gemma_flutter/xsoulspace_inference_gemma_flutter.dart';

void main() {
  group('GemmaModelEntry.bestFor', () {
    final catalog = <GemmaModelEntry>[
      GemmaModelEntry(
        id: 'mobile-only',
        purposes: {GemmaPurpose.structuredToolUse},
        platforms: {GemmaPlatform.android, GemmaPlatform.ios},
        url: 'https://example.com/mobile.task',
        sizeBytes: 1000,
        modelType: ModelType.gemmaIt,
      ),
      GemmaModelEntry(
        id: 'desktop-only',
        purposes: {GemmaPurpose.structuredToolUse},
        platforms: {GemmaPlatform.macos},
        url: 'https://example.com/desktop.litertlm',
        sizeBytes: 2000,
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
      ),
    ];

    test('picks the mobile artifact on android', () {
      expect(
        GemmaModelEntry.bestFor(
          GemmaPurpose.structuredToolUse,
          platform: GemmaPlatform.android,
          catalog: catalog,
        )?.id,
        'mobile-only',
      );
    });

    test('picks the desktop artifact on macos', () {
      expect(
        GemmaModelEntry.bestFor(
          GemmaPurpose.structuredToolUse,
          platform: GemmaPlatform.macos,
          catalog: catalog,
        )?.id,
        'desktop-only',
      );
    });

    test('returns null when no entry covers the platform', () {
      expect(
        GemmaModelEntry.bestFor(
          GemmaPurpose.structuredToolUse,
          platform: GemmaPlatform.web,
          catalog: catalog,
        ),
        isNull,
      );
    });

    test('default catalog covers android and macos for structuredToolUse', () {
      expect(
        GemmaModelEntry.bestFor(
          GemmaPurpose.structuredToolUse,
          platform: GemmaPlatform.android,
        ),
        isNotNull,
      );
      expect(
        GemmaModelEntry.bestFor(
          GemmaPurpose.structuredToolUse,
          platform: GemmaPlatform.macos,
        ),
        isNotNull,
      );
    });
  });

  final validRequest = InferenceRequest(
    prompt: 'Say hello',
    task: InferenceTask.implicitlyStructuredText,
    outputSchema: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'answer': <String, dynamic>{'type': 'string'},
      },
    },
    workingDirectory: '/tmp',
  );

  group('GemmaFlutterInferenceClient', () {
    test('id is gemma_flutter', () {
      expect(GemmaFlutterInferenceClient().id, 'gemma_flutter');
    });

    test('supports text and implicitlyStructuredText tasks', () {
      expect(
        GemmaFlutterInferenceClient().supportedTasks,
        const <InferenceTask>{
          InferenceTask.text,
          InferenceTask.implicitlyStructuredText,
        },
      );
    });

    test('returns task_unsupported for non-text tasks', () async {
      final client = GemmaFlutterInferenceClient();
      final result = await client.infer(
        InferenceRequest.speechToText(
          audioInput: const InferenceAudioInput.filePath(
            filePath: '/tmp/audio.wav',
            mimeType: 'audio/wav',
          ),
        ),
      );

      expect(result.success, isFalse);
      expect(result.error?.code, errorCodeTaskUnsupported);
    });

    group('availability and cache', () {
      test('resetAvailabilityCache sets isAvailable to false', () async {
        GemmaFlutterInferenceClient().resetAvailabilityCache();
        expect(GemmaFlutterInferenceClient().isAvailable, isFalse);
      });

      test('refreshAvailability runs and isAvailable matches result', () async {
        GemmaFlutterInferenceClient().resetAvailabilityCache();
        final available = await GemmaFlutterInferenceClient()
            .refreshAvailability();
        expect(GemmaFlutterInferenceClient().isAvailable, available);
      });
    });

    group('infer validation', () {
      test('fails with request_prompt_empty when prompt is empty', () async {
        GemmaFlutterInferenceClient().resetAvailabilityCache();
        final client = GemmaFlutterInferenceClient();
        final result = await client.infer(
          InferenceRequest(
            prompt: '   ',
            task: InferenceTask.implicitlyStructuredText,
            outputSchema: <String, dynamic>{'type': 'object'},
            workingDirectory: '/tmp',
          ),
        );
        expect(result.success, isFalse);
        expect(result.error?.code, 'request_prompt_empty');
      });

      test(
        'empty workingDirectory does not block structured requests',
        () async {
          final client = GemmaFlutterInferenceClient();
          final result = await client.infer(
            InferenceRequest(
              prompt: 'Hi',
              task: InferenceTask.implicitlyStructuredText,
              outputSchema: <String, dynamic>{'type': 'object'},
              workingDirectory: '   ',
            ),
          );
          // No working-directory validation exists in core; failure (if any)
          // must come from availability, not request validation.
          expect(result.error?.code, isNot('request_working_directory_empty'));
        },
      );

      test(
        'fails with request_schema_empty when outputSchema is empty',
        () async {
          final client = GemmaFlutterInferenceClient();
          final result = await client.infer(
            InferenceRequest(
              prompt: 'Hi',
              task: InferenceTask.implicitlyStructuredText,
              outputSchema: <String, dynamic>{},
              workingDirectory: '/tmp',
            ),
          );
          expect(result.success, isFalse);
          expect(result.error?.code, 'request_schema_empty');
        },
      );
    });

    group('infer when unavailable', () {
      test(
        'returns engine_unavailable when no model (or valid result when model present)',
        () async {
          GemmaFlutterInferenceClient().resetAvailabilityCache();
          await GemmaFlutterInferenceClient().refreshAvailability();
          final client = GemmaFlutterInferenceClient();
          final result = await client.infer(validRequest);
          expect(result.success || result.error != null, isTrue);
          if (!result.success) {
            expect(result.error!.code, isNotEmpty);
            expect([
              'engine_unavailable',
              'output_empty',
              'json_parse_failed',
              'schema_validation_failed',
            ], contains(result.error!.code));
          } else {
            expect(result.data?.structuredOutput, isA<Map<String, dynamic>>());
          }
        },
      );
    });
  });
}
