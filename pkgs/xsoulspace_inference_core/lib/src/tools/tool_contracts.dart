import 'dart:convert';

import 'package:from_json_to_json/from_json_to_json.dart';

import 'tool_registry.dart' show ToolName;

/// A parsed tool call from an LLM response.
class ToolCall {
  const ToolCall({
    required this.name,
    required this.arguments,
    this.callId,
    this.namespace,
  });
  factory ToolCall.fromJson(Map<String, dynamic> json) => ToolCall(
    name: ToolName(jsonDecodeString(json['name'])),
    arguments: jsonDecodeMap(json['arguments']),
    callId: json['call_id'] as String?,
    namespace: json['namespace'] as String?,
  );

  final ToolName name;
  final Map<String, dynamic> arguments;

  /// Correlation identity distinguishes repeated calls to the same tool.
  final String? callId;
  final String? namespace;

  Map<String, dynamic> toJson() => {
    'name': name.value,
    'arguments': arguments,
    if (callId != null) 'call_id': callId,
    if (namespace != null) 'namespace': namespace,
  };
}

/// Result of a tool call execution.
class ToolExecutionResult {
  const ToolExecutionResult({
    required this.name,
    required this.output,
    this.callId,
  });
  factory ToolExecutionResult.encode({
    required String name,
    required Map<String, dynamic>? output,
    String? callId,
  }) => ToolExecutionResult(
    name: name,
    output: output == null ? null : jsonEncode(output),
    callId: callId,
  );

  factory ToolExecutionResult.fromJson(Map<String, dynamic> json) =>
      ToolExecutionResult(
        name: jsonDecodeString(json['name']),
        output: json['output'] as String?,
        callId: json['call_id'] as String?,
      );
  final String name;
  final String? output;
  final String? callId;

  Map<String, dynamic> toJson() => {
    'name': name,
    'output': output,
    if (callId != null) 'call_id': callId,
  };
}
