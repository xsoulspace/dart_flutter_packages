/// Constrained Dart renderer for the LFM2.5-Instruct chat template
/// (ADR 0055: the cached `LiquidAI/LFM2.5-1.2B-Instruct-MLX-4bit`
/// checkpoint ships a ChatML-ish Jinja template — BOS prefix, system
/// folding, tools appended to the system block as `List of tools: [...]`,
/// think-tag stripping on non-last assistant turns, `<|im_start|>role\n…`
/// turns, and the assistant generation prompt).
///
/// This is a hand renderer for the SUPPORTED SUBSET, pinned byte-exactly
/// by `native/laya_rust/testdata/lfm25_chat_template_fixtures.json`
/// (recorded from the reference tokenizer). It is NOT a Jinja engine.
/// Supported:
/// - string `content` on every message; roles system/user/assistant;
/// - a LEADING system message folded into the system block (a later
///   system message renders as its own `<|im_start|>system` turn, which
///   is what the template's loop does);
/// - `tools` as JSON-encodable objects, dumped the way the reference's
///   Jinja `tojson` does (Python `json.dumps` defaults: insertion key
///   order, `", "`/`": "` separators, `ensure_ascii` escapes);
/// - `keep_past_thinking = false` semantics only: a NON-last assistant
///   message's content is cut to the text after its LAST `</think>` and
///   trimmed; the last assistant message keeps its thinking.
///
/// Non-claims (unsupported, and never silently approximated): tool-call
/// assistant responses, list/multipart content, `continue_final_message`,
/// `keep_past_thinking = true`, custom `bos_token`, and any other Jinja
/// feature the fixture does not pin.
library;

/// One chat message. [role] is one of system/user/assistant for the
/// supported subset; [content] must be the final string content.
final class Lfm2ChatMessage {
  const Lfm2ChatMessage({required this.role, required this.content});

  final String role;
  final String content;
}

/// Renders the messages into the exact raw prompt the checkpoint expects.
///
/// [addGenerationPrompt] appends `<|im_start|>assistant\n` (the generation
/// prompt). [includeBos] controls the leading `<|startoftext|>`: the FULL
/// template output (and the recorded fixtures) include it, but the native
/// generate path ALSO prepends the BOS id for text prompts, so a caller
/// handing the render to [NativeLfm2TextEngine.generate] passes
/// `includeBos: false` and lets the native side add exactly one BOS.
String renderLfm2ChatPrompt({
  required final List<Lfm2ChatMessage> messages,
  final List<Object?>? tools,
  final bool addGenerationPrompt = true,
  final bool includeBos = true,
}) {
  final buffer = StringBuffer();
  if (includeBos) {
    buffer.write('<|startoftext|>');
  }

  // System folding: a leading system message is lifted out of the turn
  // loop (template lines 6-9); anything left renders as plain turns.
  var systemPrompt = '';
  var turns = messages;
  if (messages.isNotEmpty && messages.first.role == 'system') {
    systemPrompt = messages.first.content;
    turns = messages.sublist(1);
  }
  if (tools != null && tools.isNotEmpty) {
    systemPrompt +=
        '${systemPrompt.isEmpty ? '' : '\n'}'
        'List of tools: [${tools.map(_templateJsonDumps).join(', ')}]';
  }
  if (systemPrompt.isNotEmpty) {
    buffer.write('<|im_start|>system\n$systemPrompt<|im_end|>\n');
  }

  var lastAssistantIndex = -1;
  for (var i = 0; i < turns.length; i++) {
    if (turns[i].role == 'assistant') {
      lastAssistantIndex = i;
    }
  }
  for (var i = 0; i < turns.length; i++) {
    final message = turns[i];
    buffer.write('<|im_start|>${message.role}\n');
    var content = message.content;
    if (message.role == 'assistant' && i != lastAssistantIndex) {
      // keep_past_thinking = false: keep only what follows the LAST
      // `</think>` (Python `content.split("</think>")[-1] | trim`).
      final marker = content.lastIndexOf('</think>');
      if (marker >= 0) {
        content = content.substring(marker + '</think>'.length).trim();
      }
    }
    buffer.write('$content<|im_end|>\n');
  }
  if (addGenerationPrompt) {
    buffer.write('<|im_start|>assistant\n');
  }
  return buffer.toString();
}

/// JSON-encodes one tool the way the reference template's Jinja `tojson`
/// filter does for this checkpoint's renderer chain: Python `json.dumps`
/// defaults — insertion key order, `', '`/`': '` separators, and
/// `ensure_ascii` escaping (every non-printable-ASCII rune becomes a
/// `\uXXXX` escape, surrogate pairs for astral runes). Note Dart's own
/// `jsonEncode` differs on BOTH counts (compact separators, raw
/// non-ASCII), which is why this encoder exists.
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
          'the LFM2.5 template renderer supports string object keys only',
        );
      }
      return '${_templateJsonString(key)}: ${_templateJsonDumps(entry.value)}';
    }).join(', ')}}';
  }
  throw ArgumentError.value(
    value,
    'tools',
    'the LFM2.5 template renderer supports JSON-encodable tools only',
  );
}

/// A JSON string literal with Python `json.dumps(ensure_ascii=True)`
/// escaping: `\"`, `\\`, the `\b\t\n\f\r` shorthands, `\uXXXX` (lowercase
/// hex) for every other rune outside printable ASCII (`\ -~`), and
/// surrogate pairs for astral runes.
String _templateJsonString(final String value) {
  final buffer = StringBuffer('"');
  for (final rune in value.runes) {
    if (rune >= 0x20 && rune <= 0x7e) {
      if (rune == 0x22) {
        buffer.write(r'\"');
      } else if (rune == 0x5c) {
        buffer.write(r'\\');
      } else {
        buffer.writeCharCode(rune);
      }
      continue;
    }
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
      default:
        if (rune > 0xffff) {
          final shifted = rune - 0x10000;
          final high = 0xd800 + (shifted >> 10);
          final low = 0xdc00 + (shifted & 0x3ff);
          buffer
            ..write('\\u${high.toRadixString(16).padLeft(4, '0')}')
            ..write('\\u${low.toRadixString(16).padLeft(4, '0')}');
        } else {
          buffer.write('\\u${rune.toRadixString(16).padLeft(4, '0')}');
        }
    }
  }
  buffer.write('"');
  return buffer.toString();
}
