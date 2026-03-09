# xsoulspace_inference_core

Provider-agnostic inference contracts and validation utilities for text, STT,
and TTS task flows.

## Included API

- `InferenceTask`
- `InferenceRequest`
- `InferenceResponse`
- `InferenceAudioInput`
- `InferenceAudioArtifact`
- `InferenceSpeechSegment`
- `InferenceVoiceOptions`
- `InferenceClient`
- `InferenceClient.supportedTasks`
- `InferenceResult<T>`
- `InferenceError`
- `parseStrictJsonObject`
- `validateRequiredKeys`
- `validateInferenceRequest`
- `validateInferenceAudioInput`
- `validateSchemaDefinition`
- `validateJsonAgainstSchema`
- `normalizeTranscript`

## Why this package exists

Inference backends are unreliable by nature (timeouts, malformed JSON, partial
responses). This package centralizes task contracts, validation, and failure
shapes so all providers expose consistent behavior.

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

## Voice pipeline example (STT -> grammar analysis -> TTS)

```dart
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

Future<void> runVoicePipeline({
  required InferenceClient sttClient,
  required InferenceClient textClient,
  required InferenceClient ttsClient,
}) async {
  final stt = await sttClient.infer(
    InferenceRequest.speechToText(
      audioInput: const InferenceAudioInput.filePath(
        filePath: '/tmp/input.wav',
        mimeType: 'audio/wav',
      ),
      workingDirectory: '/tmp',
    ),
  );
  if (!stt.success || stt.data == null) {
    throw StateError('STT failed: ${stt.error?.code}');
  }

  final normalizedTranscript = stt.data!.normalizedTranscript ??
      normalizeTranscript(stt.data!.transcript ?? '');

  final grammar = await textClient.infer(
    InferenceRequest(
      prompt: 'Analyze grammar and suggest a short corrected reply: '
          '$normalizedTranscript',
      outputSchema: const <String, dynamic>{
        'type': 'object',
        'required': <String>['reply'],
        'properties': <String, dynamic>{
          'reply': <String, dynamic>{'type': 'string'},
        },
      },
      workingDirectory: '/tmp',
    ),
  );
  if (!grammar.success || grammar.data == null) {
    throw StateError('Text analysis failed: ${grammar.error?.code}');
  }

  final reply = grammar.data!.output['reply'] as String;
  final tts = await ttsClient.infer(
    InferenceRequest.textToSpeech(
      text: reply,
      workingDirectory: '/tmp',
      metadata: const <String, dynamic>{
        'output_file_path': '/tmp/reply.wav',
      },
    ),
  );
  if (!tts.success) {
    throw StateError('TTS failed: ${tts.error?.code}');
  }
}
```

## Reliability contract

- Structured text validation preserves current prompt/schema checks.
- STT validation enforces audio input presence and valid source form.
- TTS validation enforces non-empty text.
- Schema definitions are validated before output validation starts.
- JSON-schema validation is applied only for `InferenceTask.structuredText`.
- Type mismatches include structured path metadata (for example `$.items[0].id`).
- Transcript normalization strips punctuation and collapses whitespace while
  preserving word order.

## Tests

```bash
cd pkgs/xsoulspace_inference_core
dart analyze
dart test
```

## License

MIT
