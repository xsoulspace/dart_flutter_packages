import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

void main() {
  final registry = ToolRegistry()
    ..register(
      const ToolDefinition().toDef(
        name: const ToolName('write'),
        execute: (_) async => null,
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
    expect(result.nodes.map((n) => n.kind), [
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

  group('the LFM native signature profile (qualified 2026-10-28)', () {
    final lfmRegistry = ToolRegistry()
      ..register(
        const ToolDefinition().toDef(
          name: const ToolName('get_weather'),
          execute: (_) async => null,
        ),
      )
      ..register(
        const ToolDefinition().toDef(
          name: const ToolName('write'),
          execute: (_) async => null,
        ),
      );

    ToolSyntaxParseResult parse(String text) => ToolCallSyntax.lfmNative.parse(
      text,
      registry: lfmRegistry,
      requireRegistry: true,
    );

    test('the measured checkpoint shape: [name(key="value")] span', () {
      // Live-measured 2026-10-28, LFM2.5-1.2B on the function-tool surface:
      // <|tool_call_start|>[get_weather(city="Tokyo")]<|tool_call_end|>
      final result = parse(
        '<|tool_call_start|>[get_weather(city="Tokyo")]<|tool_call_end|>',
      );
      expect(result.success, isTrue);
      final call = result.calls.single;
      expect(call.name.value, 'get_weather');
      expect(call.arguments, {'city': 'Tokyo'});
    });

    test('escapes, numbers, booleans and None decode to Dart values', () {
      final result = parse(
        '<|tool_call_start|>[write(path="a\\nb.txt", lines=3, rate=0.5, '
        'verbose=True, tail=None)]<|tool_call_end|>',
      );
      expect(result.success, isTrue);
      final call = result.calls.single;
      expect(call.name.value, 'write');
      expect(call.arguments['path'], 'a\nb.txt');
      expect(call.arguments['lines'], 3);
      expect(call.arguments['rate'], 0.5);
      expect(call.arguments['verbose'], isTrue);
      expect(call.arguments['tail'], isNull);
    });

    test('top-level comma segments are separate calls', () {
      final result = parse(
        '<|tool_call_start|>[get_weather(city="Tokyo"), write(path="x")]'
        '<|tool_call_end|>',
      );
      expect(result.success, isTrue);
      expect(result.calls, hasLength(2));
      expect(result.calls[0].name.value, 'get_weather');
      expect(result.calls[1].name.value, 'write');
    });

    test('the JSON list spelling of the same checkpoint family admits', () {
      final result = parse(
        '<|tool_call_start|>[{"name": "write", "arguments": '
        '{"path": "a"}}]<|tool_call_end|>',
      );
      expect(result.success, isTrue);
      expect(result.calls.single.name.value, 'write');
      expect(result.calls.single.arguments, {'path': 'a'});
    });

    test('prose stays zero calls; surrounding text is presentation', () {
      final result = parse(
        'Let me check. <|tool_call_start|>'
        '[get_weather(city="Tokyo")]<|tool_call_end|>',
      );
      expect(result.success, isTrue);
      expect(result.calls, hasLength(1));
    });

    test('an unknown tool refuses by name, never executes', () {
      expect(
        parse(
          '<|tool_call_start|>[get_weather(city="Tokyo")]'
          '<|tool_call_end|><|tool_call_start|>[rm(rf="/")]'
          '<|tool_call_end|>',
        ).errorCode,
        'tool_call_unknown',
      );
    });

    test('a truncated envelope (budget cap) refuses atomically', () {
      expect(
        parse('<|tool_call_start|>[get_weather(city="Tok').errorCode,
        'tool_call_truncated',
      );
    });

    test('a bare close without an open admits nothing and stays prose', () {
      final result = parse('<|tool_call_end|> nothing was opened');
      expect(result.success, isTrue);
      expect(result.calls, isEmpty);
    });

    test('the measured repetition artifact yields one call', () {
      // Live-measured 2026-10-28: the checkpoint repeats a completed call
      // as a bare trailing duplicate. The matched envelope supplies the
      // call; the repetition stays in the presentation text.
      final result = parse(
        '<|tool_call_start|>[get_weather(city="Tokyo")]<|tool_call_end|>'
        '[get_weather(city="Tokyo")]<|tool_call_end|>',
      );
      expect(result.success, isTrue);
      expect(result.calls, hasLength(1));
      expect(result.calls.single.name.value, 'get_weather');
    });

    test('an unqualified value shape refuses instead of guessing', () {
      expect(
        parse('<|tool_call_start|>[get_weather(city=Tokyo)]<|tool_call_end|>')
            .errorCode,
        'tool_call_malformed',
      );
    });

    test('duplicate keys in one call refuse as ambiguous', () {
      expect(
        parse(
          '<|tool_call_start|>[write(path="a", path="b")]'
          '<|tool_call_end|>',
        ).errorCode,
        'tool_call_ambiguous',
      );
    });

    test('renderCall round-trips the signature form', () {
      const call = ToolCall(
        name: ToolName('get_weather'),
        arguments: {'city': 'Tokyo'},
      );
      final rendered = ToolCallSyntax.lfmNative.renderCall(call);
      final result = parse(rendered);
      expect(result.success, isTrue);
      expect(result.calls.single.name.value, 'get_weather');
      expect(result.calls.single.arguments, {'city': 'Tokyo'});
    });
  });
}
