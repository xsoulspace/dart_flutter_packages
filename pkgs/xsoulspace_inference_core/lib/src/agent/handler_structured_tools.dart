// ignore_for_file: lines_longer_than_80_chars

/// Guided-generation tool decisions — the backend-agnostic tool protocol.
///
/// Instead of relying on per-backend native tool invocation (Swift tool
/// suspension, OpenAI function-calling, tag parsing), every decision is forced
/// through a structured schema:
///
/// ```
/// Decision = AnyOf{
///   act:    { tool: Enum[...], args: <tool's argsSchema> }
///   answer: { text: string }
/// }
/// ```
///
/// With guided decoding the model *cannot* emit malformed tool syntax — the
/// failure mode collapses from "parser bugs" to "wrong choice", which is a
/// model-quality problem you can measure. Works with any backend that
/// supports structured output (Apple Foundation via GenerationSchema, Gemma
/// via prompt-constrained JSON, hosted models via JSON mode).
///
/// The decoded `{tool, args}` is re-emitted as a standard [ToolCall] on the
/// response, so the world's canonical path
/// (`processResponsesSystem → toolExecutionSystem → beats`) is unchanged.
library;

import 'dart:convert';

import 'package:ecsly/ecsly.dart' show World;

import 'structured_output/structured_output.dart';
import 'events.dart';
import 'tools/tool_registry.dart';

/// Builds the guided-decision [SchemaBundle] for [registry].
///
/// The schema mirrors each registered tool's own args schema, so argument
/// generation is also guided, not free-form.
SchemaBundle decisionSchema(ToolRegistry registry) {
  final choices = <Schema>[];
  for (final tool in registry.tools.values) {
    final props = <SchemaProperty>[
      FM.prop(
        'tool',
        FM.enum_('ToolName_${tool.name.value}', [
          tool.name.value,
        ], description: tool.description),
      ),
    ];
    // Embed the tool's own args schema properties when it is an object.
    final args = tool.argsSchema.root;
    if (args is ObjectSchema) {
      props.addAll(args.properties);
    } else if (!tool.argsSchema.isEmpty) {
      props.add(FM.prop('args_json', FM.string()));
    }
    choices.add(FM.object('Act_${tool.name.value}', properties: () => props));
  }
  choices.add(
    FM.object('Answer', properties: () => [FM.prop('text', FM.string())]),
  );
  return SchemaBundle(root: FM.anyOf('Decision', choices));
}

/// Decode a guided-decision structured output into either a [ToolCall] or a
/// final answer string.
({ToolCall? call, String? answer}) decodeDecision(
  Map<String, dynamic> output,
  ToolRegistry registry,
) {
  // Flat decision: some backends (e.g. AFM guided generation decoded by the
  // native bridge) deliver {tool, ...args} directly at the top level.
  if (output['tool'] is String) {
    final tool = registry.tools[ToolName(output['tool'] as String)];
    if (tool != null) {
      final args = <String, dynamic>{}
        ..addAll(output)
        ..remove('tool');
      return (call: ToolCall(name: tool.name, arguments: args), answer: null);
    }
  }
  for (final tool in registry.tools.values) {
    // Guided output may nest args under the AnyOf choice name
    // ('Act_<tool>') or flat under the tool name.
    final candidates = [
      output[tool.name.value],
      output['Act_${tool.name.value}'],
    ];
    for (final candidate in candidates) {
      if (candidate is! Map<String, dynamic>) continue;
      final nested = candidate[tool.name.value];
      final value = nested is Map<String, dynamic> ? nested : candidate;
      final args = <String, dynamic>{};
      for (final key in value.keys) {
        if (key == 'tool') continue;
        args[key] = value[key];
      }
      return (call: ToolCall(name: tool.name, arguments: args), answer: null);
    }
  }
  final answerChoice = output['Answer'];
  if (answerChoice is Map<String, dynamic>) {
    return (call: null, answer: '${answerChoice['text'] ?? ''}');
  }
  // Decoded backends may nest the whole decision under 'text' — either as a
  // JSON-encoded string or as an already-decoded map.
  // Decoded backends may nest the whole decision under 'text' — either as a
  // JSON-encoded string or as an already-decoded map.
  final nested = output['text'];
  Object? decodedNested;
  if (nested is String) {
    try {
      decodedNested = jsonDecode(_stripCodeFence(nested));
    } on FormatException {
      // Not JSON — plain text answer below.
    }
  }
  final innerCandidates = [
    if (nested is Map<String, dynamic>) nested,
    if (decodedNested is Map<String, dynamic>) decodedNested,
  ];
  for (final candidate in innerCandidates) {
    final toolKey = candidate['tool'];
    if (toolKey is String) {
      final tool = registry.tools[ToolName(toolKey)];
      if (tool != null) {
        final args = <String, dynamic>{}
          ..addAll(candidate)
          ..remove('tool');
        return (call: ToolCall(name: tool.name, arguments: args), answer: null);
      }
      // Alternative shape some models emit: {"name": "write",
      // "arguments": {...}} — same call, different envelope.
      final nameKey = candidate['name'];
      if (nameKey is String) {
        final tool = registry.tools[ToolName(nameKey)];
        final argsValue = candidate['arguments'];
        if (tool != null && argsValue is Map<String, dynamic>) {
          return (
            call: ToolCall(name: tool.name, arguments: argsValue),
            answer: null,
          );
        }
      }
    }
    if (candidate['text'] != null) {
      return (call: null, answer: '${candidate['text']}');
    }
  }
  if (nested is String) {
    final stripped = _stripCodeFence(nested);
    return (call: null, answer: stripped.isEmpty ? nested : stripped);
  }
  // Fallback: treat the whole output as an answer.
  return (call: null, answer: jsonEncode(output));
}

/// A [GenerationHandler] decorator that routes every decision through the
/// guided-decision schema instead of native tool calling.
///
/// Wrap any backend handler (AFM, Gemma, mock). Tool calls decoded from the
/// structured output are returned as standard response [ToolCall]s; the world
/// executes them exactly as with native tool calling.
class StructuredToolDecisionHandler implements GenerationHandler {
  StructuredToolDecisionHandler({
    required this.inner,
    this.registryName = 'default',
  });

  /// The wrapped backend handler that performs actual generation.
  final GenerationHandler inner;

  /// Name of the [ToolRegistryResource] registry to derive the decision
  /// schema from. Must match the actor's [ActorTools] binding.
  final String registryName;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final registry = request.toolRegistry;
    if (registry == null || registry.tools.isEmpty) {
      return inner.generate(world, request);
    }

    // Force the decision through the guided schema; strip native tools so
    // backends don't double-handle them.
    final guided = ActorGenerateRequest(
      actorEntity: request.actorEntity,
      agentId: request.agentId,
      modelId: request.modelId,
      prompt: decisionPrompt(request.prompt),
      systemPrompt: request.systemPrompt,
      contextFragments: request.contextFragments,
      schema: decisionSchema(registry),
      toolRegistry: null,
      task: request.task,
      taskId: request.taskId,
    );

    final response = await inner.generate(world, guided);
    if (response.error.isNotEmpty) return response;

    final decoded = decodeDecision(response.structuredOutput, registry);
    final call = decoded.call;
    if (call != null) {
      return ActorGenerateResponse(
        actorEntity: response.actorEntity,
        structuredOutput: response.structuredOutput,
        rawOutput: response.rawOutput,
        toolCalls: [call],
        taskId: response.taskId,
      );
    }

    // Final answer — surface it as plain text.
    final answer = decoded.answer ?? '';
    return ActorGenerateResponse(
      actorEntity: response.actorEntity,
      structuredOutput: {'text': answer},
      rawOutput: answer,
      taskId: response.taskId,
    );
  }

  /// Compact instruction appended to the prompt describing the decision
  /// contract. Kept minimal — the schema itself carries most of the weight.
  static String decisionPrompt(String taskPrompt) =>
      '$taskPrompt\n\n'
      'Respond by choosing ONE option from the provided structure: '
      'either perform one tool action with its arguments, or give the '
      'final answer as text.';
}

/// Strip one markdown code fence (```json … ```) that weak models wrap around
/// otherwise-valid JSON despite instructions not to.
String _stripCodeFence(String s) {
  final trimmed = s.trim();
  final fence = RegExp(r'^```[a-zA-Z]*\s*\n(.*)\n```\s*$', dotAll: true);
  final match = fence.firstMatch(trimmed);
  return match != null ? match.group(1)!.trim() : trimmed;
}
