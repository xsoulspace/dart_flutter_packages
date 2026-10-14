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
