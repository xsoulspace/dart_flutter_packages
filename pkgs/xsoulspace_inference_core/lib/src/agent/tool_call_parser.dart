import 'dart:convert';

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

class ToolDef {
  const ToolDef({
    required this.name,
    required this.description,
    required this.schema,
    required this.execute,
  });
  final String name;
  final String description;
  final Map<String, dynamic> schema; // keep it simple JSON-schema-like
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> args)
  execute;
}

class ToolRegistry {
  final Map<String, ToolDef> _tools = {};

  void register(ToolDef tool) => _tools[tool.name] = tool;

  ToolDef? get(String name) => _tools[name];

  Map<String, dynamic>? getSchema(String name) => _tools[name]?.schema;

  Future<Map<String, dynamic>> execute(String name, Map<String, dynamic> args) {
    final tool = _tools[name];
    if (tool == null) {
      return Future.value({'error': 'Unknown tool: $name'});
    }
    return tool.execute(args);
  }

  /// Compact list for the system prompt (progressive disclosure)
  String compactToolList() {
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
