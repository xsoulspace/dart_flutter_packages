import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart';

/// The Qwen3 chat-template gate: the hand renderer must reproduce the
/// reference tokenizer's `apply_chat_template` output byte-for-byte on
/// every recorded case (venv-recorded fixtures — provenance in the file).
void main() {
  final fixtureFile = File(
    'native/mlx_native/testdata/qwen3_chat_template_fixtures.json',
  );
  test('renderer reproduces the reference renders byte-exactly', () {
    if (!fixtureFile.existsSync()) {
      return markTestSkipped('qwen chat template fixtures absent');
    }
    final fixture =
        jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
    for (final raw in fixture['cases'] as List) {
      final c = raw as Map<String, dynamic>;
      final messages = <QwenChatMessage>[
        for (final m in c['messages'] as List)
          QwenChatMessage(
            role: (m as Map)['role'] as String,
            content: m['content'] as String,
          ),
      ];
      final tools = c['tools'] is List && (c['tools'] as List).isNotEmpty
          ? (c['tools'] as List).toList()
          : null;
      final rendered = renderQwenChatPrompt(
        messages: messages,
        tools: tools,
        enableThinking: c['enable_thinking'] as bool? ?? false,
      );
      expect(
        rendered,
        c['rendered'] as String,
        reason: 'case ${c['id']} diverged from the reference render',
      );
    }
  });
}
