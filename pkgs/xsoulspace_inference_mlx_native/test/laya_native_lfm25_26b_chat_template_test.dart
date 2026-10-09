import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart';

/// The LFM2.5-2.6B chat-template gate (ADR 0058 2.6B row): the 1.2B hand
/// renderer with `generationThinkOpen: true` must reproduce the 2.6B
/// checkpoint's reference `apply_chat_template` output byte-for-byte on
/// every recorded case (venv-recorded fixtures — provenance in the file).
void main() {
  final fixtureFile = File(
    'native/mlx_native/testdata/lfm25_26b_chat_template_fixtures.json',
  );
  test('2.6B renderer reproduces the reference renders byte-exactly', () {
    if (!fixtureFile.existsSync()) {
      return markTestSkipped('lfm25 2.6B chat template fixtures absent');
    }
    final fixture =
        jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
    for (final raw in fixture['cases'] as List) {
      final c = raw as Map<String, dynamic>;
      final messages = <Lfm2ChatMessage>[
        for (final m in c['messages'] as List)
          Lfm2ChatMessage(
            role: (m as Map)['role'] as String,
            content: m['content'] as String,
          ),
      ];
      final tools = c['tools'] is List && (c['tools'] as List).isNotEmpty
          ? (c['tools'] as List).toList()
          : null;
      final rendered = renderLfm2ChatPrompt(
        messages: messages,
        tools: tools,
        // The render omits the BOS: the native text path prepends it.
        includeBos: false,
        variant: Lfm2ChatTemplateVariant.lfm25_26b,
      );
      // The reference render INCLUDES the BOS; the native gate compares
      // against the render minus it.
      final want = (c['rendered'] as String).replaceFirst(
        '<|startoftext|>',
        '',
      );
      expect(
        rendered,
        want,
        reason: 'case ${c['id']} diverged from the 2.6B reference render',
      );
    }
  });
}
