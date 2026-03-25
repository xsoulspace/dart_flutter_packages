import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_cursor_agent/xsoulspace_inference_cursor_agent.dart';

void main() {
  final shellSkipReason = Platform.isWindows
      ? 'shell script tests require a Unix-like environment'
      : null;

  group('CursorAgentInferenceClient', () {
    test('supports only structuredText tasks', () {
      final client = CursorAgentInferenceClient(
        binaryName: '/tmp/cursor-agent',
      );
      expect(client.supportedTasks, const <InferenceTask>{
        InferenceTask.structuredText,
      });
    });

    test('infer returns task_unsupported for STT requests', () async {
      final client = CursorAgentInferenceClient(
        binaryName: '/tmp/cursor-agent',
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
      expect(result.error?.code, errorCodeTaskUnsupported);
    });

    test(
      'infer parses structured output from cursor-agent JSON envelope',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'xsoulspace_cursor_test_',
        );
        addTearDown(() => temp.delete(recursive: true));

        final script = await _createExecutableScript(temp, _successScript());
        final client = CursorAgentInferenceClient(binaryName: script.path);

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
        expect(result.data!.meta['cursor_session_id'], 'session-ok');
        expect(
          result.data!.rawOutput,
          '{"suggestions":[{"id":"s1"}],"notes":"ok"}',
        );
      },
      skip: shellSkipReason,
    );

    test('infer retries transient process errors', () async {
      final temp = await Directory.systemTemp.createTemp(
        'xsoulspace_cursor_test_',
      );
      addTearDown(() => temp.delete(recursive: true));

      final script = await _createExecutableScript(temp, _transientScript());
      final client = CursorAgentInferenceClient(
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
          'xsoulspace_cursor_test_',
        );
        addTearDown(() => temp.delete(recursive: true));

        final script = await _createExecutableScript(temp, _timeoutScript());
        final client = CursorAgentInferenceClient(
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
        expect(result.error?.code, 'cursor_exec_timeout');
      },
      skip: shellSkipReason,
    );

    test('infer fails when binary is unavailable', () async {
      final client = CursorAgentInferenceClient(
        binaryName: '/tmp/not-found-cursor-agent',
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
      'infer maps authentication failures to cursor_auth_failed',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'xsoulspace_cursor_test_',
        );
        addTearDown(() => temp.delete(recursive: true));

        final script = await _createExecutableScript(
          temp,
          _authFailureScript(),
        );
        final client = CursorAgentInferenceClient(
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
        expect(result.error?.code, 'cursor_auth_failed');
        final details = result.error?.details as Map<String, dynamic>?;
        expect(details?['auth_failure'], isTrue);
        final remediation = details?['remediation'] as List<dynamic>?;
        expect(remediation?.join(' '), contains('CURSOR_API_KEY'));
      },
      skip: shellSkipReason,
    );

    test('infer fails when working directory is missing', () async {
      final client = CursorAgentInferenceClient(binaryName: '/bin/sh');
      final result = await client.infer(
        _request(
          '/tmp/xsoulspace_missing_dir_for_cursor_inference',
          outputSchema: const <String, dynamic>{'type': 'object'},
        ),
      );

      expect(result.success, isFalse);
      expect(result.error?.code, 'working_directory_not_found');
    });

    test(
      'infer fails when cursor-agent output exceeds maxOutputBytes',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'xsoulspace_cursor_test_',
        );
        addTearDown(() => temp.delete(recursive: true));

        final script = await _createExecutableScript(
          temp,
          _largeOutputScript(),
        );
        final client = CursorAgentInferenceClient(
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
        expect(result.error?.code, 'cursor_output_too_large');
      },
      skip: shellSkipReason,
    );

    test('infer fails when cursor-agent envelope is invalid', () async {
      final temp = await Directory.systemTemp.createTemp(
        'xsoulspace_cursor_test_',
      );
      addTearDown(() => temp.delete(recursive: true));

      final script = await _createExecutableScript(
        temp,
        _invalidEnvelopeScript(),
      );
      final client = CursorAgentInferenceClient(binaryName: script.path);
      final result = await client.infer(
        _request(
          temp.path,
          outputSchema: const <String, dynamic>{'type': 'object'},
        ),
      );

      expect(result.success, isFalse);
      expect(result.error?.code, 'cursor_output_invalid');
    }, skip: shellSkipReason);

    test('infer validates nested schema and reports mismatch', () async {
      final temp = await Directory.systemTemp.createTemp(
        'xsoulspace_cursor_test_',
      );
      addTearDown(() => temp.delete(recursive: true));

      final script = await _createExecutableScript(
        temp,
        _nestedSchemaMismatchScript(),
      );
      final client = CursorAgentInferenceClient(binaryName: script.path);
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

    test('infer fails when result text is not JSON', () async {
      final temp = await Directory.systemTemp.createTemp(
        'xsoulspace_cursor_test_',
      );
      addTearDown(() => temp.delete(recursive: true));

      final script = await _createExecutableScript(temp, _plainTextScript());
      final client = CursorAgentInferenceClient(binaryName: script.path);
      final result = await client.infer(
        _request(
          temp.path,
          outputSchema: const <String, dynamic>{'type': 'object'},
        ),
      );

      expect(result.success, isFalse);
      expect(result.error?.code, anyOf('json_parse_failed', 'json_not_object'));
    }, skip: shellSkipReason);

    test('infer accepts JSON wrapped in markdown fences', () async {
      final temp = await Directory.systemTemp.createTemp(
        'xsoulspace_cursor_test_',
      );
      addTearDown(() => temp.delete(recursive: true));

      final script = await _createExecutableScript(temp, _fencedJsonScript());
      final client = CursorAgentInferenceClient(binaryName: script.path);
      final result = await client.infer(
        _request(
          temp.path,
          outputSchema: const <String, dynamic>{
            'type': 'object',
            'required': <String>['status'],
            'properties': <String, dynamic>{
              'status': <String, dynamic>{'type': 'string'},
            },
          },
        ),
      );

      expect(result.success, isTrue);
      expect(result.data!.output['status'], 'ok');
      expect(result.data!.rawOutput, '{"status":"ok"}');
    }, skip: shellSkipReason);

    test('infer extracts JSON from mixed prose output', () async {
      final temp = await Directory.systemTemp.createTemp(
        'xsoulspace_cursor_test_',
      );
      addTearDown(() => temp.delete(recursive: true));

      final script = await _createExecutableScript(
        temp,
        _mixedTextJsonScript(),
      );
      final client = CursorAgentInferenceClient(binaryName: script.path);
      final result = await client.infer(
        _request(
          temp.path,
          outputSchema: const <String, dynamic>{
            'type': 'object',
            'required': <String>['summary', 'changedFiles'],
            'properties': <String, dynamic>{
              'summary': <String, dynamic>{'type': 'string'},
              'changedFiles': <String, dynamic>{'type': 'array'},
            },
          },
        ),
      );

      expect(result.success, isTrue, reason: '${result.error?.toJson()}');
      expect(result.data!.output['summary'], 'Applied the requested edit.');
      expect(result.data!.rawOutput, contains('changedFiles'));
    }, skip: shellSkipReason);

    test('infer normalizes loose types against schema', () async {
      final temp = await Directory.systemTemp.createTemp(
        'xsoulspace_cursor_test_',
      );
      addTearDown(() => temp.delete(recursive: true));

      final script = await _createExecutableScript(
        temp,
        _schemaLooseTypesScript(),
      );
      final client = CursorAgentInferenceClient(binaryName: script.path);
      final result = await client.infer(
        _request(
          temp.path,
          outputSchema: const <String, dynamic>{
            'type': 'object',
            'required': <String>[
              'summary',
              'changedFiles',
              'warnings',
              'validationSteps',
            ],
            'properties': <String, dynamic>{
              'summary': <String, dynamic>{'type': 'string'},
              'changedFiles': <String, dynamic>{
                'type': 'array',
                'items': <String, dynamic>{'type': 'string'},
              },
              'warnings': <String, dynamic>{
                'type': 'array',
                'items': <String, dynamic>{'type': 'string'},
              },
              'validationSteps': <String, dynamic>{
                'type': 'array',
                'items': <String, dynamic>{'type': 'string'},
              },
            },
          },
        ),
      );

      expect(result.success, isTrue, reason: '${result.error?.toJson()}');
      expect(result.data!.output['summary'], 'Prompt-only update applied.');
      expect(result.data!.output['changedFiles'], <String>['lib/main.dart']);
      expect(result.data!.output['warnings'], <String>[
        'Double-check spacing.',
      ]);
      expect(result.data!.output['validationSteps'], <String>[
        'Hot reload and verify',
      ]);
    }, skip: shellSkipReason);

    test(
      'infer remains stable across repeated sequential requests',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'xsoulspace_cursor_test_',
        );
        addTearDown(() => temp.delete(recursive: true));

        final script = await _createExecutableScript(temp, _stableScript());
        final client = CursorAgentInferenceClient(binaryName: script.path);

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

    test(
      'infer passes model from metadata inferenceModel to CLI',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'xsoulspace_cursor_test_',
        );
        addTearDown(() => temp.delete(recursive: true));

        final argsPath = '${temp.path}/args.txt';
        final script = await _createExecutableScript(
          temp,
          _argumentCaptureScript(argsPath),
        );
        final client = CursorAgentInferenceClient(binaryName: script.path);

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
            metadata: const <String, dynamic>{
              'inferenceModel': 'claude-3-5-sonnet',
            },
          ),
        );

        expect(result.success, isTrue);
        final args = File(argsPath).readAsLinesSync();
        expect(
          args,
          containsAllInOrder(<String>['--model', 'claude-3-5-sonnet']),
        );
      },
      skip: shellSkipReason,
    );

    test(
      'infer passes model from metadata cursorAgentModel to CLI',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'xsoulspace_cursor_test_',
        );
        addTearDown(() => temp.delete(recursive: true));

        final argsPath = '${temp.path}/args.txt';
        final script = await _createExecutableScript(
          temp,
          _argumentCaptureScript(argsPath),
        );
        final client = CursorAgentInferenceClient(binaryName: script.path);

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
            metadata: const <String, dynamic>{'cursorAgentModel': 'gpt-4o'},
          ),
        );

        expect(result.success, isTrue);
        final args = File(argsPath).readAsLinesSync();
        expect(args, containsAllInOrder(<String>['--model', 'gpt-4o']));
      },
      skip: shellSkipReason,
    );

    test('infer uses defaultModel when metadata has no model', () async {
      final temp = await Directory.systemTemp.createTemp(
        'xsoulspace_cursor_test_',
      );
      addTearDown(() => temp.delete(recursive: true));

      final argsPath = '${temp.path}/args.txt';
      final script = await _createExecutableScript(
        temp,
        _argumentCaptureScript(argsPath),
      );
      final client = CursorAgentInferenceClient(
        binaryName: script.path,
        defaultModel: 'claude-default',
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
      final args = File(argsPath).readAsLinesSync();
      expect(args, containsAllInOrder(<String>['--model', 'claude-default']));
    }, skip: shellSkipReason);

    test('infer remains stable across parallel requests', () async {
      final temp = await Directory.systemTemp.createTemp(
        'xsoulspace_cursor_test_',
      );
      addTearDown(() => temp.delete(recursive: true));

      final script = await _createExecutableScript(temp, _stableScript());
      final client = CursorAgentInferenceClient(binaryName: script.path);

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
  final Map<String, dynamic> metadata = const <String, dynamic>{},
}) => InferenceRequest(
  prompt: prompt,
  outputSchema: outputSchema,
  workingDirectory: workingDirectory,
  metadata: metadata,
);

Future<File> _createExecutableScript(
  final Directory directory,
  final String content,
) async {
  final script = File('${directory.path}/cursor-agent');
  await script.writeAsString(content);
  final chmodResult = await Process.run('chmod', <String>['+x', script.path]);
  if (chmodResult.exitCode != 0) {
    fail('chmod failed: ${chmodResult.stderr}');
  }
  return script;
}

String _successScript() => r'''#!/usr/bin/env bash
cat <<'JSON'
{"type":"result","subtype":"success","is_error":false,"result":"{\"suggestions\":[{\"id\":\"s1\"}],\"notes\":\"ok\"}","session_id":"session-ok"}
JSON
''';

String _authFailureScript() => r'''#!/usr/bin/env bash
echo "ERROR: 401 Unauthorized. Login required." >&2
exit 1
''';

String _transientScript() => r'''#!/usr/bin/env bash
state_file="$PWD/.transient_state"
if [ ! -f "$state_file" ]; then
  echo "attempt1" > "$state_file"
  echo "temporarily unavailable" >&2
  exit 75
fi
cat <<'JSON'
{"type":"result","subtype":"success","is_error":false,"result":"{\"ok\":true}","session_id":"session-retry"}
JSON
exit 0
''';

String _timeoutScript() => r'''#!/usr/bin/env bash
sleep 2
exit 0
''';

String _largeOutputScript() => r'''#!/usr/bin/env bash
printf '{"type":"result","subtype":"success","is_error":false,"result":"{\"payload\":\"'
head -c 1024 /dev/zero | tr '\0' 'a'
printf '\"}"}'
''';

String _invalidEnvelopeScript() => r'''#!/usr/bin/env bash
echo '{"type":"result","is_error":false}'
''';

String _nestedSchemaMismatchScript() => r'''#!/usr/bin/env bash
cat <<'JSON'
{"type":"result","subtype":"success","is_error":false,"result":"{\"items\":[{\"id\":123}]}"}
JSON
''';

String _plainTextScript() => r'''#!/usr/bin/env bash
cat <<'JSON'
{"type":"result","subtype":"success","is_error":false,"result":"hello world"}
JSON
''';

String _fencedJsonScript() => r'''#!/usr/bin/env bash
cat <<'JSON'
{"type":"result","subtype":"success","is_error":false,"result":"```json\n{\"status\":\"ok\"}\n```"}
JSON
''';

String _mixedTextJsonScript() => r'''#!/usr/bin/env bash
cat <<'JSON'
{"type":"result","subtype":"success","is_error":false,"result":"Inspecting the target file to apply the minimal edit.\nApplied the source change.\n{\"summary\":\"Applied the requested edit.\",\"changedFiles\":[\"lib/main.dart\"]}"}
JSON
''';

String _schemaLooseTypesScript() => r'''#!/usr/bin/env bash
cat <<'JSON'
{"type":"result","subtype":"success","is_error":false,"result":"{\"summary\":[\"Prompt-only update applied.\"],\"changedFiles\":\"lib/main.dart\",\"warnings\":{\"text\":\"Double-check spacing.\"},\"validationSteps\":\"Hot reload and verify\"}"}
JSON
''';

String _argumentCaptureScript(final String argsPath) =>
    '''#!/usr/bin/env bash
printf '%s\\n' "\$@" > "$argsPath"
cat <<'JSON'
{"type":"result","subtype":"success","is_error":false,"result":"{\\"ok\\":true}","session_id":"session-args"}
JSON
''';

String _stableScript() => r'''#!/usr/bin/env bash
cat <<'JSON'
{"type":"result","subtype":"success","is_error":false,"result":"{\"status\":\"ok\"}","session_id":"session-stable"}
JSON
''';
