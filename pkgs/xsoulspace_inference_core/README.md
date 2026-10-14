# xsoulspace_inference_core

Please notice: this package is under development and not ready for production use.

Provider-agnostic inference contracts and validation utilities for text, STT,
and TTS task flows. The agentic harness now lives in `~/xs/ecsai_harness`;
see [ADR 0036](../../docs/decisions/0036_harness_product_relocated.md).

The [optional decision provider plan](docs/decision_provider_PLAN.md) describes
proposed additive contracts. They are not implemented capabilities. Concrete
providers remain optional and core does not depend on them or the harness.
The proposed choice interface can support repeated evaluations for reasoning
or semantic composition as well as routing; each role requires its own evidence.

## Included API

`GenerationOptions.reasoningEffort` and both `InferenceRequest` factories carry
an explicit effort independently of `thinking`. `ReasoningEffortInferenceClient`
advertises the adapter's supported wire values; consumers must refuse an absent
capability rather than silently substitute defaults. Model-specific eligibility
still belongs to the provider. Null retains existing behavior.

`ToolStreamingInferenceClient` is an optional stream with a caller-owned tool
registry. Text deltas are provisional; only a successful completed result can
publish typed calls for the caller's ordinary validation/execution path.

Native tool requests may carry optional `ToolCall.callId` and `namespace`.
Execution results retain `callId` to reference an admitted call; names alone do
not distinguish repeated requests. `InferenceResponse` serialization preserves
calls/results and correlation, while legacy constructors remain compatible.
The executing host owns admission and effects; a provider returning a call grants
no authority. Native Responses transport lives in `xsoulspace_inference_openai`.

- `InferenceTask`
- `InferenceRequest`
- `InferenceResponse`
- `InferenceAudioInput`
- `InferenceAudioArtifact`
- `InferenceSpeechSegment`
- `InferenceVoiceOptions`
- `InferenceClient`
- `InferenceClient.supportedTasks`
- `InferenceClient.refreshAvailability`
- `InferenceClient.resetAvailabilityCache`
- `ProvisionableInferenceClient` — optional capability for local providers:
  purpose-driven `ensureReady` with `ProvisionConstraints` (consent, network
  policy, size caps) and a `ProvisionProgress` stream for UI
- `ModelPurpose`, `ModelHandle`, `ProvisionConstraints`, `ProvisionProgress`,
  `ProvisionPhase`
- `InferenceReadinessProbe`
- `InferenceReadinessSnapshot`
- `InferenceReadinessIssue`
- `InferenceResult<T>`
- `InferenceError`
- `InferenceRealtimeAudioSink`
- `InferenceTranscriptController`
- `parseStrictJsonObject`
- `validateRequiredKeys`
- `validateInferenceRequest`
- `validateInferenceAudioInput`
- `validateSchemaDefinition`
- `validateJsonAgainstSchema`
- `normalizeTranscript`

## Local model provisioning

Providers whose models must be downloaded (Gemma, Whisper, Sherpa) implement
`ProvisionableInferenceClient`. Core stays provider-agnostic: it defines only
the purpose key, the constraint shape, and the progress contract.

```dart
final client = someLocalClient; // implements InferenceClient + ProvisionableInferenceClient
final ready = await client.ensureReady(
  const ModelPurpose('structured_tool_use'),
  constraints: const ProvisionConstraints(
    maxDownloadBytes: 3 << 30,
    requireUserConsent: true,
    userConsentGranted: true,
  ),
);
```

Defaults are conservative: consent is required and no download starts without
it. Cloud providers never implement this interface — provisioning is a local-
provider concern, not part of `InferenceClient`.

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
- Readiness probes stay provider-agnostic and report standardized blocking and
  non-blocking issues.
- Realtime controllers can consume any injected
  `InferenceRealtimeSession<InferenceTranscriptEvent>`.

## Tests

```bash
cd pkgs/xsoulspace_inference_core
dart analyze
dart test
```

## License

MIT

## Declarative tool-call syntax

`ToolCallSyntax` composes explicitly selected `ToolSyntaxEnvelope` nodes.
Use `qwenJson`, `legacyTags`, or a host-selected custom envelope; profiles
do not guess another checkpoint's syntax. `renderCall` composes the selected
envelope and `parse` produces typed calls plus original envelope spans.
Parsing is bounded by bytes, nesting depth and node count, and any malformed
or truncated envelope refuses the entire result. Fenced source examples
refuse as ambiguous. Supply the current registry with `requireRegistry: true`
when admitting calls; parsing never executes tools or grants authority.
Argument-schema validation, consent and execution remain downstream.

The Qwen profile is `qwen-delimited-json-v2`: unmatched dedicated closing
markers produce an atomic named refusal instead of silently becoming text.
Custom envelopes can declare `rejectOrphanClose: true` when their closing
marker is reserved syntax. Leave it false for ordinary punctuation, as in
legacy `>` tags. Opaque thoughts and JSON argument strings remain excluded
from delimiter scanning; bare JSON does not become an executable call.

`validateJsonAgainstSchema` supports the generated inline JSON-Schema subset:
types, enum, required-key presence, `anyOf`, property schemas, additional-property
policy and array item/length bounds. It is not a complete draft validator or a
reference resolver. Core-to-JSON conversion preserves optional omission and adds
nullable alternatives; primitive guides and `representNilExplicitly` semantics
are not fully represented. Consumers retain authority over other constraints.

A host can compose a checkpoint-specific envelope without changing execution:

```dart
const syntax = ToolCallSyntax(
  id: 'trained-action-json-v1',
  envelopes: [
    ToolSyntaxEnvelope.opaque(open: '[thought]', close: '[/thought]'),
    ToolSyntaxEnvelope.jsonCall(
      open: '[action]',
      close: '[/action]',
      nameKey: 'function',
      argumentsKey: 'parameters',
    ),
  ],
);
final text = syntax.renderCall(const ToolCall(
  name: ToolName('readFile'),
  arguments: {'path': 'lib/main.dart'},
));
final parsed = syntax.parse(
  text,
  registry: actorToolRegistry, // The host's current granted registry.
  requireRegistry: true,
);
```

`parsed.calls` contains existing typed calls; `parsed.nodes` preserves original
regions and offsets. Opaque thought contents are not recursively interpreted,
and an unfinished thought refuses the whole result. A provider that prefills
thinking must declare it to its adapter; raw text does not grant a thinking
channel. A syntax profile selects decoding, not tool authority or execution.

For JSON serialized inside a declared tool string field, use
`decodeJsonWithUniqueKeys` to retain the same duplicate-key refusal as envelope
parsing. It validates JSON and rejects duplicate decoded keys in any object,
including equivalent escapes. Source code held in string values remains opaque.
The caller owns size/depth limits, payload schema and authority; decoding grants
no tool execution or consent.

### Original and presentation output

`InferenceResponse.rawOutput` preserves provider source. Optional
`presentationText` carries discussion decoded by the selected provider syntax
profile: null retains legacy raw presentation; empty explicitly means no visible
discussion. Structured `toolCalls` remain structured. Consumers must not reparse
presentation into executable calls, erase originals, or treat streamed provisional
text as a durable effect. Final settlement can correct provisional text.
