import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_inference_gemma_flutter/xsoulspace_inference_gemma_flutter.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

void main() {
  const validRequest = InferenceRequest(
    prompt: 'Say hello',
    outputSchema: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{'answer': <String, dynamic>{'type': 'string'}},
    },
    workingDirectory: '/tmp',
  );

  group('GemmaFlutterInferenceClient', () {
    test('id is gemma_flutter', () {
      expect(GemmaFlutterInferenceClient().id, 'gemma_flutter');
    });

    group('availability and cache', () {
      test('resetAvailabilityCache sets isAvailable to false', () async {
        GemmaFlutterInferenceClient.resetAvailabilityCache();
        expect(GemmaFlutterInferenceClient().isAvailable, isFalse);
      });

      test('refreshAvailability runs and isAvailable matches result', () async {
        GemmaFlutterInferenceClient.resetAvailabilityCache();
        final available = await GemmaFlutterInferenceClient.refreshAvailability();
        expect(GemmaFlutterInferenceClient().isAvailable, available);
      });
    });

    group('infer validation', () {
      test('fails with request_prompt_empty when prompt is empty', () async {
        GemmaFlutterInferenceClient.resetAvailabilityCache();
        final client = GemmaFlutterInferenceClient();
        final result = await client.infer(const InferenceRequest(
          prompt: '   ',
          outputSchema: <String, dynamic>{'type': 'object'},
          workingDirectory: '/tmp',
        ));
        expect(result.success, isFalse);
        expect(result.error?.code, 'request_prompt_empty');
      });

      test('fails with request_working_directory_empty when workingDirectory is empty', () async {
        GemmaFlutterInferenceClient.resetAvailabilityCache();
        final client = GemmaFlutterInferenceClient();
        final result = await client.infer(const InferenceRequest(
          prompt: 'Hi',
          outputSchema: <String, dynamic>{'type': 'object'},
          workingDirectory: '   ',
        ));
        expect(result.success, isFalse);
        expect(result.error?.code, 'request_working_directory_empty');
      });

      test('fails with request_schema_empty when outputSchema is empty', () async {
        final client = GemmaFlutterInferenceClient();
        final result = await client.infer(const InferenceRequest(
          prompt: 'Hi',
          outputSchema: <String, dynamic>{},
          workingDirectory: '/tmp',
        ));
        expect(result.success, isFalse);
        expect(result.error?.code, 'request_schema_empty');
      });
    });

    group('infer when unavailable', () {
      test('returns engine_unavailable when no model (or valid result when model present)', () async {
        GemmaFlutterInferenceClient.resetAvailabilityCache();
        await GemmaFlutterInferenceClient.refreshAvailability();
        final client = GemmaFlutterInferenceClient();
        final result = await client.infer(validRequest);
        expect(result.success || result.error != null, isTrue);
        if (!result.success) {
          expect(result.error!.code, isNotEmpty);
          expect(
            ['engine_unavailable', 'codex_output_empty', 'json_parse_failed', 'schema_validation_failed'],
            contains(result.error!.code),
          );
        } else {
          expect(result.data?.output, isA<Map<String, dynamic>>());
        }
      });
    });
  });
}
