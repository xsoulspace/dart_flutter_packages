// tool_agent.dart
import 'dart:convert';

import '../../../xsoulspace_inference_core.dart';
import 'tool_registry.dart';

// ─────────────────────────────────────────────
// 1. Tag model + parser
// ─────────────────────────────────────────────

enum ToolTagType { getDefinition, call, result }

class ToolTag {
  const ToolTag({
    required this.type,
    required this.toolName,
    required this.start,
    required this.end,
    this.payload,
  });
  final ToolTagType type;
  final String toolName;
  final Map<String, dynamic>? payload;
  final int start;
  final int end;
}

// ignore: avoid_classes_with_only_static_members
class ToolTagParser {
  static final _regex = RegExp(
    r'<(getDefinition|call|result)\|([a-zA-Z0-9_]+)(?:\|(\{.*?\}))?>',
    multiLine: true,
    dotAll: true,
  );

  static List<ToolTag> parse(String text) {
    final tags = <ToolTag>[];
    for (final m in _regex.allMatches(text)) {
      final typeStr = m.group(1)!;
      final name = m.group(2)!;
      final raw = m.group(3);

      Map<String, dynamic>? payload;
      if (raw != null) {
        try {
          payload = jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {
          continue; // skip malformed
        }
      }

      final type = switch (typeStr) {
        'getDefinition' => ToolTagType.getDefinition,
        'call' => ToolTagType.call,
        'result' => ToolTagType.result,
        _ => null,
      };
      if (type == null) continue;

      tags.add(
        ToolTag(
          type: type,
          toolName: name,
          payload: payload,
          start: m.start,
          end: m.end,
        ),
      );
    }
    return tags;
  }
}

// ─────────────────────────────────────────────
// 4. System prompt (short, on-device friendly)
// ─────────────────────────────────────────────
// TODO(arenukvern): change tool protocol to make it aligned ith openai
String buildSystemPrompt(ToolRegistry registry, String role) =>
    '''
You are an $role. Use AVAILABLE TOOLS below accoridngly to TOOL PROTOCOL when to get, modify, provide real information.

TOOL PROTOCOL (strict print to execute)
1. Get a tool's schema:
   <getDefinition|toolName>

2. Call a tool accoringly to scheme:
   <call|toolName|{"arg": value}>

3. The runtime will reply with:
   <result|toolName|{...}>

CRITICAL RULES
- You have no private knowledge of the real world.
- If a question can be answered by one of the available tools, you MUST call the tool.
- Never invent data that a tool can provide.
- You may call the same tool multiple times with different arguments.
- After you receive tool results, produce the final JSON answer.
- Do not keep calling tools once you have enough information.

AVAILABLE TOOLS
${registry.getToolsAsString()}
''';

/// Parse tool calls from raw LLM output using tag-based parsing.
///
/// This is the default parser for raw LLM backends that don't have
/// native tool call APIs. For backends with native tool call support
/// (Apple Foundation, OpenAI, etc.), the [ModelRuntime] should return
/// already-parsed [ToolCall] objects and this function is not used.
List<ToolCall> parseToolCalls(String rawOutput) {
  final tags = ToolTagParser.parse(rawOutput);
  final calls = tags.where((t) => t.type == ToolTagType.call).toList();
  return calls
      .map(
        (tag) => ToolCall(
          name: ToolName(tag.toolName),
          arguments: tag.payload ?? {},
        ),
      )
      .toList();
}
