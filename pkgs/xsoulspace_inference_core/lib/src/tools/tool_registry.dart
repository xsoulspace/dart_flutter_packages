// ─────────────────────────────────────────────
// 2. Tool definition + registry
// ─────────────────────────────────────────────
import 'dart:convert';

import 'package:meta/meta.dart';

import '../structured_output/structured_output.dart';

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
    if (argsSchema.isNotEmpty) 'parameters': argsSchema.toJson(),
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
