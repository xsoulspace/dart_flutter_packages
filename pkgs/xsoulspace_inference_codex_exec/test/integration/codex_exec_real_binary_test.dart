import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_codex_exec/xsoulspace_inference_codex_exec.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

void main() {
  final integrationEnabled =
      Platform.environment['CODEX_INFERENCE_INTEGRATION'] == '1';
  final hasOfficialExecAuth = (Platform.environment['CODEX_API_KEY'] ?? '')
      .trim()
      .isNotEmpty;
  final skipReason = !integrationEnabled
      ? 'set CODEX_INFERENCE_INTEGRATION=1 to run real codex integration tests'
      : hasOfficialExecAuth
      ? false
      : 'set CODEX_API_KEY (official codex exec auth) to run integration tests';

  group('CodexExecInferenceClient real binary integration', () {
    test(
      'returns schema-compliant output',
      () async {
        final client = _createClient();
        expect(client.isAvailable, isTrue, reason: 'codex binary unavailable');

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
        expect(client.isAvailable, isTrue, reason: 'codex binary unavailable');

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
    Platform.environment['CODEX_INFERENCE_WORKDIR'] ?? Directory.current.path;

CodexExecInferenceClient _createClient() {
  final binaryFromEnv = Platform.environment['CODEX_BINARY'] ?? 'codex';
  final apiKey = Platform.environment['CODEX_API_KEY'];
  return CodexExecInferenceClient(
    binaryName: binaryFromEnv,
    environment: apiKey == null
        ? null
        : <String, String>{'CODEX_API_KEY': apiKey},
    executionTimeout: const Duration(minutes: 3),
    maxAttempts: 3,
    maxTransientRetries: 2,
    maxTimeoutRetries: 1,
  );
}
