import 'dart:async';
import 'dart:convert';
import 'package:dart_acp_toolkit/dart_acp_toolkit.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_acp/xsoulspace_inference_acp.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

class Wire implements StringSink {
  Wire({this.onTransportDispose});
  final Future<void> Function()? onTransportDispose;
  final output = StreamController<List<int>>();
  final methods = <Map<String, dynamic>>[];
  bool rejectLoad = false;
  bool holdPrompt = false;
  Map<String, dynamic>? held;
  late final client = AcpClient(
    agentOutput: output.stream,
    agentInput: this,
    onTransportDispose: onTransportDispose,
  );
  void respond(Map<String, dynamic> request, Map<String, Object?> result) {
    final response = {'jsonrpc': '2.0', 'id': request['id'], 'result': result};
    output.add(utf8.encode('${jsonEncode(response)}\n'));
  }

  @override
  void writeln([Object? value = '']) {
    final request = jsonDecode('$value') as Map<String, dynamic>;
    methods.add(request);
    switch (request['method']) {
      case 'initialize':
        respond(request, {'protocolVersion': 1});
      case 'session/new':
        respond(request, {'sessionId': 'persistent'});
      case 'session/load':
        if (rejectLoad) {
          output.add(
            utf8.encode(
              '${jsonEncode({
                'jsonrpc': '2.0',
                'id': request['id'],
                'error': {'code': -32601, 'message': 'unsupported'},
              })}\n',
            ),
          );
        } else {
          respond(request, {'sessionId': 'persistent'});
        }
      case 'session/prompt':
        if (holdPrompt) {
          held = request;
          return;
        }
        output.add(
          utf8.encode(
            '${jsonEncode({
              'jsonrpc': '2.0',
              'method': 'session/update',
              'params': {
                'sessionId': 'persistent',
                'update': {
                  'sessionUpdate': 'agent_message_chunk',
                  'content': {'type': 'text', 'text': 'answer'},
                },
              },
            })}\n',
          ),
        );
        respond(request, {'stopReason': 'end_turn'});
    }
  }

  @override
  void write(Object? value) => writeln(value);
  @override
  void writeAll(Iterable<Object?> values, [String separator = '']) =>
      write(values.join(separator));
  @override
  void writeCharCode(int value) => write(String.fromCharCode(value));
}

void main() {
  test('failed native disposal blocks another clientFactory service', () async {
    final wire = Wire(
      onTransportDispose: () =>
          Future.error(StateError('owned_transport_settlement_unknown')),
    );
    var connections = 0;
    final adapter = AcpInferenceClient(
      command: 'unused',
      conversationKey: 'owner',
      clientFactory: () async {
        connections++;
        return wire.client;
      },
    );
    expect(
      (await adapter.infer(InferenceRequest(prompt: 'first'))).success,
      isTrue,
    );
    await expectLater(adapter.dispose(), throwsStateError);
    await expectLater(
      adapter.infer(InferenceRequest(prompt: 'second')),
      throwsStateError,
    );
    expect(connections, 1);
    await expectLater(adapter.dispose(), throwsStateError);
    await wire.output.close();
  });

  for (final streaming in [false, true]) {
    test('projected cut survives ${streaming ? 'stream' : 'plain'} ACP prompt '
        'without hidden replay', () async {
      final wire = Wire();
      final adapter = AcpInferenceClient(
        command: 'unused',
        conversationKey: 'explicit-cut',
        clientFactory: () async => wire.client,
      );
      final request = InferenceRequest(
        prompt: 'current decision',
        systemPrompt: 'actor system',
        contextFragments: const [
          'visible source: exact "quoted" text',
          'absence:private is off-screen',
          'asst:earlier observed decision',
          'tool:read source=original',
        ],
      );
      if (streaming) {
        expect(
          (await (await adapter.streamStructuredText(request)).result).success,
          true,
        );
      } else {
        expect((await adapter.infer(request)).success, true);
      }
      final packet = wire.methods.lastWhere(
        (r) => r['method'] == 'session/prompt',
      );
      final blocks = (packet['params'] as Map)['prompt'] as List;
      final projected = [
        for (final block in blocks)
          jsonDecode((block as Map)['text'] as String) as Map,
      ];
      expect(projected.first, {'role': 'system', 'content': 'actor system'});
      expect(projected.last, {'role': 'user', 'content': 'current decision'});
      expect(
        projected.any(
          (m) =>
              m['role'] == 'assistant' &&
              m['content'] == 'earlier observed decision',
        ),
        true,
      );
      final all = projected.map((m) => m['content']).join('\n');
      expect(all, contains('visible source: exact "quoted" text'));
      expect(all, contains('absence:private is off-screen'));
      expect(all, contains('Tool results observed so far:'));
      expect(all, contains('read source=original'));
      final next = InferenceRequest(prompt: 'next only');
      if (streaming) {
        await (await adapter.streamStructuredText(next)).result;
      } else {
        await adapter.infer(next);
      }
      final nextPacket = wire.methods.lastWhere(
        (r) => r['method'] == 'session/prompt',
      );
      final nextBlocks = (nextPacket['params'] as Map)['prompt'] as List;
      expect(nextBlocks, hasLength(1));
      expect(jsonDecode((nextBlocks.single as Map)['text'] as String), {
        'role': 'user',
        'content': 'next only',
      });
      await adapter.dispose();
      await wire.output.close();
    });
    test('explicit messages override synthetic cut in '
        '${streaming ? 'stream' : 'plain'} ACP', () async {
      final wire = Wire();
      final adapter = AcpInferenceClient(
        command: 'unused',
        clientFactory: () async => wire.client,
      );
      final request = InferenceRequest(
        prompt: 'excluded prompt',
        systemPrompt: 'excluded system',
        contextFragments: const ['excluded fragment'],
        messages: const [
          ChatMessage.system('native owner text'),
          ChatMessage.tool('exact tool result'),
          ChatMessage.assistant('acknowledged source'),
          ChatMessage.user('current explicit'),
        ],
      );
      if (streaming) {
        await (await adapter.streamStructuredText(request)).result;
      } else {
        await adapter.infer(request);
      }
      final packet = wire.methods.lastWhere(
        (r) => r['method'] == 'session/prompt',
      );
      final blocks = (packet['params'] as Map)['prompt'] as List;
      final messages = [
        for (final block in blocks)
          jsonDecode((block as Map)['text'] as String),
      ];
      expect(messages, [
        {'role': 'system', 'content': 'native owner text'},
        {'role': 'tool', 'content': 'exact tool result'},
        {'role': 'assistant', 'content': 'acknowledged source'},
        {'role': 'user', 'content': 'current explicit'},
      ]);
      expect(jsonEncode(messages), isNot(contains('excluded')));
      await adapter.dispose();
      await wire.output.close();
    });
  }

  test('new adapter resumes owner-persisted reference without fork', () async {
    AcpSessionReference? saved;
    final persistence = AcpSessionPersistence(
      read: (_) async => saved,
      save: (reference) async => saved = reference,
      authorize: (_, _) async => true,
    );
    final first = Wire();
    final initial = AcpInferenceClient(
      command: 'unused',
      conversationKey: 'durable-actor',
      providerIdentity: 'registered-agent/revision-1',
      sessionPersistence: persistence,
      clientFactory: () async => first.client,
    );
    final scoped = InferenceRequest(
      prompt: 'work',
      workingDirectory: '/candidate',
    );
    expect((await initial.infer(scoped)).success, true);
    expect(saved?.sessionId, 'persistent');
    await initial.dispose();
    await first.output.close();
    final second = Wire();
    final resumed = AcpInferenceClient(
      command: 'unused',
      conversationKey: 'durable-actor',
      providerIdentity: 'registered-agent/revision-1',
      sessionPersistence: persistence,
      clientFactory: () async => second.client,
    );
    expect((await resumed.infer(scoped)).success, true);
    expect(
      second.methods.where((r) => r['method'] == 'session/load'),
      hasLength(1),
    );
    expect(second.methods.where((r) => r['method'] == 'session/new'), isEmpty);
    await resumed.dispose();
    await second.output.close();
  });

  test('revoked current grant refuses cached conversation prompt', () async {
    var allowed = true;
    final wire = Wire();
    final adapter = AcpInferenceClient(
      command: 'unused',
      conversationKey: 'actor',
      providerIdentity: 'registered',
      clientFactory: () async => wire.client,
      sessionPersistence: AcpSessionPersistence(
        read: (_) async => null,
        save: (_) async {},
        authorize: (_, _) async => allowed,
      ),
    );
    final scoped = InferenceRequest(
      prompt: 'work',
      workingDirectory: '/candidate',
    );
    expect((await adapter.infer(scoped)).success, true);
    allowed = false;
    expect(
      (await adapter.infer(scoped)).error?.code,
      'acp_session_grant_refused',
    );
    expect(
      wire.methods.where((r) => r['method'] == 'session/prompt'),
      hasLength(1),
    );
    await adapter.dispose();
    await wire.output.close();
  });

  test('stored provider mismatch refuses rather than forking', () async {
    final wire = Wire();
    final adapter = AcpInferenceClient(
      command: 'unused',
      conversationKey: 'actor',
      providerIdentity: 'new-provider',
      clientFactory: () async => wire.client,
      sessionPersistence: AcpSessionPersistence(
        read: (scope) async => AcpSessionReference(
          binding: AcpSessionBinding(
            conversationKey: scope.conversationKey,
            workingDirectory: scope.workingDirectory,
            providerIdentity: 'old-provider',
            descriptorRevision: scope.descriptorRevision,
          ),
          sessionId: 'old',
        ),
        save: (_) async {},
        authorize: (_, _) async => true,
      ),
    );
    final result = await adapter.infer(
      InferenceRequest(prompt: 'work', workingDirectory: '/candidate'),
    );
    expect(result.error?.code, 'acp_stored_session_binding_changed');
    expect(
      wire.methods.where((r) => '${r['method']}'.startsWith('session/')),
      isEmpty,
    );
    await adapter.dispose();
    await wire.output.close();
  });

  test('failed save retries the same acknowledged reference', () async {
    final first = Wire();
    final second = Wire();
    var connects = 0;
    var failSave = true;
    AcpSessionReference? saved;
    final adapter = AcpInferenceClient(
      command: 'unused',
      conversationKey: 'actor',
      providerIdentity: 'registered',
      clientFactory: () async => connects++ == 0 ? first.client : second.client,
      sessionPersistence: AcpSessionPersistence(
        read: (_) async => saved,
        save: (reference) async {
          if (failSave) throw StateError('store unavailable');
          saved = reference;
        },
        authorize: (_, _) async => true,
      ),
    );
    final scoped = InferenceRequest(
      prompt: 'work',
      workingDirectory: '/candidate',
    );
    expect(
      (await adapter.infer(scoped)).error?.code,
      'acp_session_persistence_failed',
    );
    expect(
      first.methods.where((r) => r['method'] == 'session/prompt'),
      isEmpty,
    );
    failSave = false;
    expect((await adapter.infer(scoped)).success, true);
    expect(second.methods.where((r) => r['method'] == 'session/new'), isEmpty);
    expect(
      second.methods.where((r) => r['method'] == 'session/load'),
      hasLength(1),
    );
    expect(saved?.sessionId, 'persistent');
    await adapter.dispose();
    await first.output.close();
    await second.output.close();
  });

  test(
    'concurrent turns share initialized connection and refuse overlap',
    () async {
      final wire = Wire()..holdPrompt = true;
      var connections = 0;
      final adapter = AcpInferenceClient(
        command: 'unused',
        conversationKey: 'actor',
        clientFactory: () async {
          connections++;
          return wire.client;
        },
      );
      final request = InferenceRequest(prompt: 'work');
      final first = adapter.infer(request);
      final second = adapter.infer(request);
      final busy = await second;
      expect(busy.error?.code, 'acp_session_busy');
      expect(connections, 1);
      expect(
        wire.methods.where((row) => row['method'] == 'session/new'),
        hasLength(1),
      );
      wire.respond(wire.held!, {'stopReason': 'end_turn'});
      expect((await first).success, isTrue);
      await adapter.dispose();
      await wire.output.close();
    },
  );

  test('unbound tool registry refuses before connecting', () async {
    var connects = 0;
    final registry = ToolRegistry()
      ..register(
        ToolDef(
          name: const ToolName('owned_tool'),
          description: 'owned',
          execute: (_) => Future.value('unused'),
        ),
      );
    final adapter = AcpInferenceClient(
      command: 'unused',
      clientFactory: () {
        connects++;
        throw StateError('must not connect');
      },
    );
    final result = await adapter.infer(
      InferenceRequest(prompt: 'work'),
      toolRegistry: registry,
    );
    expect(result.error?.code, 'acp_tool_registry_unbound');
    expect(connects, 0);
  });
  test(
    'installed MCP descriptors route without copying tool catalog',
    () async {
      final wire = Wire();
      final registry = ToolRegistry()
        ..register(
          ToolDef(
            name: const ToolName('owned_tool'),
            description: 'owned',
            execute: (_) => Future.value('unused'),
          ),
        );
      const descriptor = {
        'name': 'owned-host',
        'type': 'http',
        'url': 'http://127.0.0.1:12345/mcp',
        'headers': <Object>[],
      };
      final adapter = AcpInferenceClient(
        command: 'unused',
        conversationKey: 'actor',
        clientFactory: () async => wire.client,
        boundMcpServers: (bound) {
          expect(identical(bound, registry), isTrue);
          return [descriptor];
        },
      );
      expect(
        (await adapter.infer(
          InferenceRequest(prompt: 'work'),
          toolRegistry: registry,
        )).success,
        isTrue,
      );
      final session = wire.methods.singleWhere(
        (row) => row['method'] == 'session/new',
      );
      expect((session['params'] as Map)['mcpServers'], [descriptor]);
      expect(jsonEncode(session), isNot(contains('owned_tool')));
      await adapter.dispose();
      await wire.output.close();
    },
  );
  test('stream cancellation forwards session and discards late text', () async {
    final wire = Wire()..holdPrompt = true;
    final adapter = AcpInferenceClient(
      command: 'unused',
      conversationKey: 'actor',
      clientFactory: () async => wire.client,
    );
    final stream = await adapter.streamStructuredText(
      InferenceRequest(prompt: 'work'),
    );
    while (wire.held == null) {
      await Future<void>.delayed(Duration.zero);
    }
    await stream.cancel();
    wire.respond(wire.held!, {'stopReason': 'end_turn'});
    expect((await stream.result).success, isFalse);
    expect(
      wire.methods.where((row) => row['method'] == 'session/cancel'),
      hasLength(1),
    );
    await stream.dispose();
    await adapter.dispose();
    await wire.output.close();
  });

  final request = InferenceRequest(
    prompt: 'continue',
    workingDirectory: '/candidate',
  );
  test('explicit conversation retains session and captures text', () async {
    final wire = Wire();
    final adapter = AcpInferenceClient(
      command: 'unused',
      conversationKey: 'actor-conversation',
      clientFactory: () async => wire.client,
    );
    final first = await adapter.infer(request);
    final second = await adapter.infer(request);
    expect(first.success, isTrue);
    expect(second.success, isTrue);
    expect(
      wire.methods.where((row) => row['method'] == 'session/new'),
      hasLength(1),
    );
    await adapter.dispose();
    await wire.output.close();
  });
  test(
    'reconnect loads the prior conversation without replay or fork',
    () async {
      final first = Wire();
      final second = Wire();
      var connections = 0;
      final adapter = AcpInferenceClient(
        command: 'unused',
        conversationKey: 'actor',
        clientFactory: () async =>
            connections++ == 0 ? first.client : second.client,
      );
      await adapter.infer(request);
      await first.output.close();
      await Future<void>.delayed(Duration.zero);
      final result = await adapter.infer(request);
      expect(result.success, isTrue);
      expect(
        second.methods.where((row) => row['method'] == 'session/load'),
        hasLength(1),
      );
      expect(
        second.methods.where((row) => row['method'] == 'session/new'),
        isEmpty,
      );
      expect(
        second.methods.where((row) => row['method'] == 'session/prompt'),
        hasLength(1),
      );
      await adapter.dispose();
      await second.output.close();
    },
  );
  test(
    'unsupported resume refuses without new session or prompt replay',
    () async {
      final first = Wire();
      final second = Wire()..rejectLoad = true;
      var connections = 0;
      final adapter = AcpInferenceClient(
        command: 'unused',
        conversationKey: 'actor',
        clientFactory: () async =>
            connections++ == 0 ? first.client : second.client,
      );
      await adapter.infer(request);
      await first.output.close();
      await Future<void>.delayed(Duration.zero);
      expect((await adapter.infer(request)).success, isFalse);
      expect(
        second.methods.where(
          (row) =>
              row['method'] == 'session/new' ||
              row['method'] == 'session/prompt',
        ),
        isEmpty,
      );
      await adapter.dispose();
      await second.output.close();
    },
  );
  test('cancellation reaches ACP and discards late completion', () async {
    final wire = Wire()..holdPrompt = true;
    final adapter = AcpInferenceClient(
      command: 'unused',
      conversationKey: 'actor',
      clientFactory: () async => wire.client,
    );
    final pending = adapter.infer(request);
    while (wire.held == null) {
      await Future<void>.delayed(Duration.zero);
    }
    adapter.cancelActive();
    wire.respond(wire.held!, {'stopReason': 'end_turn'});
    expect((await pending).success, isFalse);
    expect(
      wire.methods.where((row) => row['method'] == 'session/cancel'),
      hasLength(1),
    );
    await adapter.dispose();
    await wire.output.close();
  });
}
