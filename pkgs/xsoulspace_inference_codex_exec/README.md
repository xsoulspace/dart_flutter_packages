# xsoulspace_inference_codex_exec

Codex CLI backed implementation of
`xsoulspace_inference_core` (`InferenceClient`).

## What this package uses

- Uses official Codex CLI non-interactive API: `codex exec`.
- Does not use the TypeScript Codex SDK (`@openai/codex-sdk`).

## Official auth only

This package supports official Codex authentication paths only:

1. `CODEX_API_KEY` for non-interactive `codex exec` runs (recommended for CI).
2. `codex login --with-api-key` for persisted local credentials.

Notes:

- `codex login --api-key ...` is deprecated/unsupported in current CLI.
- Integration tests in this package require `CODEX_API_KEY`.

## Usage

```dart
import 'package:xsoulspace_inference_codex_exec/xsoulspace_inference_codex_exec.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

Future<void> runInference() async {
  final client = CodexExecInferenceClient(
    binaryName: 'codex',
    executionTimeout: const Duration(minutes: 2),
    maxAttempts: 3,
    maxTransientRetries: 1,
    maxTimeoutRetries: 1,
  );

  final result = await client.infer(
    InferenceRequest(
      prompt: 'Return JSON {"status":"ok"}',
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

## Production reliability behavior

- Request prevalidation before executing Codex (`prompt`, `schema`, `workingDirectory`).
- Retry strategy:
  - legacy CLI flag fallback (`--full-auto` to `-a on-failure`) when needed.
  - timeout retries.
  - transient-process-error retries.
- Hard timeout and process kill on long-running executions.
- Output size cap via `maxOutputBytes`.
- Recursive JSON schema conformance check before success.
- Structured metadata for each attempt (`attempt_count`, timings, auto args).

## Failure codes

- `engine_unavailable`: codex binary not found.
- `working_directory_not_found`: request directory does not exist.
- `codex_exec_timeout`: process exceeded timeout.
- `codex_auth_failed`: official auth failed (for example `401 Unauthorized`).
- `codex_exec_failed`: process failed for non-auth reasons.
- `codex_output_too_large`: output exceeded configured bytes limit.
- `codex_output_empty`: no output returned.
- `json_parse_failed` / `json_not_object`: malformed structured output.
- `schema_type_mismatch` and related schema errors from core validator.

## Testing

### Unit and reliability tests

```bash
cd pkgs/xsoulspace_inference_codex_exec
dart analyze
dart test
```

### Real Codex integration tests (official auth required)

```bash
cd pkgs/xsoulspace_inference_codex_exec
CODEX_INFERENCE_INTEGRATION=1 \
CODEX_API_KEY=YOUR_KEY \
CODEX_BINARY=codex \
dart test test/integration/codex_exec_real_binary_test.dart
```

If `CODEX_API_KEY` is not set, integration tests are intentionally skipped.

## License

MIT
