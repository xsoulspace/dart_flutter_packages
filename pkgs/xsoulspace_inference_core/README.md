# xsoulspace_inference_core

Provider-agnostic inference contracts and validation utilities.

## Included API

- `InferenceRequest`
- `InferenceResponse`
- `InferenceClient`
- `InferenceResult<T>`
- `InferenceError`
- `parseStrictJsonObject`
- `validateRequiredKeys`
- `validateInferenceRequest`
- `validateSchemaDefinition`
- `validateJsonAgainstSchema`

## Why this package exists

Inference backends are unreliable by nature (timeouts, malformed JSON, partial
responses). This package centralizes validation and failure shapes so all
providers expose consistent behavior.

## Usage

```dart
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

InferenceResult<void> validateRequest(final InferenceRequest request) =>
    validateInferenceRequest(request);

InferenceResult<void> validateOutput({
  required final String rawOutput,
  required final Map<String, dynamic> schema,
}) {
  final parsed = parseStrictJsonObject(rawOutput);
  if (!parsed.success || parsed.data == null) {
    return InferenceResult<void>.fail(
      code: parsed.error?.code ?? 'json_parse_failed',
      message: parsed.error?.message ?? 'Invalid JSON output',
      details: parsed.error?.details,
    );
  }

  return validateJsonAgainstSchema(value: parsed.data, schema: schema);
}
```

## Reliability contract

- Empty prompt / schema / working directory is rejected before execution.
- Schema definitions are validated before output validation starts.
- Output validation supports nested `object` and `array` nodes.
- Type mismatches include structured path metadata (for example `$.items[0].id`).

## Tests

```bash
cd pkgs/xsoulspace_inference_core
dart analyze
dart test
```

## License

MIT
