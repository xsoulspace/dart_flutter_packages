import 'dart:convert';

import 'tool_contracts.dart';
import 'tool_registry.dart';

enum ToolSyntaxKind { call, definition, result, thought }

/// One declarative envelope in a provider-selected syntax tree.
/// Payloads are JSON objects, except [ToolSyntaxEnvelope.signatureCall],
/// whose payload is the qualified function-signature grammar. Named
/// envelopes carry the name before [separator].
final class ToolSyntaxEnvelope {
  const ToolSyntaxEnvelope.jsonCall({
    required this.open,
    required this.close,
    this.nameKey = 'name',
    this.argumentsKey = 'arguments',
    this.rejectOrphanClose = false,
  }) : kind = ToolSyntaxKind.call,
       separator = null,
       signatureForm = false;

  /// A function-signature call region between the markers: the measured
  /// Liquid/LFM2.5 native shape
  /// (`<|tool_call_start|>[get_weather(city="Tokyo")]<|tool_call_end|>`).
  /// The payload grammar is the separately tested signature grammar
  /// (ADR 0058: a checkpoint's own textual format is qualified by
  /// fixtures before it executes), tolerant of the JSON list/object
  /// spellings the same checkpoints also emit.
  const ToolSyntaxEnvelope.signatureCall({
    required this.open,
    required this.close,
    this.rejectOrphanClose = false,
  }) : kind = ToolSyntaxKind.call,
       separator = null,
       nameKey = 'name',
       argumentsKey = 'arguments',
       signatureForm = true;

  const ToolSyntaxEnvelope.namedJson({
    required this.kind,
    required this.open,
    required this.close,
    this.separator = '|',
    this.rejectOrphanClose = false,
  }) : nameKey = 'name',
       argumentsKey = 'arguments',
       signatureForm = false;

  /// Declared non-action region; contents are never recursively parsed.
  const ToolSyntaxEnvelope.opaque({
    required this.open,
    required this.close,
    this.rejectOrphanClose = false,
  }) : kind = ToolSyntaxKind.thought,
       separator = null,
       nameKey = 'name',
       argumentsKey = 'arguments',
       signatureForm = false;

  /// Whether the payload parses as the qualified function-signature
  /// grammar instead of a JSON object.
  final bool signatureForm;

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

  /// The LFM2 native signature profile, qualified 2026-10-28 from live
  /// measurement of the LFM2.5-1.2B checkpoint on the function-tool
  /// surface: the model emits
  /// `<|tool_call_start|>[get_weather(city="Tokyo")]<|tool_call_end|>`.
  /// The payload grammar also admits the JSON list/object spellings the
  /// same checkpoint family emits (ADR 0058 tools bench, 2026-10-09).
  static const lfmNative = ToolCallSyntax(
    id: 'lfm-native-signature-v1',
    envelopes: [
      // The close marker is NOT reserved: the 1.2B checkpoint repeats a
      // completed call as a bare trailing duplicate (measured 2026-10-28),
      // and a close-only span carries no payload it could admit. The
      // repetition survives as presentation text; the matched envelope
      // supplies the call.
      ToolSyntaxEnvelope.signatureCall(
        open: '<|tool_call_start|>',
        close: '<|tool_call_end|>',
      ),
    ],
  );

  final String id;
  final List<ToolSyntaxEnvelope> envelopes;

  String renderCall(ToolCall call) {
    final envelope = envelopes.firstWhere(
      (node) => node.kind == ToolSyntaxKind.call,
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
    String text, {
    ToolRegistry? registry,
    bool requireRegistry = false,
    ToolSyntaxLimits limits = const ToolSyntaxLimits(),
  }) {
    ToolSyntaxParseResult fail(String code, int offset) =>
        ToolSyntaxParseResult._(errorCode: code, errorOffset: offset);
    if (limits.maxBytes <= 0 ||
        limits.maxNodes <= 0 ||
        limits.maxDepth <= 0 ||
        envelopes.isEmpty ||
        envelopes.any(
          (e) => e.open.isEmpty || e.close.isEmpty || e.separator == '',
        )) {
      return fail('tool_syntax_invalid_profile', 0);
    }
    if (envelopes.map((e) => e.open).toSet().length != envelopes.length ||
        envelopes.any(
          (e) =>
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
      final parsed = envelope.signatureForm
          ? _parseSignatureCalls(body)
          : _parseJsonPayload(body, envelope);
      if (parsed.errorCode != null) return fail(parsed.errorCode!, start);
      for (final (name, arguments) in parsed.calls!) {
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
        if (nodes.length >= limits.maxNodes) {
          return fail('tool_syntax_limit', start);
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
      }
      cursor = close + envelope.close.length;
    }
    return ToolSyntaxParseResult._(nodes: List.unmodifiable(nodes));
  }
}

/// One parsed call: the tool name and its argument map.
typedef _ParsedCall = (String, Map<String, dynamic>);

/// A payload parse outcome: the calls, or the named refusal.
final class _PayloadParse {
  const _PayloadParse.ok(this.calls) : errorCode = null;
  const _PayloadParse.error(this.errorCode) : calls = null;
  final List<_ParsedCall>? calls;
  final String? errorCode;
}

/// Decodes one JSON-object payload (the existing envelope grammar).
_PayloadParse _parseJsonPayload(String body, ToolSyntaxEnvelope envelope) {
  final String name;
  final Map<String, dynamic> arguments;
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
        return const _PayloadParse.error('tool_call_ambiguous');
      }
    } else {
      final decoded = jsonDecode(body) as Map;
      if (decoded.keys.any(
        (key) => key != envelope.nameKey && key != envelope.argumentsKey,
      )) {
        return const _PayloadParse.error('tool_call_malformed');
      }
      name = decoded[envelope.nameKey] as String;
      arguments = (decoded[envelope.argumentsKey] as Map)
          .cast<String, dynamic>();
      if (_hasDuplicateKeys(body)) {
        return const _PayloadParse.error('tool_call_ambiguous');
      }
    }
  } on Object {
    return const _PayloadParse.error('tool_call_malformed');
  }
  return _PayloadParse.ok([(name, arguments)]);
}

/// The qualified function-signature payload grammar (LFM2 native shape).
///
/// Measured forms, in admission order:
/// 1. JSON list of call objects: `[{"name": "write", "arguments": {...}}]`
///    (or a single object) — the structured spelling.
/// 2. Function signatures, optionally list-wrapped, comma-separated at
///    top level: `[get_weather(city="Tokyo"), ping()]` — values are
///    quoted strings (escapes decoded), integers, doubles, True, False
///    or None.
///
/// Admission is atomic: any malformed segment refuses the whole envelope.
_PayloadParse _parseSignatureCalls(String body) {
  if (body.isEmpty) {
    return const _PayloadParse.error('tool_call_malformed');
  }
  if (body.startsWith('{') || body.startsWith('[')) {
    final jsonCalls = _trySignatureJsonCalls(body);
    if (jsonCalls != null) return _PayloadParse.ok(jsonCalls);
  }
  var rest = body.trim();
  if (rest.startsWith('[') && rest.endsWith(']')) {
    rest = rest.substring(1, rest.length - 1).trim();
    if (rest.isEmpty) {
      return const _PayloadParse.error('tool_call_malformed');
    }
  }
  final calls = <_ParsedCall>[];
  for (final segment in _splitSignatureSegments(rest)) {
    final head = RegExp(r'^([A-Za-z0-9_]+)\s*\(([\s\S]*)\)$')
        .firstMatch(segment);
    if (head == null) {
      return const _PayloadParse.error('tool_call_malformed');
    }
    final arguments = <String, dynamic>{};
    final pair = RegExp(
      r'''([A-Za-z0-9_]+)\s*=\s*("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|-?\d+(?:\.\d+)?|True|False|None)''',
    );
    final argumentBody = head.group(2)!.trim();
    if (argumentBody.isNotEmpty) {
      final matches = pair.allMatches(argumentBody).toList();
      // Every pair must be accounted for: leftovers mean a value shape
      // this grammar has not qualified.
      var covered = 0;
      for (final match in matches) {
        covered += match.group(0)!.length;
      }
      // Pairs are comma-separated: completeness is measured against the
      // body with separators and whitespace removed.
      final bare = argumentBody.replaceAll(RegExp(r'[\s,]'), '');
      if (covered != bare.length) {
        return const _PayloadParse.error('tool_call_malformed');
      }
      for (final match in matches) {
        final key = match.group(1)!;
        if (arguments.containsKey(key)) {
          return const _PayloadParse.error('tool_call_ambiguous');
        }
        arguments[key] = _signatureValue(match.group(2)!);
      }
    }
    calls.add((head.group(1)!, arguments));
  }
  return _PayloadParse.ok(calls);
}

/// The JSON spelling of a signature payload: one call object or a list of
/// them. Null when the body is not that shape (the caller falls through
/// to the signature grammar).
List<_ParsedCall>? _trySignatureJsonCalls(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on Object {
    return null;
  }
  final elements = decoded is List ? decoded : [if (decoded is Map) decoded];
  if (elements.isEmpty) return null;
  final calls = <_ParsedCall>[];
  for (final element in elements) {
    if (element is! Map) return null;
    final name = element['name'];
    final arguments = element['arguments'];
    if (name is! String || arguments is! Map) return null;
    calls.add((name, arguments.cast<String, dynamic>()));
  }
  return calls;
}

/// Splits a signature body at top-level commas: depth counts parentheses
/// and brackets; quoted regions never split.
List<String> _splitSignatureSegments(String body) {
  final segments = <String>[];
  final current = StringBuffer();
  var depth = 0;
  var quoted = false;
  var escaped = false;
  for (var i = 0; i < body.length; i++) {
    final character = body[i];
    if (quoted) {
      current.write(character);
      if (escaped) {
        escaped = false;
      } else if (character == r'\') {
        escaped = true;
      } else if (character == '"' || character == "'") {
        quoted = false;
      }
      continue;
    }
    if (character == '"' || character == "'") {
      quoted = true;
      current.write(character);
      continue;
    }
    if (character == '(' || character == '[') depth++;
    if (character == ')' || character == ']') depth--;
    if (character == ',' && depth == 0) {
      segments.add(current.toString().trim());
      current.clear();
      continue;
    }
    current.write(character);
  }
  final last = current.toString().trim();
  if (last.isNotEmpty) segments.add(last);
  return segments;
}

/// Converts one qualified signature value: quoted string (escapes
/// decoded), integer, double, True, False or None.
dynamic _signatureValue(String raw) {
  if (raw.startsWith('"') || raw.startsWith("'")) {
    final body = raw.substring(1, raw.length - 1);
    final buffer = StringBuffer();
    for (var i = 0; i < body.length; i++) {
      final character = body[i];
      if (character != r'\' || i + 1 >= body.length) {
        buffer.write(character);
        continue;
      }
      i++;
      final String decoded = switch (body[i]) {
        'n' => '\n',
        't' => '\t',
        'r' => '\r',
        final other => other,
      };
      buffer.write(decoded);
    }
    return buffer.toString();
  }
  if (raw == 'True') return true;
  if (raw == 'False') return false;
  if (raw == 'None') return null;
  return num.tryParse(raw) ?? raw;
}

/// Decode an embedded tool payload without silently choosing duplicate keys.
///
/// Applies to every nested object and equivalent escaped key spelling. The
/// caller still owns payload type, size/depth limits, schema and authority.
Object? decodeJsonWithUniqueKeys(String source) {
  final decoded = jsonDecode(source);
  if (_hasDuplicateKeys(source)) {
    throw const FormatException('ambiguous duplicate JSON object key');
  }
  return decoded;
}

/// Called after JSON validation. Inspect the token stream before decoded
/// maps lose duplicate keys (including equivalent escaped key spellings).
bool _hasDuplicateKeys(String json) {
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
