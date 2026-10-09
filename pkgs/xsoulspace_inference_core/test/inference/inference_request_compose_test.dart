import 'dart:convert';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// ADR 0059 — the composable request surface: `GenerationOptions`,
/// `ChatMessage`, request-level `thinking`, `messages`, and `copyWith`.
void main() {
  group('GenerationOptions', () {
    test('composes, copies, and JSON round-trips', () {
      const options = GenerationOptions(
        maxTokens: 384,
        temperature: 0,
        stopSequences: ['</think>'],
        thinking: true,
      );
      final copy = options.copyWith(maxTokens: 512);
      expect(copy.maxTokens, 512);
      expect(copy.temperature, 0.0);
      expect(copy.stopSequences, options.stopSequences);
      expect(copy.thinking, isTrue);

      final roundTrip = GenerationOptions.fromJson(
        jsonDecode(jsonEncode(copy.toJson())) as Map<String, dynamic>,
      );
      expect(roundTrip.maxTokens, 512);
      expect(roundTrip.temperature, 0.0);
      expect(roundTrip.stopSequences, const ['</think>']);
      expect(roundTrip.thinking, isTrue);
    });

    test('empty options carry nothing on the wire map', () {
      expect(const GenerationOptions().toJson(), <String, dynamic>{});
    });
  });

  group('ChatMessage', () {
    test('role factories and JSON round-trip', () {
      const messages = [
        ChatMessage.system('be brief'),
        ChatMessage.user('hi'),
        ChatMessage.assistant('hello'),
        ChatMessage.tool('{}'),
      ];
      expect(messages.map((m) => m.role), const [
        ChatRole.system,
        ChatRole.user,
        ChatRole.assistant,
        ChatRole.tool,
      ]);
      for (final message in messages) {
        final roundTrip = ChatMessage.fromJson(
          jsonDecode(jsonEncode(message.toJson())) as Map<String, dynamic>,
        );
        expect(roundTrip.role, message.role);
        expect(roundTrip.content, message.content);
      }
    });

    test('unknown role decodes to user, never throws', () {
      final message = ChatMessage.fromJson({'role': 'engine', 'content': 'x'});
      expect(message.role, ChatRole.user);
      expect(message.content, 'x');
    });
  });

  group('InferenceRequest', () {
    test('text and structured factories agree on every shared field', () {
      const messages = [ChatMessage.system('s'), ChatMessage.user('u')];
      final text = InferenceRequest(
        prompt: 'p',
        systemPrompt: 'sys',
        messages: messages,
        maxTokens: 64,
        temperature: 0.5,
        stopSequences: const ['stop'],
        thinking: true,
      );
      final structured = InferenceRequest.structured(
        prompt: 'p',
        systemPrompt: 'sys',
        messages: messages,
        maxTokens: 64,
        temperature: 0.5,
        stopSequences: const ['stop'],
        thinking: true,
      );
      for (final request in [text, structured]) {
        expect(request.systemPrompt, 'sys');
        expect(request.messages.map((m) => m.content), const ['s', 'u']);
        expect(request.maxTokens, 64);
        expect(request.temperature, 0.5);
        expect(request.stopSequences, const ['stop']);
        expect(request.thinking, isTrue);
        expect(
          request.generationOptions.maxTokens,
          64,
          reason: 'generationOptions views the flat fields',
        );
        expect(request.generationOptions.thinking, isTrue);
      }
      // The only intended difference: the schema payload (an explicit
      // schema round-trips through SchemaBundle; the default is empty on
      // both factories).
      expect(text.outputSchema, const <String, dynamic>{});
      expect(structured.outputSchema, text.outputSchema);
    });

    test('copyWith derives without mutating and round-trips fields', () {
      final base = InferenceRequest(prompt: 'draft', maxTokens: 32);
      final derived = base.copyWith(
        prompt: 'final',
        temperature: 0.2,
        thinking: false,
        messages: const [ChatMessage.user('final')],
      );
      expect(base.prompt, 'draft', reason: 'derivation never mutates');
      expect(base.maxTokens, 32);
      expect(base.thinking, isNull);
      expect(derived.prompt, 'final');
      expect(derived.maxTokens, 32, reason: 'unset fields carry over');
      expect(derived.temperature, 0.2);
      expect(derived.thinking, isFalse);
      expect(derived.messages.single.content, 'final');
    });

    test('messages stay absent from the map when empty', () {
      final request = InferenceRequest(prompt: 'p');
      expect(request.messages, isEmpty);
      expect(request.value.containsKey('messages'), isFalse);
    });
  });
}
