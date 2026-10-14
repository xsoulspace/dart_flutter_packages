import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_mlx_native/src/native_text_protocol.dart';
import 'package:xsoulspace_inference_mlx_native/src/laya_native_qwen_chat_template.dart';

void main() {
  test(
    'native function parameters use standard schema and preserve requirements',
    () {
      final registry = ToolRegistry()
        ..register(
          ToolDef.encode(
            name: const ToolName('choose'),
            description: 'Choose a supported action',
            argsSchema: SchemaBundle(
              root: FM.object(
                'choose',
                properties: () => [
                  FM.prop(
                    'action',
                    FM.enum_('action', ['read', 'request_more']),
                  ),
                  FM.prop('note', FM.string(), optional: true),
                ],
              ),
            ),
            execute: (_) async => null,
          ),
        );
      final tool = nativeTextFunctionTools(registry).single;
      expect(tool['type'], 'function');
      final function = tool['function']! as Map;
      expect(function['name'], 'choose');
      final parameters = function['parameters']! as Map;
      expect(parameters['type'], 'object');
      expect(parameters['required'], ['action']);
      expect(parameters['additionalProperties'], false);
      expect((parameters['properties'] as Map)['action'], {
        'type': 'string',
        'enum': ['read', 'request_more'],
      });
      expect(parameters.containsKey('root'), false);
      expect(
        registry.getToolsJsons().single['parameters'],
        contains('root'),
        reason: 'the internal host contract remains unchanged',
      );
    },
  );
  test(
    'decoded presentation excludes profile spans and preserves prose/source',
    () {
      final registry = ToolRegistry()
        ..register(
          const ToolDefinition().toDef(
            name: const ToolName('read'),
            execute: (_) async => null,
          ),
        );
      const envelope = '<tool_call>{"name":"read","arguments":{}}</tool_call>';
      const raw = 'Before<think>private reasoning</think>$envelope After';
      final result = normalizeNativeTextCalls(
        text: raw,
        syntax: ToolCallSyntax.qwenJson,
        registry: registry,
      );
      expect(result.success, isTrue);
      expect(result.data!.presentationText, 'Before After');
      expect(result.data!.calls.single.name, const ToolName('read'));
      expect(result.data!.sources.single['raw'], envelope);
      final prefilled = normalizeNativeTextCalls(
        text: 'Private prefill</think>$envelope Answer',
        syntax: ToolCallSyntax.qwenJson,
        registry: registry,
        thinkingPrefilled: true,
      );
      expect(prefilled.data!.presentationText, ' Answer');
      final plain = normalizeNativeTextCalls(
        text: '[reference](https://example.com) [1, 2, 3]',
        syntax: ToolCallSyntax.qwenJson,
        registry: registry,
      );
      expect(
        plain.data!.presentationText,
        '[reference](https://example.com) [1, 2, 3]',
      );
    },
  );

  test(
    'normalization refusal retains actual supplied usage and raw diagnostics',
    () {
      final registry = ToolRegistry()
        ..register(
          const ToolDefinition().toDef(
            name: const ToolName('read'),
            execute: (_) async => null,
          ),
        );
      const raw =
          '<tool_call>{"name":"read","arguments":{}}</tool_call>'
          '<tool_call>{"name":"read","arguments":';
      final normalized = normalizeNativeTextCalls(
        text: raw,
        syntax: ToolCallSyntax.qwenJson,
        registry: registry,
      );
      expect(normalized.success, isFalse);
      expect(
        normalized.data,
        isNull,
        reason: 'Earlier parsed calls are never partially admitted',
      );
      final refused = nativeTextNormalizationRefusal(
        normalized: normalized,
        rawOutput: raw,
        promptTokens: 731,
        completionTokens: 83,
      );
      expect(refused.success, isFalse);
      expect(refused.data, isNull);
      expect(refused.error!.code, normalized.error!.code);
      expect(refused.error!.message, normalized.error!.message);
      final details = refused.error!.details! as Map;
      expect(details['protocol_error'], normalized.error!.details);
      expect(details['raw_output'], raw);
      expect(details['usage'], {'prompt_tokens': 731, 'completion_tokens': 83});
      expect(
        () => nativeTextNormalizationRefusal(
          normalized: InferenceResult.ok(const NativeTextToolOutput()),
          rawOutput: '',
          promptTokens: 0,
          completionTokens: 0,
        ),
        throwsArgumentError,
      );
    },
  );
  test('provider-declared prefilled thoughts never admit embedded calls', () {
    final registry = ToolRegistry()
      ..register(
        const ToolDefinition().toDef(
          name: const ToolName('read'),
          execute: (final _) async => null,
        ),
      );
    const thought =
        'Reasoning <tool_call>{"name":"ungranted",'
        '"arguments":{}}</tool_call></think>';
    const answer = '<tool_call>{"name":"read","arguments":{}}</tool_call>';
    final result = normalizeNativeTextCalls(
      text: '$thought$answer',
      syntax: ToolCallSyntax.qwenJson,
      registry: registry,
      thinkingPrefilled: true,
    );
    expect(result.success, isTrue);
    expect(result.data!.calls.single.name, const ToolName('read'));
    expect(result.data!.sources.single['start'], thought.length);
    expect(
      normalizeNativeTextCalls(
        text: answer,
        syntax: ToolCallSyntax.qwenJson,
        registry: registry,
        thinkingPrefilled: true,
      ).error!.code,
      'tool_thinking_truncated',
    );
  });
  test('call result next-call cycle uses only projected actor context', () async {
    var executed = 0;
    final registry = ToolRegistry()
      ..register(
        const ToolDefinition().toDef(
          name: const ToolName('read'),
          execute: (final _) async {
            executed++;
            return '{"revision":7}';
          },
        ),
      );
    final first = normalizeNativeTextCalls(
      text:
          '<think>private reasoning</think>'
          '<tool_call>{"name":"read","arguments":{"path":"a.dart"}}</tool_call>',
      syntax: ToolCallSyntax.qwenJson,
      registry: registry,
    );
    expect(first.success, isTrue);
    expect(
      first.data!.sources.single['start'],
      '<think>private reasoning</think>'.length,
    );
    expect(first.data!.sources.single['raw'], contains('a.dart'));
    expect(executed, 0, reason: 'normalization never executes');
    final call = first.data!.calls.single;
    final output = await registry.execute(call.name, call.arguments);
    final request = InferenceRequest(
      prompt: 'Choose next action',
      systemPrompt: 'Actor A only',
      contextFragments: [
        'asst:<tool_call>{"name":"read","arguments":{"path":"a.dart"}}</tool_call>',
        'tool:read $output',
        'absence:other actors off screen',
      ],
    );
    final messages = nativeTextMessages(request);
    final rendered = renderQwenChatPrompt(
      messages: [
        for (final message in messages)
          QwenChatMessage(role: message.role.name, content: message.content),
      ],
      tools: registry.getToolsJsons(),
      enableThinking: false,
    );
    expect(rendered, contains('revision'));
    expect(rendered, contains('Actor A only'));
    expect(rendered, contains('Choose next action'));
    final next = normalizeNativeTextCalls(
      text:
          '<tool_call>{"name":"read","arguments":{"path":"b.dart"}}</tool_call>',
      syntax: ToolCallSyntax.qwenJson,
      registry: registry,
    );
    expect(next.data!.calls.single.arguments['path'], 'b.dart');
    expect(executed, 1);
  });
  test(
    'explicit message compatibility and unclosed thinking are preserved',
    () {
      final messages = nativeTextMessages(
        InferenceRequest(
          prompt: 'ignored',
          contextFragments: ['hidden from explicit transcript'],
          messages: const [
            ChatMessage.system('explicit'),
            ChatMessage.tool('result'),
          ],
        ),
      );
      expect(messages.map((final m) => m.content), ['explicit', 'result']);
      expect(
        normalizeNativeTextCalls(
          text: '<think><tool_call>{}',
          syntax: ToolCallSyntax.qwenJson,
          registry: null,
        ).error!.code,
        'tool_thinking_truncated',
      );
      expect(
        normalizeNativeTextCalls(
          text: '<|tool_call_start|>[x()]<|tool_call_end|>',
          syntax: null,
          registry: null,
        ).error!.code,
        'tool_syntax_unsupported',
      );
    },
  );
}
