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
/// - assistant history: content is cut to the text after its LAST
///   `</think>`; the `<think>` body is dropped for turns before the last
///   user query (the template's `reasoning_content` branch only fires for
///   turns AFTER the last query, which no wire request produces — a
///   trailing assistant turn renders plain).
///
/// Non-claims (unsupported, never silently approximated): tools and
/// tool_calls/tool responses (the template's `# Tools` system block and
/// `<tool_call>`/`<tool_response>` shapes), list/multipart or
/// `reasoning_content` fields, `enable_thinking = true` rendering,
/// `continue_final_message`, and any other Jinja feature the fixtures do
/// not pin.
library;

/// The `<think>`-head tail: Python's `.split('<think>')[-1]`.
String splitThinkHead(final String head) =>
    head.contains('<think>') ? head.split('<think>').last : head;

final class QwenChatMessage {
  const QwenChatMessage({required this.role, required this.content});

  final String role;
  final String content;
}

/// Renders the messages into the exact raw prompt the checkpoint expects.
/// No BOS: the Qwen3 template does not use one, and the native generate
/// path adds none for text prompts.
String renderQwenChatPrompt({
  required final List<QwenChatMessage> messages,
  final bool addGenerationPrompt = true,
  final bool enableThinking = false,
}) {
  final buffer = StringBuffer();

  // Leading system message lifts out of the turn loop (template's
  // no-tools branch).
  var index0 = 0;
  if (messages.isNotEmpty && messages.first.role == 'system') {
    buffer
      ..write('<|im_start|>system\n')
      ..write(messages.first.content)
      ..write('<|im_end|>\n');
    index0 = 1;
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
