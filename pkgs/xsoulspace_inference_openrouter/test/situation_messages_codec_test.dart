// ignore_for_file: lines_longer_than_80_chars

/// Tests for the Situation → messages codec (fair-comparison plan Step 1):
/// messages are computed per call from protocol-tagged fragments — never
/// stored state.
library;

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_openrouter/xsoulspace_inference_openrouter.dart';

void main() {
  group('SituationMessagesCodec', () {
    test('renders roles from protocol-tagged fragments', () {
      final messages = SituationMessagesCodec.render(
        prompt: 'Continue the task.',
        systemPrompt: 'You are a coding agent.',
        fragments: [
          ContextFragmentProtocol.assistant('Reading config first.'),
          ContextFragmentProtocol.toolResult('write', '{"ok":true}'),
          ContextFragmentProtocol.absence('prior dialogue unavailable'),
        ],
      );

      expect(messages[0]['role'], 'system');
      expect(messages[0]['content'], 'You are a coding agent.');
      // Green-screen + unattributed context collapse into one user message.
      expect(messages[1]['role'], 'user');
      expect(messages[1]['content'], contains('off-screen'));
      expect(messages[1]['content'], contains('absence:prior dialogue'));
      // The actor's own prior output is an assistant message.
      expect(messages[2]['role'], 'assistant');
      expect(messages[2]['content'], 'Reading config first.');
      // Tool results render as notes (self-contained ⇒ pairs never split).
      expect(messages[3]['content'], contains('- write {"ok":true}'));
      // The decision prompt is always the final user message.
      expect(messages.last['role'], 'user');
      expect(messages.last['content'], 'Continue the task.');
    });

    test('empty fragments yield system + prompt only', () {
      final messages = SituationMessagesCodec.render(
        prompt: 'p',
        systemPrompt: 's',
        fragments: const [],
      );
      expect(messages, hasLength(2));
      expect(messages[0]['role'], 'system');
      expect(messages[1]['content'], 'p');
    });

    test('isRenderable accepts tagged and plain fragments', () {
      expect(
        SituationMessagesCodec.isRenderable([
          ContextFragmentProtocol.assistant('a'),
          'plain context',
        ]),
        isTrue,
      );
    });
  });
}
