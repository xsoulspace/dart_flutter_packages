import 'dart:convert';

import 'package:from_json_to_json/from_json_to_json.dart';

import 'tool_registry.dart' show ToolName;

/// A parsed tool call from an LLM response.
class ToolCall {
  const ToolCall({required this.name, required this.arguments});
  final ToolName name;
  final Map<String, dynamic> arguments;
}

/// Result of a tool call execution.
class ToolExecutionResult {
  const ToolExecutionResult({required this.name, required this.output});
  factory ToolExecutionResult.encode({
    required String name,
    required Map<String, dynamic>? output,
  }) => ToolExecutionResult(
    name: name,
    output: output == null ? null : jsonEncode(output),
  );

  factory ToolExecutionResult.fromJson(Map<String, dynamic> json) =>
      ToolExecutionResult(
        name: jsonDecodeString(json['name']),
        output: jsonDecodeString(json['output']),
      );
  final String name;
  final String? output;

  Map<String, dynamic> toJson() => {'name': name, 'output': output};
}
