/// Constrained Dart renderer for the Qwen3 chat template (the cached
/// `mlx-community/Qwen3-0.6B-4bit` checkpoint ships the ChatML-with-
/// thinking Jinja template: `<|im_start|>role\n…<|im_end|>\n` turns, a
/// `<think>\n\n</think>\n\n` generation prefix when thinking is off, and
/// think-tag stripping on assistant history before the last user query).
///
/// This is a hand renderer for the SUPPORTED SUBSET, pinned byte-exactly
/// by `native/mlx_native/testdata/qwen3_chat_template_fixtures.json`
/// (recorded from the reference tokenizer's `apply_chat_template` with
/// `enable_thinking=False`). It is NOT a Jinja engine. Supported:
/// - string `content` on every message; roles system/user/assistant;
/// - a LEADING system message (later system messages render as their own
///   `<|im_start|>system` turn, which is what the template's loop does);
/// - `enable_thinking = false` semantics only: the generation prompt is
///   `<|im_start|>assistant\n<think>\n\n</think>\n\n` (the napbench law:
///   thinking off);
/// - `tools` (ADR 0058 tools rung): the `# Tools` system block — appended
///   to a leading system message with a blank line, or synthesized as its
///   own system turn when no system message exists — with tool JSON lines
///   dumped the way the reference `tojson` filter does
///   (`json.dumps(ensure_ascii=False)` defaults: insertion key order,
///   `", "`/`": "` separators, raw non-ASCII); a `tool`-role message
///   renders as a user turn wrapping the content in
///   `<tool_response>\n…\n</tool_response>`; assistant `<tool_call>`
///   history content renders plain;
/// - assistant history: content is cut to the text after its LAST
///   `</think>`; the `<think>` body is dropped for turns before the last
///   user query (the template's `reasoning_content` branch only fires for
///   turns AFTER the last query, which no wire request produces — a
///   trailing assistant turn renders plain).
///
/// Non-claims (unsupported, never silently approximated): CONSECUTIVE
/// tool messages are NOT merged into one user turn (the reference's
/// loop.first/last merge — each tool message here becomes its own user
/// turn; pinned by fixtures only for single non-consecutive tool turns),
/// user-role content that literally starts with `<tool_response>` (the
/// reversed-walk skip), list/multipart or `reasoning_content` fields,
/// `enable_thinking = true` rendering, `continue_final_message`, and any
/// other Jinja feature the fixtures do not pin.
library;

/// The `<think>`-head tail: Python's `.split('<think>')[-1]`.
String splitThinkHead(final String head) =>
    head.contains('<think>') ? head.split('<think>').last : head;

final class QwenChatMessage {
  const QwenChatMessage({required this.role, required this.content});

  final String role;
  final String content;
}

/// The `# Tools` system block appended when a call passes tools (the
/// template's exact instruction text — the `<tools>` lines are the tools
/// JSON-dumped one per line, reference `tojson` spacing).
String _toolsSystemBlock(final List<Object?> tools) =>
    '# Tools\n\n'
    'You may call one or more functions to assist with the user query.\n\n'
    'You are provided with function signatures within <tools></tools> XML '
    'tags:\n<tools>\n'
    '${tools.map(_templateJsonDumps).join('\n')}'
    '\n</tools>\n\n'
    'For each function call, return a json object with function name and '
    'arguments within <tool_call></tool_call> XML tags:\n<tool_call>\n'
    '{"name": <function-name>, "arguments": <args-json-object>}\n'
    '</tool_call>';

/// JSON-encodes one tool the way the reference template's Jinja `tojson`
/// filter does for this checkpoint's renderer chain:
/// `json.dumps(ensure_ascii=False)` defaults — insertion key order,
/// `", "`/`": "` separators, raw non-ASCII. (The LFM2.5 template's
/// `tojson` is the ensure_ascii=True variant — its own encoder lives in
/// that renderer.)
String _templateJsonDumps(final Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is bool) {
    return value ? 'true' : 'false';
  }
  if (value is num) {
    return '$value';
  }
  if (value is String) {
    return _templateJsonString(value);
  }
  if (value is List) {
    return '[${value.map(_templateJsonDumps).join(', ')}]';
  }
  if (value is Map) {
    return '{${value.entries.map((final entry) {
      final key = entry.key;
      if (key is! String) {
        throw ArgumentError.value(
          value,
          'tools',
          'the Qwen3 template renderer supports string object keys only',
        );
      }
      return '${_templateJsonString(key)}: ${_templateJsonDumps(entry.value)}';
    }).join(', ')}}';
  }
  throw ArgumentError.value(
    value,
    'tools',
    'the Qwen3 template renderer supports JSON-encodable tools only',
  );
}

/// A JSON string literal with Python `json.dumps(ensure_ascii=False)`
/// escaping: `\"`, `\\`, the `\b\t\n\f\r` shorthands, `\uXXXX` for
/// control runes — every other rune (including non-ASCII) stays raw.
String _templateJsonString(final String value) {
  final buffer = StringBuffer('"');
  for (final rune in value.runes) {
    switch (rune) {
      case 0x08:
        buffer.write(r'\b');
      case 0x09:
        buffer.write(r'\t');
      case 0x0a:
        buffer.write(r'\n');
      case 0x0c:
        buffer.write(r'\f');
      case 0x0d:
        buffer.write(r'\r');
      case 0x22:
        buffer.write(r'\"');
      case 0x5c:
        buffer.write(r'\\');
      default:
        if (rune < 0x20) {
          buffer.write('\\u${rune.toRadixString(16).padLeft(4, '0')}');
        } else {
          buffer.writeCharCode(rune);
        }
    }
  }
  buffer.write('"');
  return buffer.toString();
}

/// Renders the messages into the exact raw prompt the checkpoint expects.
/// No BOS: the Qwen3 template does not use one, and the native generate
/// path adds none for text prompts.
String renderQwenChatPrompt({
  required final List<QwenChatMessage> messages,
  final List<Object?>? tools,
  final bool addGenerationPrompt = true,
  final bool enableThinking = false,
}) {
  final buffer = StringBuffer();
  final toolsBlock = (tools == null || tools.isEmpty)
      ? ''
      : _toolsSystemBlock(tools);

  // Leading system message lifts out of the turn loop; tools append to it
  // after a blank line (template's system branch). With no system message
  // the tools block IS the system turn.
  var index0 = 0;
  if (messages.isNotEmpty && messages.first.role == 'system') {
    buffer
      ..write('<|im_start|>system\n')
      ..write(messages.first.content)
      ..write(toolsBlock.isEmpty ? '' : '\n\n$toolsBlock')
      ..write('<|im_end|>\n');
    index0 = 1;
  } else if (toolsBlock.isNotEmpty) {
    buffer
      ..write('<|im_start|>system\n')
      ..write(toolsBlock)
      ..write('<|im_end|>\n');
  }
  final turns = messages.sublist(index0);

  // last_query_index: the last user turn (the template walks REVERSED and
  // skips user turns whose content is a full <tool_response> block —
  // impossible in this subset, so it is simply the last user index,
  // absolute in the original message list).
  var lastQueryIndex = -1;
  for (var i = 0; i < messages.length; i++) {
    if (messages[i].role == 'user') lastQueryIndex = i;
  }

  // Python str.strip/lstrip/rstrip('\n') equivalents (Dart's trim family
  // takes no character set).
  String lstripNl(final String s) {
    var i = 0;
    while (i < s.length && s[i] == '\n') {
      i++;
    }
    return s.substring(i);
  }

  String rstripNl(final String s) {
    var e = s.length;
    while (e > 0 && s[e - 1] == '\n') {
      e--;
    }
    return s.substring(0, e);
  }

  for (var t = 0; t < turns.length; t++) {
    final m = turns[t];
    final absolute = t + index0;
    switch (m.role) {
      case 'system' || 'user':
        buffer
          ..write('<|im_start|>${m.role}\n')
          ..write(m.content)
          ..write('<|im_end|>\n');
      case 'tool':
        // A tool result renders as a user turn wrapping the content
        // (template's tool branch, single non-consecutive turn shape —
        // consecutive-tool merging is a recorded non-claim).
        buffer
          ..write('<|im_start|>user\n<tool_response>\n')
          ..write(m.content)
          ..write('\n</tool_response><|im_end|>\n');
      case 'assistant':
        // Think extraction happens for EVERY assistant turn (template
        // reassigns content before the positional branch); what differs by
        // position is whether the <think> body is preserved.
        var content = m.content;
        var reasoning = '';
        if (content.contains('</think>')) {
          final parts = content.split('</think>');
          reasoning = lstripNl(splitThinkHead(rstripNl(parts.first)));
          content = lstripNl(parts.last);
        }
        final keepThinking =
            absolute > lastQueryIndex && (t == turns.length - 1 || reasoning.isNotEmpty);
        buffer.write('<|im_start|>assistant\n');
        if (keepThinking) {
          buffer
            ..write('<think>\n')
            ..write(rstripNl(lstripNl(reasoning)))
            ..write('\n</think>\n\n')
            ..write(lstripNl(content));
        } else {
          buffer.write(content);
        }
        buffer.write('<|im_end|>\n');
    }
  }

  if (addGenerationPrompt) {
    buffer.write('<|im_start|>assistant\n');
    if (!enableThinking) {
      buffer.write('<think>\n\n</think>\n\n');
    }
  }
  return buffer.toString();
}
