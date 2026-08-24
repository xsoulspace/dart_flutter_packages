// ignore_for_file: lines_longer_than_80_chars

/// Situation → chat-completions `messages` codec.
///
/// The messages array is a **codec, not state** (fair-comparison plan Step 1
/// ruling): computed fresh per call from role-tagged context fragments
/// ([ContextFragmentProtocol]), never stored, never appended to. The beat
/// graph remains the only source of truth.
///
/// Rendering rules:
/// - `system`   ← system prompt (+ structured-output contract appended by the
///   client when applicable).
/// - `asst:` fragments → assistant messages (the actor's own prior outputs —
///   native-loop fidelity without storing a transcript).
/// - `tool:` fragments → tool-role notes; each is self-contained, so call/
///   result pairing can never split across a budget boundary.
/// - `absence:` and plain fragments → a single leading user context message
///   (green-screen notes + unattributed projected content).
/// - the decision prompt itself → the final user message.
library;

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// Renders budgeted context fragments into an OpenRouter messages array.
abstract final class SituationMessagesCodec {
  /// Build the messages array. [prompt] is the current decision prompt;
  /// [systemPrompt] the actor's system prompt; [fragments] the projected,
  /// protocol-tagged cut (see [ContextFragmentProtocol]).
  static List<Map<String, String>> render({
    required final String prompt,
    required final String systemPrompt,
    required final List<Object> fragments,
  }) {
    final assistant = <Map<String, String>>[];
    final toolNotes = <String>[];
    final context = <String>[];

    for (final raw in fragments) {
      final fragment = raw.toString();
      if (fragment.startsWith(ContextFragmentProtocol.assistantPrefix)) {
        assistant.add({
          'role': 'assistant',
          'content': fragment.substring(
            ContextFragmentProtocol.assistantPrefix.length,
          ),
        });
      } else if (fragment.startsWith(ContextFragmentProtocol.toolResultPrefix)) {
        toolNotes.add(
          fragment.substring(ContextFragmentProtocol.toolResultPrefix.length),
        );
      } else if (fragment.startsWith(ContextFragmentProtocol.absencePrefix)) {
        context.add(fragment);
      } else {
        context.add(fragment);
      }
    }

    return [
      if (systemPrompt.isNotEmpty) {'role': 'system', 'content': systemPrompt},
      if (context.isNotEmpty)
        {
          'role': 'user',
          'content':
              'Projected context (green-screened; anything not shown is '
              'off-screen):\n${context.join('\n')}',
        },
      ...assistant,
      if (toolNotes.isNotEmpty)
        {
          'role': 'user',
          'content':
              'Tool results observed so far:\n'
              '${toolNotes.map((t) => '- $t').join('\n')}',
        },
      {'role': 'user', 'content': prompt},
    ];
  }

  /// True when every non-absence fragment carries a recognizable role tag —
  /// guards against silently rendering untagged legacy cuts as empty roles.
  static bool isRenderable(final List<Object> fragments) => fragments.every(
    (final f) {
      final s = f.toString();
      return s.startsWith(ContextFragmentProtocol.assistantPrefix) ||
          s.startsWith(ContextFragmentProtocol.toolResultPrefix) ||
          s.startsWith(ContextFragmentProtocol.absencePrefix) ||
          !s.contains(':') ||
          s.startsWith('absence:');
    },
  );
}
