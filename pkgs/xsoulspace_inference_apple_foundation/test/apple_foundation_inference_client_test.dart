import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_inference_apple_foundation/xsoulspace_inference_apple_foundation.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

const _channel = MethodChannel('xsoulspace_inference_apple_foundation');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final binaryMessenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    binaryMessenger.setMockMethodCallHandler(_channel, null);
  });

  group('AppleFoundationInferenceClient', () {
    test('id is apple_foundation', () {
      expect(AppleFoundationInferenceClient().id, 'apple_foundation');
    });

    group('isAvailable and refreshAvailability', () {
      test('isAvailable is true after refresh when channel returns true', () async {
        binaryMessenger.setMockMethodCallHandler(
          _channel,
          (MethodCall call) async => call.method == 'isAvailable' ? true : null,
        );
        expect(await AppleFoundationInferenceClient.refreshAvailability(), isTrue);
        expect(AppleFoundationInferenceClient().isAvailable, isTrue);
      });

      test('isAvailable is false after refresh when channel returns false', () async {
        binaryMessenger.setMockMethodCallHandler(
          _channel,
          (MethodCall call) async => call.method == 'isAvailable' ? false : null,
        );
        expect(await AppleFoundationInferenceClient.refreshAvailability(), isFalse);
        expect(AppleFoundationInferenceClient().isAvailable, isFalse);
      });

      test('refreshAvailability returns false on PlatformException', () async {
        binaryMessenger.setMockMethodCallHandler(
          _channel,
          (MethodCall call) async {
            if (call.method == 'isAvailable') {
              throw PlatformException(code: 'unavailable', message: 'Engine off');
            }
            return null;
          },
        );
        expect(await AppleFoundationInferenceClient.refreshAvailability(), isFalse);
        expect(AppleFoundationInferenceClient().isAvailable, isFalse);
      });
    });

    group('infer', () {
      const validRequest = InferenceRequest(
        prompt: 'Say hello',
        outputSchema: <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{'answer': <String, dynamic>{'type': 'string'}},
        },
        workingDirectory: '/tmp',
      );

      test('fails with request_prompt_empty when prompt is empty', () async {
        binaryMessenger.setMockMethodCallHandler(
          _channel,
          (MethodCall call) async => call.method == 'isAvailable' ? true : null,
        );
        await AppleFoundationInferenceClient.refreshAvailability();
        final client = AppleFoundationInferenceClient();
        final result = await client.infer(const InferenceRequest(
          prompt: '   ',
          outputSchema: <String, dynamic>{'type': 'object'},
          workingDirectory: '/tmp',
        ));
        expect(result.success, isFalse);
        expect(result.error?.code, 'request_prompt_empty');
      });

      test('fails with request_working_directory_empty when workingDirectory is empty', () async {
        await AppleFoundationInferenceClient.refreshAvailability();
        final client = AppleFoundationInferenceClient();
        final result = await client.infer(const InferenceRequest(
          prompt: 'Hi',
          outputSchema: <String, dynamic>{'type': 'object'},
          workingDirectory: '   ',
        ));
        expect(result.success, isFalse);
        expect(result.error?.code, 'request_working_directory_empty');
      });

      test('fails with request_schema_empty when outputSchema is empty', () async {
        final client = AppleFoundationInferenceClient();
        final result = await client.infer(const InferenceRequest(
          prompt: 'Hi',
          outputSchema: <String, dynamic>{},
          workingDirectory: '/tmp',
        ));
        expect(result.success, isFalse);
        expect(result.error?.code, 'request_schema_empty');
      });

      test('fails with engine_unavailable when not available', () async {
        binaryMessenger.setMockMethodCallHandler(
          _channel,
          (MethodCall call) async => call.method == 'isAvailable' ? false : null,
        );
        await AppleFoundationInferenceClient.refreshAvailability();
        final client = AppleFoundationInferenceClient();
        final result = await client.infer(validRequest);
        expect(result.success, isFalse);
        expect(result.error?.code, 'engine_unavailable');
      });

      test('succeeds with valid JSON matching schema', () async {
        binaryMessenger.setMockMethodCallHandler(
          _channel,
          (MethodCall call) async {
            if (call.method == 'isAvailable') return true;
            if (call.method == 'generate') return '{"answer": "hello"}';
            return null;
          },
        );
        await AppleFoundationInferenceClient.refreshAvailability();
        final client = AppleFoundationInferenceClient();
        final result = await client.infer(validRequest);
        expect(result.success, isTrue);
        expect(result.data?.output, <String, dynamic>{'answer': 'hello'});
        expect(result.data?.meta['provider'], 'apple_foundation');
      });

      test('fails with codex_output_empty when channel returns empty string', () async {
        binaryMessenger.setMockMethodCallHandler(
          _channel,
          (MethodCall call) async {
            if (call.method == 'isAvailable') return true;
            if (call.method == 'generate') return '';
            return null;
          },
        );
        await AppleFoundationInferenceClient.refreshAvailability();
        final client = AppleFoundationInferenceClient();
        final result = await client.infer(validRequest);
        expect(result.success, isFalse);
        expect(result.error?.code, 'codex_output_empty');
      });

      test('fails with codex_output_empty when channel returns null', () async {
        binaryMessenger.setMockMethodCallHandler(
          _channel,
          (MethodCall call) async {
            if (call.method == 'isAvailable') return true;
            if (call.method == 'generate') return null;
            return null;
          },
        );
        await AppleFoundationInferenceClient.refreshAvailability();
        final client = AppleFoundationInferenceClient();
        final result = await client.infer(validRequest);
        expect(result.success, isFalse);
        expect(result.error?.code, 'codex_output_empty');
      });

      test('fails with json_parse_failed when output is not valid JSON', () async {
        binaryMessenger.setMockMethodCallHandler(
          _channel,
          (MethodCall call) async {
            if (call.method == 'isAvailable') return true;
            if (call.method == 'generate') return 'not json';
            return null;
          },
        );
        await AppleFoundationInferenceClient.refreshAvailability();
        final client = AppleFoundationInferenceClient();
        final result = await client.infer(validRequest);
        expect(result.success, isFalse);
        expect(result.error?.code, 'json_parse_failed');
      });

      test('fails with schema_validation_failed when JSON does not match schema', () async {
        binaryMessenger.setMockMethodCallHandler(
          _channel,
          (MethodCall call) async {
            if (call.method == 'isAvailable') return true;
            if (call.method == 'generate') return '{"wrong": 123}';
            return null;
          },
        );
        await AppleFoundationInferenceClient.refreshAvailability();
        final client = AppleFoundationInferenceClient();
        final schema = <String, dynamic>{
          'type': 'object',
          'required': <String>['answer'],
          'properties': <String, dynamic>{'answer': <String, dynamic>{'type': 'string'}},
        };
        final result = await client.infer(InferenceRequest(
          prompt: 'Hi',
          outputSchema: schema,
          workingDirectory: '/tmp',
        ));
        expect(result.success, isFalse);
        expect(
          result.error?.code,
          anyOf('schema_validation_failed', 'schema_required_keys_missing'),
        );
      });

      test('fails with PlatformException code when channel throws', () async {
        binaryMessenger.setMockMethodCallHandler(
          _channel,
          (MethodCall call) async {
            if (call.method == 'isAvailable') return true;
            if (call.method == 'generate') {
              throw PlatformException(code: 'rate_limited', message: 'Too many requests');
            }
            return null;
          },
        );
        await AppleFoundationInferenceClient.refreshAvailability();
        final client = AppleFoundationInferenceClient();
        final result = await client.infer(validRequest);
        expect(result.success, isFalse);
        expect(result.error?.code, 'rate_limited');
        expect(result.error?.message, 'Too many requests');
      });

      test('uses engine_unavailable when PlatformException has empty code', () async {
        binaryMessenger.setMockMethodCallHandler(
          _channel,
          (MethodCall call) async {
            if (call.method == 'isAvailable') return true;
            if (call.method == 'generate') {
              throw PlatformException(code: '', message: 'Unknown');
            }
            return null;
          },
        );
        await AppleFoundationInferenceClient.refreshAvailability();
        final client = AppleFoundationInferenceClient();
        final result = await client.infer(validRequest);
        expect(result.success, isFalse);
        expect(result.error?.code, 'engine_unavailable');
      });
    });
  });
}
