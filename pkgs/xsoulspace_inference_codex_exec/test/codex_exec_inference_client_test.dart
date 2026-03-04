import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_codex_exec/xsoulspace_inference_codex_exec.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

void main() {
  final shellSkipReason = Platform.isWindows
      ? 'shell script tests require a Unix-like environment'
      : null;

  group('CodexExecInferenceClient', () {
    test(
      'infer parses structured output from codex output file',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'xsoulspace_codex_test_',
        );
        addTearDown(() => temp.delete(recursive: true));

        final script = await _createExecutableScript(temp, _successScript());
        final client = CodexExecInferenceClient(binaryName: script.path);

        final result = await client.infer(
          _request(
            temp.path,
            outputSchema: const <String, dynamic>{
              'type': 'object',
              'required': <String>['suggestions'],
              'properties': <String, dynamic>{
                'suggestions': <String, dynamic>{'type': 'array'},
              },
            },
          ),
        );

        expect(result.success, isTrue);
        final suggestions = result.data!.output['suggestions'] as List<dynamic>;
        expect(suggestions, isNotEmpty);
      },
      skip: shellSkipReason,
    );

    test(
      'infer retries with fallback args for legacy codex flags',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'xsoulspace_codex_test_',
        );
        addTearDown(() => temp.delete(recursive: true));

        final script = await _createExecutableScript(temp, _legacyScript());
        final client = CodexExecInferenceClient(binaryName: script.path);
        final result = await client.infer(
          _request(
            temp.path,
            outputSchema: const <String, dynamic>{
              'type': 'object',
              'required': <String>['ok'],
              'properties': <String, dynamic>{
                'ok': <String, dynamic>{'type': 'boolean'},
              },
            },
          ),
        );

        expect(result.success, isTrue);
        expect(result.data!.output['ok'], isTrue);
        expect(result.data!.warnings, isNotEmpty);
        expect(result.data!.meta['fallback_used'], isTrue);
        expect(result.data!.meta['attempt_count'], 2);
      },
      skip: shellSkipReason,
    );

    test('infer retries transient process errors', () async {
      final temp = await Directory.systemTemp.createTemp(
        'xsoulspace_codex_test_',
      );
      addTearDown(() => temp.delete(recursive: true));

      final script = await _createExecutableScript(temp, _transientScript());
      final client = CodexExecInferenceClient(
        binaryName: script.path,
        maxTransientRetries: 1,
      );
      final result = await client.infer(
        _request(
          temp.path,
          outputSchema: const <String, dynamic>{
            'type': 'object',
            'required': <String>['ok'],
            'properties': <String, dynamic>{
              'ok': <String, dynamic>{'type': 'boolean'},
            },
          },
        ),
      );

      expect(result.success, isTrue);
      expect(result.data!.output['ok'], isTrue);
      expect(result.data!.meta['attempt_count'], 2);
    }, skip: shellSkipReason);

    test(
      'infer fails with timeout error when process exceeds executionTimeout',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'xsoulspace_codex_test_',
        );
        addTearDown(() => temp.delete(recursive: true));

        final script = await _createExecutableScript(temp, _timeoutScript());
        final client = CodexExecInferenceClient(
          binaryName: script.path,
          executionTimeout: const Duration(milliseconds: 150),
          maxTimeoutRetries: 0,
          maxAttempts: 1,
        );
        final result = await client.infer(
          _request(
            temp.path,
            outputSchema: const <String, dynamic>{
              'type': 'object',
              'required': <String>['ok'],
            },
          ),
        );

        expect(result.success, isFalse);
        expect(result.error?.code, 'codex_exec_timeout');
      },
      skip: shellSkipReason,
    );

    test('infer fails when binary is unavailable', () async {
      final client = CodexExecInferenceClient(
        binaryName: '/tmp/not-found-codex',
      );
      final result = await client.infer(
        _request(
          Directory.current.path,
          outputSchema: const <String, dynamic>{'type': 'object'},
        ),
      );

      expect(result.success, isFalse);
      expect(result.error?.code, 'engine_unavailable');
    }, skip: shellSkipReason);

    test(
      'infer maps authentication failures to codex_auth_failed',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'xsoulspace_codex_test_',
        );
        addTearDown(() => temp.delete(recursive: true));

        final script = await _createExecutableScript(
          temp,
          _authFailureScript(),
        );
        final client = CodexExecInferenceClient(
          binaryName: script.path,
          maxAttempts: 1,
        );
        final result = await client.infer(
          _request(
            temp.path,
            outputSchema: const <String, dynamic>{'type': 'object'},
          ),
        );

        expect(result.success, isFalse);
        expect(result.error?.code, 'codex_auth_failed');
        final details = result.error?.details as Map<String, dynamic>?;
        expect(details?['auth_failure'], isTrue);
        final remediation = details?['remediation'] as List<dynamic>?;
        expect(remediation?.join(' '), contains('CODEX_API_KEY'));
      },
      skip: shellSkipReason,
    );

    test('infer fails when working directory is missing', () async {
      final client = CodexExecInferenceClient(binaryName: '/bin/sh');
      final result = await client.infer(
        _request(
          '/tmp/xsoulspace_missing_dir_for_inference',
          outputSchema: const <String, dynamic>{'type': 'object'},
        ),
      );

      expect(result.success, isFalse);
      expect(result.error?.code, 'working_directory_not_found');
    });

    test(
      'infer fails when codex output exceeds maxOutputBytes',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'xsoulspace_codex_test_',
        );
        addTearDown(() => temp.delete(recursive: true));

        final script = await _createExecutableScript(
          temp,
          _largeOutputScript(),
        );
        final client = CodexExecInferenceClient(
          binaryName: script.path,
          maxOutputBytes: 120,
        );
        final result = await client.infer(
          _request(
            temp.path,
            outputSchema: const <String, dynamic>{
              'type': 'object',
              'required': <String>['payload'],
            },
          ),
        );

        expect(result.success, isFalse);
        expect(result.error?.code, 'codex_output_too_large');
      },
      skip: shellSkipReason,
    );

    test('infer validates nested schema and reports mismatch', () async {
      final temp = await Directory.systemTemp.createTemp(
        'xsoulspace_codex_test_',
      );
      addTearDown(() => temp.delete(recursive: true));

      final script = await _createExecutableScript(
        temp,
        _nestedSchemaMismatchScript(),
      );
      final client = CodexExecInferenceClient(binaryName: script.path);
      final result = await client.infer(
        _request(
          temp.path,
          outputSchema: const <String, dynamic>{
            'type': 'object',
            'required': <String>['items'],
            'properties': <String, dynamic>{
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
        ),
      );

      expect(result.success, isFalse);
      expect(result.error?.code, 'schema_type_mismatch');
    }, skip: shellSkipReason);

    test(
      'infer remains stable across repeated sequential requests',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'xsoulspace_codex_test_',
        );
        addTearDown(() => temp.delete(recursive: true));

        final script = await _createExecutableScript(temp, _stableScript());
        final client = CodexExecInferenceClient(binaryName: script.path);

        for (var index = 0; index < 20; index++) {
          final result = await client.infer(
            _request(
              temp.path,
              prompt: 'request $index',
              outputSchema: const <String, dynamic>{
                'type': 'object',
                'required': <String>['status'],
                'properties': <String, dynamic>{
                  'status': <String, dynamic>{'type': 'string'},
                },
              },
            ),
          );
          expect(result.success, isTrue, reason: 'failed at iteration=$index');
          expect(result.data!.output['status'], 'ok');
        }
      },
      skip: shellSkipReason,
    );

    test('infer remains stable across parallel requests', () async {
      final temp = await Directory.systemTemp.createTemp(
        'xsoulspace_codex_test_',
      );
      addTearDown(() => temp.delete(recursive: true));

      final script = await _createExecutableScript(temp, _stableScript());
      final client = CodexExecInferenceClient(binaryName: script.path);

      final results = await Future.wait(
        List<Future<InferenceResult<InferenceResponse>>>.generate(
          8,
          (final index) => client.infer(
            _request(
              temp.path,
              prompt: 'parallel request $index',
              outputSchema: const <String, dynamic>{
                'type': 'object',
                'required': <String>['status'],
                'properties': <String, dynamic>{
                  'status': <String, dynamic>{'type': 'string'},
                },
              },
            ),
          ),
        ),
      );

      for (final result in results) {
        expect(result.success, isTrue);
        expect(result.data!.output['status'], 'ok');
      }
    }, skip: shellSkipReason);
  });
}

InferenceRequest _request(
  final String workingDirectory, {
  final String prompt = 'return json',
  required final Map<String, dynamic> outputSchema,
}) => InferenceRequest(
  prompt: prompt,
  outputSchema: outputSchema,
  workingDirectory: workingDirectory,
);

Future<File> _createExecutableScript(
  final Directory directory,
  final String content,
) async {
  final script = File('${directory.path}/codex');
  await script.writeAsString(content);
  final chmodResult = await Process.run('chmod', <String>['+x', script.path]);
  if (chmodResult.exitCode != 0) {
    fail('chmod failed: ${chmodResult.stderr}');
  }
  return script;
}

String _successScript() => r'''#!/usr/bin/env bash
output=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--output-last-message" ]; then
    shift
    output="$1"
  fi
  shift
done
if [ -n "$output" ]; then
  cat > "$output" <<'JSON'
{"suggestions":[{"id":"s1"}],"notes":"ok"}
JSON
  exit 0
fi
exit 1
''';

String _legacyScript() => r'''#!/usr/bin/env bash
output=""
use_fallback=0
for arg in "$@"; do
  if [ "$arg" = "-a" ]; then
    use_fallback=1
  fi
done
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--output-last-message" ]; then
    shift
    output="$1"
  fi
  shift
done
if [ "$use_fallback" -eq 0 ]; then
  echo "unexpected argument --full-auto" >&2
  exit 1
fi
cat > "$output" <<'JSON'
{"ok":true}
JSON
exit 0
''';

String _authFailureScript() => r'''#!/usr/bin/env bash
echo "ERROR: exceeded retry limit, last status: 401 Unauthorized" >&2
exit 1
''';

String _transientScript() => r'''#!/usr/bin/env bash
output=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--output-last-message" ]; then
    shift
    output="$1"
  fi
  shift
done
state_file="$(dirname "$output")/.transient_state"
if [ ! -f "$state_file" ]; then
  echo "attempt1" > "$state_file"
  echo "temporarily unavailable" >&2
  exit 75
fi
cat > "$output" <<'JSON'
{"ok":true}
JSON
exit 0
''';

String _timeoutScript() => r'''#!/usr/bin/env bash
sleep 2
exit 0
''';

String _largeOutputScript() => r'''#!/usr/bin/env bash
output=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--output-last-message" ]; then
    shift
    output="$1"
  fi
  shift
done
printf '{"payload":"' > "$output"
head -c 1024 /dev/zero | tr '\0' 'a' >> "$output"
printf '"}' >> "$output"
exit 0
''';

String _nestedSchemaMismatchScript() => r'''#!/usr/bin/env bash
output=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--output-last-message" ]; then
    shift
    output="$1"
  fi
  shift
done
cat > "$output" <<'JSON'
{"items":[{"id":123}]}
JSON
exit 0
''';

String _stableScript() => r'''#!/usr/bin/env bash
output=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--output-last-message" ]; then
    shift
    output="$1"
  fi
  shift
done
cat > "$output" <<'JSON'
{"status":"ok"}
JSON
exit 0
''';
