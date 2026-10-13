import 'dart:convert';

import 'tool_contracts.dart';
import 'tool_registry.dart';

enum ToolSyntaxKind { call, definition, result, thought }

/// One declarative envelope in a provider-selected syntax tree.
/// Payloads are JSON objects. Named envelopes carry the name before
/// [separator].
final class ToolSyntaxEnvelope {
  const ToolSyntaxEnvelope.jsonCall({
    required this.open,
    required this.close,
    this.nameKey = 'name',
    this.argumentsKey = 'arguments',
    this.rejectOrphanClose = false,
  }) : kind = ToolSyntaxKind.call,
       separator = null;

  const ToolSyntaxEnvelope.namedJson({
    required this.kind,
    required this.open,
    required this.close,
    this.separator = '|',
    this.rejectOrphanClose = false,
  }) : nameKey = 'name',
       argumentsKey = 'arguments';

  /// Declared non-action region; contents are never recursively parsed.
  const ToolSyntaxEnvelope.opaque({
    required this.open,
    required this.close,
    this.rejectOrphanClose = false,
  }) : kind = ToolSyntaxKind.thought,
       separator = null,
       nameKey = 'name',
       argumentsKey = 'arguments';

  final ToolSyntaxKind kind;
  final String open;
  final String close;
  final String? separator;
  final String nameKey;
  final String argumentsKey;

  /// The closing marker is reserved syntax outside a matched envelope.
  /// Opt in for dedicated delimiters, never ordinary punctuation such as `>`.
  final bool rejectOrphanClose;
}

final class ToolSyntaxLimits {
  const ToolSyntaxLimits({
    this.maxBytes = 1024 * 1024,
    this.maxNodes = 128,
    this.maxDepth = 64,
  });
  final int maxBytes;
  final int maxNodes;
  final int maxDepth;
}

/// Source offsets are UTF-16 code units, matching Dart substring/indexOf.
final class ToolSyntaxNode {
  const ToolSyntaxNode({
    required this.kind,
    required this.name,
    required this.payload,
    required this.start,
    required this.end,
    required this.raw,
    this.call,
  });
  final ToolSyntaxKind kind;
  final String name;
  final Map<String, dynamic> payload;
  final int start;
  final int end;
  final String raw;
  final ToolCall? call;
}

final class ToolSyntaxParseResult {
  const ToolSyntaxParseResult._({
    this.nodes = const [],
    this.errorCode,
    this.errorOffset,
  });
  final List<ToolSyntaxNode> nodes;
  final String? errorCode;
  final int? errorOffset;
  bool get success => errorCode == null;
  List<ToolCall> get calls => [
    for (final node in nodes)
      if (node.call != null) node.call!,
  ];
}

/// Composition, not execution: select one profile explicitly for the model.
/// Errors are atomic: a truncated later envelope never admits earlier calls.
final class ToolCallSyntax {
  const ToolCallSyntax({required this.id, required this.envelopes});

  static const qwenJson = ToolCallSyntax(
    id: 'qwen-delimited-json-v2',
    envelopes: [
      ToolSyntaxEnvelope.opaque(
        open: '<think>',
        close: '</think>',
        rejectOrphanClose: true,
      ),
      ToolSyntaxEnvelope.jsonCall(
        open: '<tool_call>',
        close: '</tool_call>',
        rejectOrphanClose: true,
      ),
    ],
  );
  static const legacyTags = ToolCallSyntax(
    id: 'legacy-named-json-tags-v1',
    envelopes: [
      ToolSyntaxEnvelope.opaque(open: '<think>', close: '</think>'),
      ToolSyntaxEnvelope.namedJson(
        kind: ToolSyntaxKind.definition,
        open: '<getDefinition|',
        close: '>',
      ),
      ToolSyntaxEnvelope.namedJson(
        kind: ToolSyntaxKind.call,
        open: '<call|',
        close: '>',
      ),
      ToolSyntaxEnvelope.namedJson(
        kind: ToolSyntaxKind.result,
        open: '<result|',
        close: '>',
      ),
    ],
  );

  final String id;
  final List<ToolSyntaxEnvelope> envelopes;

  String renderCall(final ToolCall call) {
    final envelope = envelopes.firstWhere(
      (final node) => node.kind == ToolSyntaxKind.call,
    );
    final payload = envelope.separator == null
        ? jsonEncode({
            envelope.nameKey: call.name.value,
            envelope.argumentsKey: call.arguments,
          })
        : '${call.name.value}${envelope.separator}'
              '${jsonEncode(call.arguments)}';
    return '${envelope.open}$payload${envelope.close}';
  }

  ToolSyntaxParseResult parse(
    final String text, {
    final ToolRegistry? registry,
    final bool requireRegistry = false,
    final ToolSyntaxLimits limits = const ToolSyntaxLimits(),
  }) {
    ToolSyntaxParseResult fail(final String code, final int offset) =>
        ToolSyntaxParseResult._(errorCode: code, errorOffset: offset);
    if (limits.maxBytes <= 0 ||
        limits.maxNodes <= 0 ||
        limits.maxDepth <= 0 ||
        envelopes.isEmpty ||
        envelopes.any(
          (final e) => e.open.isEmpty || e.close.isEmpty || e.separator == '',
        )) {
      return fail('tool_syntax_invalid_profile', 0);
    }
    if (envelopes.map((final e) => e.open).toSet().length != envelopes.length ||
        envelopes.any(
          (final e) =>
              e.separator == null &&
              (e.nameKey.isEmpty ||
                  e.argumentsKey.isEmpty ||
                  e.nameKey == e.argumentsKey),
        )) {
      return fail('tool_syntax_invalid_profile', 0);
    }
    if (utf8.encode(text).length > limits.maxBytes) {
      return fail('tool_syntax_limit', 0);
    }
    final nodes = <ToolSyntaxNode>[];
    var cursor = 0;
    String? fence;
    int? inlineTicks;
    while (cursor < text.length) {
      ToolSyntaxEnvelope? envelope;
      var start = -1;
      var orphanClose = false;
      for (final candidate in envelopes) {
        final position = text.indexOf(candidate.open, cursor);
        if (position >= 0 && (start < 0 || position < start)) {
          start = position;
          envelope = candidate;
          orphanClose = false;
        }
        if (candidate.rejectOrphanClose) {
          final closing = text.indexOf(candidate.close, cursor);
          if (closing >= 0 && (start < 0 || closing < start)) {
            start = closing;
            envelope = candidate;
            orphanClose = true;
          }
        }
      }
      if (envelope == null) break;
      // A fenced source/example is not an assistant action segment. Refuse
      // ambiguity instead of extracting an executable-looking substring.
      for (final marker in RegExp(
        '`+|~{3,}',
      ).allMatches(text.substring(cursor, start))) {
        final token = marker.group(0)!;
        if (token.startsWith('`') && token.length < 3 && fence == null) {
          if (inlineTicks == null) {
            inlineTicks = token.length;
          } else if (inlineTicks == token.length) {
            inlineTicks = null;
          }
          continue;
        }
        if (fence == null) {
          fence = token;
        } else if (fence == token) {
          fence = null;
        }
      }
      if (fence != null || inlineTicks != null) {
        return fail('tool_call_ambiguous', start);
      }
      if (orphanClose) {
        return fail(
          envelope.kind == ToolSyntaxKind.thought
              ? 'tool_thinking_ambiguous'
              : 'tool_call_malformed',
          start,
        );
      }
      if (nodes.length >= limits.maxNodes) {
        return fail('tool_syntax_limit', start);
      }
      final payloadStart = start + envelope.open.length;
      if (envelope.kind == ToolSyntaxKind.thought) {
        final close = text.indexOf(envelope.close, payloadStart);
        if (close < 0) return fail('tool_thinking_truncated', start);
        final nested = text.indexOf(envelope.open, payloadStart);
        if (nested >= 0 && nested < close) {
          return fail('tool_thinking_ambiguous', start);
        }
        final end = close + envelope.close.length;
        nodes.add(
          ToolSyntaxNode(
            kind: ToolSyntaxKind.thought,
            name: '',
            payload: const {},
            start: start,
            end: end,
            raw: text.substring(start, end),
          ),
        );
        cursor = end;
        continue;
      }
      var quoted = false;
      var escaped = false;
      var depth = 0;
      var close = -1;
      for (var i = payloadStart; i < text.length; i++) {
        final character = text[i];
        if (quoted) {
          if (escaped) {
            escaped = false;
          } else if (character == r'\') {
            escaped = true;
          } else if (character == '"') {
            quoted = false;
          }
          continue;
        }
        if (depth == 0 && text.startsWith(envelope.close, i)) {
          close = i;
          break;
        }
        if (character == '"') quoted = true;
        if (character == '{' || character == '[') depth++;
        if (character == '}' || character == ']') depth--;
        if (depth < 0) return fail('tool_call_malformed', start);
        if (depth > limits.maxDepth) return fail('tool_syntax_limit', start);
      }
      if (close < 0) return fail('tool_call_truncated', start);
      final body = text.substring(payloadStart, close).trim();
      String name;
      Map<String, dynamic> arguments;
      try {
        final separator = envelope.separator;
        if (separator != null) {
          final split = body.indexOf(separator);
          name = (split < 0 ? body : body.substring(0, split)).trim();
          arguments = split < 0
              ? <String, dynamic>{}
              : (jsonDecode(body.substring(split + separator.length)) as Map)
                    .cast<String, dynamic>();
          if (split >= 0 &&
              _hasDuplicateKeys(body.substring(split + separator.length))) {
            return fail('tool_call_ambiguous', start);
          }
        } else {
          final decoded = jsonDecode(body) as Map;
          if (decoded.keys.any(
            (final key) =>
                key != envelope!.nameKey && key != envelope.argumentsKey,
          )) {
            return fail('tool_call_malformed', start);
          }
          name = decoded[envelope.nameKey] as String;
          arguments = (decoded[envelope.argumentsKey] as Map)
              .cast<String, dynamic>();
          if (_hasDuplicateKeys(body)) {
            return fail('tool_call_ambiguous', start);
          }
        }
      } on Object {
        return fail('tool_call_malformed', start);
      }
      if (name.isEmpty ||
          name.trim() != name ||
          RegExp(r'[\s<>|]').hasMatch(name)) {
        return fail('tool_call_malformed', start);
      }
      if (envelope.kind == ToolSyntaxKind.call) {
        if (requireRegistry && registry == null) {
          return fail('tool_call_unbound', start);
        }
        if (registry != null && registry.get(ToolName(name)) == null) {
          return fail('tool_call_unknown', start);
        }
      }
      final end = close + envelope.close.length;
      nodes.add(
        ToolSyntaxNode(
          kind: envelope.kind,
          name: name,
          payload: Map.unmodifiable(arguments),
          start: start,
          end: end,
          raw: text.substring(start, end),
          call: envelope.kind == ToolSyntaxKind.call
              ? ToolCall(name: ToolName(name), arguments: arguments)
              : null,
        ),
      );
      cursor = end;
    }
    return ToolSyntaxParseResult._(nodes: List.unmodifiable(nodes));
  }
}

/// Decode an embedded tool payload without silently choosing duplicate keys.
///
/// Applies to every nested object and equivalent escaped key spelling. The
/// caller still owns payload type, size/depth limits, schema and authority.
Object? decodeJsonWithUniqueKeys(final String source) {
  final decoded = jsonDecode(source);
  if (_hasDuplicateKeys(source)) {
    throw const FormatException('ambiguous duplicate JSON object key');
  }
  return decoded;
}

/// Called after JSON validation. Inspect the token stream before decoded
/// maps lose duplicate keys (including equivalent escaped key spellings).
bool _hasDuplicateKeys(final String json) {
  final frames = <Set<String>?>[];
  for (var i = 0; i < json.length; i++) {
    final character = json[i];
    if (character == '{') frames.add(<String>{});
    if (character == '[') frames.add(null);
    if (character == '}' || character == ']') frames.removeLast();
    if (character != '"') continue;
    final start = i;
    var escaped = false;
    for (i++; i < json.length; i++) {
      if (escaped) {
        escaped = false;
      } else if (json[i] == r'\') {
        escaped = true;
      } else if (json[i] == '"') {
        break;
      }
    }
    var next = i + 1;
    while (next < json.length && json[next].trim().isEmpty) {
      next++;
    }
    if (next < json.length && json[next] == ':') {
      final key = jsonDecode(json.substring(start, i + 1)) as String;
      if (!frames.last!.add(key)) return true;
    }
  }
  return false;
}
