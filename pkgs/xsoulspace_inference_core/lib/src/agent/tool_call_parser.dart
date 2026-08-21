// tool_agent.dart
import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';

import 'events.dart';
import 'structured_output/foundation_schema.dart';

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
// 2. Tool definition + registry
// ─────────────────────────────────────────────
/// [args] can be String or Map
/// returns serialized (encoded) answer
typedef ToolCallCallback = Future<String?> Function(Object? args);

class ToolDefinition {
  const ToolDefinition({
    this.description = '',
    this.argsSchema = SchemaBundle.empty,
  });
  final String description;
  final SchemaBundle argsSchema;

  ToolDef toDef({required ToolName name, required ToolCallCallback execute}) =>
      ToolDef(
        name: name,
        description: description,
        argsSchema: argsSchema,
        execute: execute,
      );
}

/// part of [ToolDefinition]
@immutable
class ToolName {
  const ToolName(this.value);
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ToolName && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

class ToolDef extends ToolDefinition {
  const ToolDef({
    required super.description,
    required this.name,
    required this.execute,
    super.argsSchema = SchemaBundle.empty,
  });

  factory ToolDef.encode({
    required ToolName name,
    required String description,
    required Future<Map<String, dynamic>?> Function(Object? args) execute,
    SchemaBundle argsSchema = SchemaBundle.empty,
  }) => ToolDef(
    name: name,
    argsSchema: argsSchema,
    description: description,
    execute: (e) async {
      final result = await execute(e);
      return result == null ? null : jsonEncode(result);
    },
  );

  final ToolName name;
  final ToolCallCallback execute;

  Map<String, dynamic> toJson() => {
    'name': name.value,
    'description': description,
    'parameters': argsSchema.toJson(),
  };
}

class ToolRegistry {
  final Map<ToolName, ToolDef> _tools = {};

  void register(ToolDef tool) => _tools[tool.name] = tool;

  ToolDef? get(ToolName name) => _tools[name];

  Map<String, dynamic>? getSchema(ToolName name) =>
      _tools[name]?.argsSchema.toJson();

  // ignore: avoid_annotating_with_dynamic
  Future<String?> execute(ToolName name, dynamic args) {
    final tool = _tools[name];
    if (tool == null) {
      return Future.value(jsonEncode({'error': 'Unknown tool: $name'}));
    }
    return tool.execute(args);
  }

  Map<ToolName, ToolDef> get tools => _tools;

  List<Map<String, dynamic>> getToolsJsons() =>
      _tools.values.map((e) => e.toJson()).toList();

  /// Compact list for the system prompt (progressive disclosure)
  String getToolsAsString() {
    if (_tools.isEmpty) return 'No tools available.';
    return _tools.values.map((t) => '- ${t.name}: ${t.description}').join('\n');
  }
}

// ─────────────────────────────────────────────
// 3. Runtime state (prevents endless loops)
// ─────────────────────────────────────────────

class CallRecord {
  CallRecord(this.signature, this.result);
  final String signature; // toolName + json(args)
  final Map<String, dynamic> result;
}

class ToolRuntimeState {
  final Set<String> knownSchemas = {};
  final List<CallRecord> history = [];
  int step = 0;

  static const int maxSteps = 5; // hard ceiling for on-device

  bool get reachedLimit => step >= maxSteps;
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
