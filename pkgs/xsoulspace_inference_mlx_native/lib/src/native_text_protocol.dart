import 'dart:convert';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// Native chat templates consume the same function signatures as wire APIs.
/// The core kind-tagged schema is a host contract, not model-facing JSON Schema.
List<Map<String, Object?>> nativeTextFunctionTools(ToolRegistry registry) => [
  for (final tool in registry.tools.values)
    {
      'type': 'function',
      'function': {
        'name': tool.name.value,
        'description': tool.description,
        'parameters': bundleToJsonSchema(tool.argsSchema),
      },
    },
];

/// Reconstruct only the request's already-projected cut. Explicit messages
/// remain authoritative, so no second transcript or hidden world read exists.
List<ChatMessage> nativeTextMessages(InferenceRequest request) =>
    request.messages.isNotEmpty
    ? request.messages
    : SituationMessagesCodec.render(
        prompt: request.prompt,
        systemPrompt: request.systemPrompt,
        fragments: request.contextFragments,
      ).map(ChatMessage.fromJson).toList();

/// The request's output schema as standard JSON Schema.
///
/// The core request carries the kind-tagged schema bundle; the native
/// prompt needs standard JSON Schema, so the shared conversion is used
/// (never a hand-rolled serializer). A schema that is already plain JSON
/// Schema is passed through unchanged.
Map<String, dynamic> nativeTextJsonSchema(Map<String, dynamic> outputSchema) {
  if (outputSchema.isEmpty) return const <String, dynamic>{};
  final root = outputSchema['root'];
  if (root is Map && root['kind'] is String) {
    return bundleToJsonSchema(SchemaBundle.fromJson(outputSchema));
  }
  return outputSchema;
}

/// The structured-output contract rendered into the native prompt.
///
/// The native engines have NO server-side and NO token-level grammar
/// enforcement: the schema is spelled out in the prompt (the same contract
/// as the wire providers' prompt-rendered schema) and the answer is parsed
/// back afterwards. The text is the core prompt builder's own wording, so
/// the two paths say the same thing.
String nativeTextStructuredOutputInstruction(Map<String, dynamic> jsonSchema) {
  if (jsonSchema.isEmpty) return '';
  final builder = PromptBuilder('');
  builder.writeStructuredOutputPrompt(jsonSchema);
  return builder.toString().trim();
}

/// The messages with the structured-output contract attached.
///
/// The contract rides on the leading system message when there is one, and
/// opens the conversation otherwise — the chat templates lift a leading
/// system turn, so the schema is always in front of the answer.
List<ChatMessage> nativeTextStructuredMessages(
  List<ChatMessage> messages,
  Map<String, dynamic> jsonSchema,
) {
  if (jsonSchema.isEmpty) return messages;
  final instruction = nativeTextStructuredOutputInstruction(jsonSchema);
  if (messages.isNotEmpty && messages.first.role == ChatRole.system) {
    return <ChatMessage>[
      ChatMessage.system('${messages.first.content}\n\n$instruction'),
      ...messages.skip(1),
    ];
  }
  return <ChatMessage>[ChatMessage.system(instruction), ...messages];
}

/// Decodes the model's answer as the requested structured output.
///
/// Tolerant by contract: a markdown fence and surrounding prose are
/// tolerated — the outermost balanced JSON object wins. A refusal is
/// honest: a missing or non-object payload fails with a named code and
/// the raw text as the evidence, never a success with an empty map.
InferenceResult<Map<String, dynamic>> nativeTextParseStructuredOutput({
  required String raw,
  String? preferred,
}) {
  var candidate = preferred == null ? null : _outermostJson(preferred);
  candidate ??= _outermostJson(raw);
  if (candidate == null) {
    return InferenceResult<Map<String, dynamic>>.fail(
      code: 'structured_output_unparseable',
      message: 'The native answer carries no JSON object',
      details: <String, dynamic>{'raw_output': raw},
    );
  }
  try {
    final decoded = jsonDecode(candidate);
    if (decoded is! Map<String, dynamic>) {
      return InferenceResult<Map<String, dynamic>>.fail(
        code: 'structured_output_not_object',
        message: 'The native answer is JSON, but not a JSON object',
        details: <String, dynamic>{
          'raw_output': raw,
          'json_type': decoded.runtimeType.toString(),
        },
      );
    }
    return InferenceResult<Map<String, dynamic>>.ok(decoded);
    // ignore: avoid_catches_without_on_clauses
  } catch (error) {
    return InferenceResult<Map<String, dynamic>>.fail(
      code: 'structured_output_unparseable',
      message: 'The native answer is not valid JSON',
      details: <String, dynamic>{'raw_output': raw, 'error': error.toString()},
    );
  }
}

/// The first decodable outermost JSON value in [raw].
///
/// Prose, markdown fences and a stray brace before the payload are
/// tolerated: every candidate start is tried and the first one that
/// decodes wins. A JSON object is preferred over a JSON array — the
/// structured-output contract is an object.
String? _outermostJson(String raw) {
  String? anyValue;
  for (var start = 0; start < raw.length; start++) {
    final opener = raw[start];
    if (opener != '{' && opener != '[') continue;
    final end = _balancedEnd(raw, start);
    if (end == null) continue;
    final candidate = raw.substring(start, end + 1);
    Object? decoded;
    try {
      decoded = jsonDecode(candidate);
    } on FormatException {
      continue;
    }
    if (decoded is Map<String, dynamic>) return candidate;
    anyValue ??= candidate;
  }
  return anyValue;
}

/// The end offset of the JSON value opening at [start], or null when the
/// value never closes.
int? _balancedEnd(String raw, int start) {
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = start; i < raw.length; i++) {
    final character = raw[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (character == r'\') {
        escaped = true;
      } else if (character == '"') {
        inString = false;
      }
      continue;
    }
    if (character == '"') {
      inString = true;
      continue;
    }
    if (character == '{' || character == '[') {
      depth++;
      continue;
    }
    if (character == '}' || character == ']') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return null;
}

final class NativeTextToolOutput {
  const NativeTextToolOutput({
    this.calls = const [],
    this.sources = const [],
    this.presentationText = '',
  });
  final List<ToolCall> calls;
  final String presentationText;
  final List<Map<String, Object>> sources;
}

InferenceResult<NativeTextToolOutput> normalizeNativeTextCalls({
  required String text,
  required ToolCallSyntax? syntax,
  required ToolRegistry? registry,
  bool thinkingPrefilled = false,
}) {
  var answer = text;
  var presentationStart = 0;
  // The Qwen renderer, not raw substring guessing, declares an open thought
  // in its generation prompt. Mask it without shifting original source spans.
  if (thinkingPrefilled && !text.trimLeft().startsWith('<think>')) {
    final close = text.indexOf('</think>');
    if (close < 0) {
      return InferenceResult.fail(
        code: 'tool_thinking_truncated',
        message: 'The checkpoint did not close its declared thinking region',
      );
    }
    final end = close + '</think>'.length;
    answer = '${' ' * end}${text.substring(end)}';
    presentationStart = end;
  }
  if (syntax == null) {
    if (answer.contains('<|tool_call_start|>') ||
        answer.contains('<tool_call>')) {
      return InferenceResult.fail(
        code: 'tool_syntax_unsupported',
        message: 'This checkpoint has no qualified tool-call syntax profile',
      );
    }
    return InferenceResult.ok(
      NativeTextToolOutput(presentationText: text.substring(presentationStart)),
    );
  }
  final parsed = syntax.parse(
    answer,
    registry: registry,
    requireRegistry: true,
  );
  if (!parsed.success) {
    return InferenceResult.fail(
      code: parsed.errorCode!,
      message: 'Native output does not satisfy ${syntax.id}',
      details: {'syntax': syntax.id, 'offset': parsed.errorOffset},
    );
  }
  // The already validated profile owns these spans. Presentation never parses
  // again, and the exact original remains available separately as evidence.
  final presentation = StringBuffer();
  var cursor = presentationStart;
  for (final node in parsed.nodes) {
    if (node.end <= cursor) continue;
    if (node.start > cursor)
      presentation.write(text.substring(cursor, node.start));
    cursor = node.end;
  }
  presentation.write(text.substring(cursor));
  return InferenceResult.ok(
    NativeTextToolOutput(
      calls: parsed.calls,
      presentationText: presentation.toString(),
      sources: [
        for (final node in parsed.nodes)
          if (node.call != null)
            {
              'syntax': syntax.id,
              'start': node.start,
              'end': node.end,
              'raw': node.raw,
            },
      ],
    ),
  );
}

/// A parser refusal remains a failure. Counters come from the native SDK's
/// completion token arrays, never from estimating raw text or error messages.
InferenceResult<InferenceResponse> nativeTextNormalizationRefusal({
  required InferenceResult<NativeTextToolOutput> normalized,
  required String rawOutput,
  required int promptTokens,
  required int completionTokens,
}) {
  if (normalized.success || normalized.error == null) {
    throw ArgumentError('A normalization refusal is required');
  }
  final error = normalized.error!;
  return InferenceResult.fail(
    code: error.code,
    message: error.message,
    details: {
      'protocol_error': error.details,
      'raw_output': rawOutput,
      'usage': {
        'prompt_tokens': promptTokens,
        'completion_tokens': completionTokens,
      },
    },
  );
}
