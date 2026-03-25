# xsoulspace_inference_cursor_agent

Please notice: this package is under development and not ready for production use.

Cursor Agent CLI backed implementation of
`xsoulspace_inference_core` (`InferenceClient`).

## What this package uses

- Uses official Cursor Agent CLI non-interactive API:
  `cursor-agent --print --output-format json`.
- Does not provide a special web-search mode.

## Authentication

This package supports Cursor Agent authentication through:

1. `CURSOR_API_KEY` for non-interactive runs.
2. `cursor-agent login` for persisted local credentials.

## Usage

```dart
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_cursor_agent/xsoulspace_inference_cursor_agent.dart';

Future<void> runInference() async {
  final client = CursorAgentInferenceClient(
    binaryName: 'cursor-agent',
    executionTimeout: const Duration(minutes: 2),
    maxAttempts: 3,
    maxTransientRetries: 1,
    maxTimeoutRetries: 1,
  );

  final result = await client.infer(
    InferenceRequest(
      prompt: 'Return ONLY JSON {"status":"ok"}',
      outputSchema: const <String, dynamic>{
        'type': 'object',
        'required': <String>['status'],
        'properties': <String, dynamic>{
          'status': <String, dynamic>{'type': 'string'},
        },
      },
      workingDirectory: '.',
    ),
  );

  if (!result.success) {
    throw StateError('${result.error?.code}: ${result.error?.message}');
  }
}
```

## Task support

- Supported: `InferenceTask.structuredText`
- Unsupported: `InferenceTask.speechToText`, `InferenceTask.textToSpeech`
  return `task_unsupported`.

## Production reliability behavior

- Request prevalidation before executing Cursor Agent.
- Timeout retries.
- Transient-process-error retries.
- Hard timeout and process kill on long-running executions.
- Output size cap via `maxOutputBytes`.
- Strict Cursor JSON-envelope validation.
- Recursive JSON schema conformance check before success.
- Structured metadata for each attempt (`attempt_count`, timings).

## Failure codes

- `engine_unavailable`: `cursor-agent` binary not found.
- `working_directory_not_found`: request directory does not exist.
- `cursor_exec_timeout`: process exceeded timeout.
- `cursor_auth_failed`: authentication failed.
- `cursor_exec_failed`: process failed for non-auth reasons.
- `cursor_output_too_large`: stdout exceeded configured bytes limit.
- `cursor_output_empty`: no output returned.
- `cursor_output_invalid`: malformed or error Cursor envelope.
- `json_parse_failed` / `json_not_object`: malformed structured output.
- `schema_type_mismatch` and related schema errors from core validator.

## Testing

### Unit and reliability tests

```bash
cd pkgs/xsoulspace_inference_cursor_agent
dart analyze
dart test
```

### Real Cursor integration tests

```bash
cd pkgs/xsoulspace_inference_cursor_agent
CURSOR_INFERENCE_INTEGRATION=1 \
CURSOR_API_KEY=YOUR_KEY \
CURSOR_BINARY=cursor-agent \
dart test test/integration/cursor_agent_real_binary_test.dart
```

If `CURSOR_API_KEY` is not set, existing `cursor-agent login` credentials may
also work.

## License

MIT
