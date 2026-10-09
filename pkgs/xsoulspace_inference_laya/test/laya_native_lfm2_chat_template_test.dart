import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_laya/xsoulspace_inference_laya.dart';

/// The LFM2.5-Instruct chat template renderer gate (ADR 0055): the Dart
/// renderer must reproduce the venv-recorded reference renders BYTE-EXACTLY
/// for its supported subset (see testdata/lfm25_chat_template_fixtures.json
/// provenance — transformers AutoTokenizer.apply_chat_template on the cached
/// snapshot). Pure Dart — runs wherever the fixture is committed.
void main() {
  final fixtureFile = File(
    'native/laya_rust/testdata/lfm25_chat_template_fixtures.json',
  );

  test('renderer reproduces the recorded reference renders exactly', () {
    if (!fixtureFile.existsSync()) {
      return markTestSkipped('chat template fixture absent');
    }
    final fixture =
        jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
    final cases = fixture['cases'] as Map<String, dynamic>;

    // (a) system + user.
    expect(
      renderLfm2ChatPrompt(
        messages: const <Lfm2ChatMessage>[
          Lfm2ChatMessage(role: 'system', content: 'You are a precise search assistant.'),
          Lfm2ChatMessage(role: 'user', content: 'What is binary search?'),
        ],
      ),
      cases['system_user'],
      reason: 'system+user render diverged from the reference',
    );

    // (b) multi-turn where an EARLIER assistant turn carries thinking —
    // keep-past-thinking=false strips it; the last assistant keeps its own.
    expect(
      renderLfm2ChatPrompt(
        messages: const <Lfm2ChatMessage>[
          Lfm2ChatMessage(role: 'user', content: 'What is binary search?'),
          Lfm2ChatMessage(
            role: 'assistant',
            content:
                '<think>Recall the definition first.</think>Binary search halves the range each step.',
          ),
          Lfm2ChatMessage(role: 'user', content: 'And its complexity?'),
          Lfm2ChatMessage(role: 'assistant', content: 'O(log n) comparisons per lookup.'),
          Lfm2ChatMessage(role: 'user', content: 'When does it fail?'),
        ],
      ),
      cases['think_stripped_multiturn'],
      reason: 'think-strip multi-turn render diverged from the reference',
    );

    // (c) tools: two tool objects through the Python-dumps-compatible
    // encoder (separators, insertion order, ensure_ascii) — the `<` in the
    // second description pins that no htmlsafe re-escaping happens.
    expect(
      renderLfm2ChatPrompt(
        messages: const <Lfm2ChatMessage>[
          Lfm2ChatMessage(role: 'user', content: 'Search the web for laya.'),
        ],
        tools: const <Object?>[
          <String, Object?>{
            'name': 'web_search',
            'description': 'Searches the web.',
            'parameters': <String, Object?>{
              'query': <String, Object?>{'type': 'string'},
            },
          },
          <String, Object?>{
            'name': 'calculator',
            'description': 'Evaluates arithmetic like a<b comparison.',
            'parameters': <String, Object?>{
              'expression': <String, Object?>{'type': 'string'},
            },
          },
        ],
      ),
      cases['two_tools'],
      reason: 'tools render diverged from the reference',
    );
  });

  test('includeBos=false drops only the leading BOS token', () {
    const messages = <Lfm2ChatMessage>[
      Lfm2ChatMessage(role: 'user', content: 'Hi.'),
    ];
    final full = renderLfm2ChatPrompt(messages: messages);
    final withoutBos = renderLfm2ChatPrompt(messages: messages, includeBos: false);
    expect(full, startsWith('<|startoftext|>'));
    expect(withoutBos, full.substring('<|startoftext|>'.length));
  });
}
