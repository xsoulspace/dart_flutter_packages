import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

void main() {
  final registry = ToolRegistry()
    ..register(
      const ToolDefinition().toDef(
        name: const ToolName('write'),
        execute: (final _) async => null,
      ),
    );
  test('declared thought regions exclude calls and preserve answer spans', () {
    const thought =
        '<think><tool_call>{"name":"unknown",'
        '"arguments":{}}</tool_call></think>';
    final answer = ToolCallSyntax.qwenJson.renderCall(
      const ToolCall(
        name: ToolName('write'),
        arguments: {'code': '<think>source</think>'},
      ),
    );
    final result = ToolCallSyntax.qwenJson.parse(
      '$thought$answer',
      registry: registry,
      requireRegistry: true,
    );
    expect(result.success, isTrue);
    expect(result.calls, hasLength(1));
    expect(result.nodes.first.kind, ToolSyntaxKind.thought);
    expect(result.nodes.last.start, thought.length);
    expect(result.calls.single.arguments['code'], '<think>source</think>');
    expect(
      ToolCallSyntax.qwenJson.parse('$answer<think>unfinished').calls,
      isEmpty,
    );
    expect(
      ToolCallSyntax.qwenJson.parse('$answer<think>unfinished').errorCode,
      'tool_thinking_truncated',
    );
    expect(
      ToolCallSyntax.qwenJson.parse('<think><think>x</think>').errorCode,
      'tool_thinking_ambiguous',
    );
  });
  test('Qwen composition preserves nested source and exact source span', () {
    const call = ToolCall(
      name: ToolName('write'),
      arguments: {
        'code': 'if (a > b) { print("</tool_call>"); }',
        'nested': {
          'list': [true, null, 3],
        },
      },
    );
    final encoded = ToolCallSyntax.qwenJson.renderCall(call);
    final parsed = ToolCallSyntax.qwenJson.parse(
      'α\n$encoded\nend',
      registry: registry,
      requireRegistry: true,
    );
    expect(parsed.success, isTrue);
    expect(parsed.calls.single.arguments, call.arguments);
    expect(parsed.nodes.single.start, 2);
    expect(parsed.nodes.single.end, 2 + encoded.length);
    expect(parsed.nodes.single.raw, encoded);
  });
  test('legacy tree keeps definition and result and multiline calls', () {
    final result = ToolCallSyntax.legacyTags.parse(
      '<getDefinition|write><call|write|{\n"code":"> } <call|x>"}> '
      '<result|write|{"ok":true}>',
    );
    expect(result.success, isTrue);
    expect(result.nodes.map((final n) => n.kind), [
      ToolSyntaxKind.definition,
      ToolSyntaxKind.call,
      ToolSyntaxKind.result,
    ]);
    expect(result.calls.single.arguments['code'], '> } <call|x>');
  });
  test('atomic malformed/truncated calls and authority refusals', () {
    for (final entry in {
      '<tool_call>{"name":"write","arguments":': 'tool_call_truncated',
      '<tool_call>{bad}</tool_call>': 'tool_call_malformed',
      '<tool_call>{"name":"write","name":"other",'
              '"arguments":{}}</tool_call>':
          'tool_call_ambiguous',
      '<tool_call>{"name":"write","arguments":'
              r'{"nested":{"a":1,"\u0061":2}}}</tool_call>':
          'tool_call_ambiguous',
      '<tool_call>{"name":"other","arguments":{}}</tool_call>':
          'tool_call_unknown',
      '```xml\n<tool_call>{"name":"write","arguments":{}}</tool_call>\n```':
          'tool_call_ambiguous',
      '`<tool_call>{"name":"write","arguments":{}}</tool_call>`':
          'tool_call_ambiguous',
    }.entries) {
      final first = ToolCallSyntax.qwenJson.renderCall(
        const ToolCall(name: ToolName('write'), arguments: {}),
      );
      final parsed = ToolCallSyntax.qwenJson.parse(
        '$first'
        '${entry.key}',
        registry: registry,
      );
      expect(parsed.errorCode, entry.value);
      expect(parsed.calls, isEmpty);
    }
    expect(
      ToolCallSyntax.qwenJson
          .parse(
            '<tool_call>{"name":"write","arguments":{}}</tool_call>',
            requireRegistry: true,
          )
          .errorCode,
      'tool_call_unbound',
    );
  });
  test('source fences inside JSON do not fence subsequent actions', () {
    final first = ToolCallSyntax.qwenJson.renderCall(
      const ToolCall(
        name: ToolName('write'),
        arguments: {'source': '``` dart'},
      ),
    );
    final second = ToolCallSyntax.qwenJson.renderCall(
      const ToolCall(name: ToolName('write'), arguments: {'source': 'next'}),
    );
    expect(ToolCallSyntax.qwenJson.parse('$first$second').calls, hasLength(2));
  });
  test('Qwen orphan closers are atomic diagnostic refusals', () {
    const orphan = '{"name":"write","arguments":{}}</tool_call>';
    final valid = ToolCallSyntax.qwenJson.renderCall(
      const ToolCall(name: ToolName('write'), arguments: {}),
    );
    for (final prefix in ['', valid]) {
      final parsed = ToolCallSyntax.qwenJson.parse('$prefix$orphan');
      expect(parsed.success, isFalse);
      expect(parsed.errorCode, 'tool_call_malformed');
      expect(
        parsed.errorOffset,
        prefix.length + orphan.indexOf('</tool_call>'),
      );
      expect(parsed.calls, isEmpty);
    }
    expect(
      ToolCallSyntax.qwenJson.parse('</think>').errorCode,
      'tool_thinking_ambiguous',
    );
    expect(
      ToolCallSyntax.qwenJson.parse('<think>$orphan</think>').success,
      isTrue,
    );
    expect(
      ToolCallSyntax.qwenJson.parse('`</tool_call>`').errorCode,
      'tool_call_ambiguous',
    );
    // Bare JSON remains text; no permissive syntax fallback is introduced.
    expect(ToolCallSyntax.qwenJson.parse('{"name":"write"}').calls, isEmpty);
    expect(ToolCallSyntax.legacyTags.parse('a > b').success, isTrue);
  });
  test('explicit profile selection and configurable bounds', () {
    final text = ToolCallSyntax.qwenJson.renderCall(
      const ToolCall(
        name: ToolName('write'),
        arguments: {
          'a': {'b': 1},
        },
      ),
    );
    expect(ToolCallSyntax.legacyTags.parse(text).calls, isEmpty);
    expect(
      ToolCallSyntax.qwenJson
          .parse(text, limits: const ToolSyntaxLimits(maxDepth: 1))
          .errorCode,
      'tool_syntax_limit',
    );
    expect(
      ToolCallSyntax.qwenJson
          .parse(text, limits: const ToolSyntaxLimits(maxBytes: 3))
          .errorCode,
      'tool_syntax_limit',
    );
    expect(
      ToolCallSyntax.qwenJson
          .parse('$text$text', limits: const ToolSyntaxLimits(maxNodes: 1))
          .errorCode,
      'tool_syntax_limit',
    );
    const custom = ToolCallSyntax(
      id: 'custom',
      envelopes: [
        ToolSyntaxEnvelope.jsonCall(
          open: '[action]',
          close: '[/action]',
          nameKey: 'function',
          argumentsKey: 'parameters',
        ),
      ],
    );
    expect(
      custom
          .parse(
            custom.renderCall(
              const ToolCall(name: ToolName('write'), arguments: {}),
            ),
          )
          .calls
          .single
          .name,
      const ToolName('write'),
    );
  });
}
