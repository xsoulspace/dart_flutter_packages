import 'dart:convert';

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
  final Map<String, dynamic>? payload; // null for getDefinition
  final int start;
  final int end;

  @override
  String toString() =>
      'ToolTag($type | $toolName | ${payload != null ? jsonEncode(payload) : null})';
}

// ignore: avoid_classes_with_only_static_members
class ToolTagParser {
  // Matches: <getDefinition|name>  or  <call|name|{...}>  or  <result|name|{...}>
  static final _tagRegex = RegExp(
    r'<(getDefinition|call|result)\|([a-zA-Z0-9_]+)(?:\|(\{.*?\}))?>',
    multiLine: true,
    dotAll: true,
  );

  /// Finds every tool tag in the given text.
  static List<ToolTag> parse(String text) {
    final tags = <ToolTag>[];

    for (final match in _tagRegex.allMatches(text)) {
      final typeStr = match.group(1)!;
      final name = match.group(2)!;
      final rawPayload = match.group(3);

      Map<String, dynamic>? payload;
      if (rawPayload != null) {
        try {
          payload = jsonDecode(rawPayload) as Map<String, dynamic>;
        } catch (_) {
          // Malformed JSON – you can decide to skip or surface an error
          continue;
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
          start: match.start,
          end: match.end,
        ),
      );
    }

    return tags;
  }

  /// Convenience: returns the first actionable tag (getDefinition or call).
  /// Useful when the model is only allowed to emit one tag per turn.
  static ToolTag? lastActionable(String text) {
    final tags = parse(text);
    return tags.cast<ToolTag?>().lastWhere(
      (t) => t!.type == ToolTagType.getDefinition || t.type == ToolTagType.call,
      orElse: () => null,
    );
  }

  /// Replaces a specific tag range with a new <result|...> string.
  /// Useful when you want to keep the rest of the model’s text intact.
  static String injectResult({
    required String original,
    required ToolTag originalTag,
    required String toolName,
    required Object? resultPayload,
  }) {
    final resultTag = '<result|$toolName|${jsonEncode(resultPayload)}>';
    return original.replaceRange(originalTag.start, originalTag.end, resultTag);
  }
}
