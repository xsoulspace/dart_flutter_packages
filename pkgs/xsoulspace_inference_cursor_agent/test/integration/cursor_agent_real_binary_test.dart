import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_cursor_agent/xsoulspace_inference_cursor_agent.dart';

void main() {
  final integrationEnabled =
      Platform.environment['CURSOR_INFERENCE_INTEGRATION'] == '1';
  final skipReason = integrationEnabled
      ? false
      : 'set CURSOR_INFERENCE_INTEGRATION=1 and authenticate via CURSOR_API_KEY or cursor-agent login';

  group('CursorAgentInferenceClient real binary integration', () {
    test(
      'returns schema-compliant output',
      () async {
        final client = _createClient();
        expect(
          client.isAvailable,
          isTrue,
          reason: 'cursor-agent binary unavailable',
        );

        final result = await client.infer(
          InferenceRequest(
            prompt:
                'Return ONLY a JSON object with keys "status" and "items". '
                '"status" must be "ok". '
                '"items" must be an array with one object {"id":"smoke"}.',
            outputSchema: const <String, dynamic>{
              'type': 'object',
              'required': <String>['status', 'items'],
              'properties': <String, dynamic>{
                'status': <String, dynamic>{
                  'type': 'string',
                  'enum': <String>['ok'],
                },
                'items': <String, dynamic>{
                  'type': 'array',
                  'items': <String, dynamic>{
                    'type': 'object',
                    'required': <String>['id'],
                    'properties': <String, dynamic>{
                      'id': <String, dynamic>{'type': 'string'},
                    },
                  },
                },
              },
            },
            workingDirectory: _integrationWorkingDirectory(),
          ),
        );

        expect(
          result.success,
          isTrue,
          reason: result.error?.toJson().toString(),
        );
        expect(result.data?.output['status'], 'ok');
      },
      skip: skipReason,
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'is reliable across repeated runs',
      () async {
        final client = _createClient();
        expect(
          client.isAvailable,
          isTrue,
          reason: 'cursor-agent binary unavailable',
        );

        for (var index = 0; index < 5; index++) {
          final result = await client.infer(
            InferenceRequest(
              prompt:
                  'Return ONLY JSON object {"status":"ok","iteration":$index}.',
              outputSchema: const <String, dynamic>{
                'type': 'object',
                'required': <String>['status', 'iteration'],
                'properties': <String, dynamic>{
                  'status': <String, dynamic>{
                    'type': 'string',
                    'enum': <String>['ok'],
                  },
                  'iteration': <String, dynamic>{'type': 'number'},
                },
              },
              workingDirectory: _integrationWorkingDirectory(),
            ),
          );

          expect(
            result.success,
            isTrue,
            reason: 'run=$index error=${result.error?.toJson()}',
          );
          expect(result.data?.output['status'], 'ok');
        }
      },
      skip: skipReason,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}

String _integrationWorkingDirectory() =>
    Platform.environment['CURSOR_INFERENCE_WORKDIR'] ?? Directory.current.path;

CursorAgentInferenceClient _createClient() {
  final binaryFromEnv = Platform.environment['CURSOR_BINARY'] ?? 'cursor-agent';
  final apiKey = Platform.environment['CURSOR_API_KEY'];
  return CursorAgentInferenceClient(
    binaryName: binaryFromEnv,
    environment: apiKey == null
        ? null
        : <String, String>{'CURSOR_API_KEY': apiKey},
    executionTimeout: const Duration(minutes: 3),
    maxAttempts: 3,
    maxTransientRetries: 2,
    maxTimeoutRetries: 1,
  );
}
