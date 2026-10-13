import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_acp/xsoulspace_inference_acp.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'acp_inference_client_test.dart' show Wire;

class RebindWire extends Wire {
  String loadId = 'persistent';
  bool holdLoad = false;
  Map<String, dynamic>? pendingLoad;
  final events = <String>[];
  @override
  void writeln([Object? value = '']) {
    final packet = jsonDecode('$value') as Map<String, dynamic>;
    events.add('${packet['method']}');
    if (packet['method'] == 'session/load' && !rejectLoad) {
      methods.add(packet);
      if (holdLoad) {
        pendingLoad = packet;
      } else {
        respond(packet, {'sessionId': loadId});
      }
      return;
    }
    super.writeln(value);
  }
}

class Fixture {
  Fixture({bool installPort = true}) {
    adapter = AcpInferenceClient(
      command: 'unused',
      conversationKey: 'conversation',
      providerIdentity: 'provider',
      clientFactory: () async => wires[connections++].client,
      boundMcpServers: (_) => [
        {'name': 'owner', 'type': 'http', 'url': descriptor},
      ],
      sessionPersistence: AcpSessionPersistence(
        read: (_) async => stored,
        save: (reference) async {
          saves++;
          stored = reference;
        },
        acknowledge: (reference) async {
          acknowledgements.add(reference);
          events.add('ack');
        },
        authorize: (binding, previous) async {
          // Normal strict grant receives only null or a matching new ACK.
          expect(previous == null || previous.binding.matches(binding), true);
          return grant;
        },
        rebind: installPort
            ? AcpSessionRebindPort(
                stage: (previous, next) async {
                  stages++;
                  events.add('stage');
                  stagedPrevious = previous;
                  if (stageGate != null) await stageGate!.future;
                  return ticket;
                },
                authorize: (issued, previous, next) async {
                  expect(identical(issued, ticket), true);
                  expect(identical(previous, stagedPrevious), true);
                  checks++;
                  return transitionGrant;
                },
                commit: (issued, previous, acknowledged) async {
                  commits++;
                  events.add('commit');
                  expect(identical(issued, ticket), true);
                  expect(acknowledged.sessionId, previous.sessionId);
                  expect(stored!.binding.matches(previous.binding), true);
                  if (failCommit) throw StateError('CAS failed');
                  stored = acknowledged;
                  return true;
                },
              )
            : null,
      ),
    );
  }
  late AcpInferenceClient adapter;
  final wires = [RebindWire(), RebindWire(), RebindWire()];
  final ticket = Object();
  final events = <String>[];
  final acknowledgements = <AcpSessionReference>[];
  final registry = ToolRegistry()
    ..register(
      ToolDef(
        name: const ToolName('owned'),
        description: 'owned',
        execute: (_) async => 'unused',
      ),
    );
  final request = InferenceRequest(
    prompt: 'current',
    workingDirectory: '/canonical-candidate',
  );
  AcpSessionReference? stored;
  AcpSessionReference? stagedPrevious;
  String descriptor = 'http://127.0.0.1:1234/mcp';
  bool grant = true;
  bool transitionGrant = true;
  bool failCommit = false;
  Completer<void>? stageGate;
  int connections = 0;
  int stages = 0;
  int checks = 0;
  int commits = 0;
  int saves = 0;
  Future<InferenceResult<InferenceResponse>> infer() =>
      adapter.infer(request, toolRegistry: registry);
  Future<void> initial({bool settle = true}) async {
    expect((await infer()).success, true);
    if (settle) await adapter.dispose();
    descriptor = 'http://127.0.0.1:5678/mcp';
  }

  Future<void> close() async {
    await adapter.dispose();
    for (var i = 0; i < wires.length; i++) {
      if (i >= connections) unawaited(wires[i].output.stream.drain<void>());
      await wires[i].output.close();
    }
  }
}

void main() {
  test('exact descriptor transition loads ACK then commits; '
      'repeated turn does not rebind', () async {
    final f = Fixture();
    addTearDown(f.close);
    await f.initial();
    final old = f.stored!;
    expect((await f.infer()).success, true);
    expect(identical(f.stagedPrevious, old), true);
    expect(f.stored!.sessionId, old.sessionId);
    expect(f.stored!.binding.matches(old.binding), false);
    expect(f.events, ['ack', 'stage', 'ack', 'commit']);
    expect(f.saves, 1);
    expect(f.checks, greaterThanOrEqualTo(6));
    expect(
      f.wires[1].methods.where((m) => m['method'] == 'session/new'),
      isEmpty,
    );
    expect(
      f.wires[1].methods.where((m) => m['method'] == 'session/load'),
      hasLength(1),
    );
    expect((await f.infer()).success, true);
    expect(f.stages, 1);
    expect(f.commits, 1);
    expect(f.acknowledgements, hasLength(2));
  });
  test('live old transport refuses rotation before staging', () async {
    final f = Fixture();
    addTearDown(f.close);
    await f.initial(settle: false);
    expect((await f.infer()).error?.code, 'acp_session_rebind_busy');
    expect(f.stages, 0);
    expect(
      f.wires[0].methods.where((m) => m['method'] == 'session/load'),
      isEmpty,
    );
  });
  test('absent port retains ordinary mismatch refusal', () async {
    final f = Fixture(installPort: false);
    addTearDown(f.close);
    await f.initial();
    expect((await f.infer()).success, false);
    expect(f.stages, 0);
    expect(
      f.wires[1].methods.where((m) => '${m['method']}'.startsWith('session/')),
      isEmpty,
    );
  });
  for (final fault in ['load', 'wrong_ack', 'commit', 'grant']) {
    test('$fault leaves original cursor and blocks replay', () async {
      final f = Fixture();
      addTearDown(f.close);
      await f.initial();
      final old = f.stored!;
      switch (fault) {
        case 'load':
          f.wires[1].rejectLoad = true;
        case 'wrong_ack':
          f.wires[1].loadId = 'different-session';
        case 'commit':
          f.failCommit = true;
        case 'grant':
          f.transitionGrant = false;
      }
      expect((await f.infer()).success, false);
      expect(identical(f.stored, old), true);
      expect(
        f.wires[1].methods.where((m) => m['method'] == 'session/prompt'),
        isEmpty,
      );
      expect((await f.infer()).error?.code, 'acp_session_rebind_pending');
      expect(f.stages, 1);
      expect(
        f.wires[2].methods.where(
          (m) => '${m['method']}'.startsWith('session/'),
        ),
        isEmpty,
      );
    });
  }
  test(
    'cancellation while stage awaits blocks load and keeps pending',
    () async {
      final f = Fixture();
      addTearDown(f.close);
      await f.initial();
      f.stageGate = Completer<void>();
      final pending = f.infer();
      while (f.stages == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      f.adapter.cancelActive();
      f.stageGate!.complete();
      expect((await pending).error?.code, 'acp_cancelled');
      expect(
        f.wires[1].methods.where((m) => m['method'] == 'session/load'),
        isEmpty,
      );
      expect((await f.infer()).error?.code, 'acp_session_rebind_pending');
    },
  );
  test(
    'cancellation after remote ACK blocks acknowledgement and commit',
    () async {
      final f = Fixture();
      addTearDown(f.close);
      await f.initial();
      f.wires[1].holdLoad = true;
      final pending = f.infer();
      while (f.wires[1].pendingLoad == null) {
        await Future<void>.delayed(Duration.zero);
      }
      f.adapter.cancelActive();
      f.wires[1].respond(f.wires[1].pendingLoad!, {'sessionId': 'persistent'});
      expect((await pending).error?.code, 'acp_cancelled');
      expect(f.acknowledgements, hasLength(1));
      expect(f.commits, 0);
    },
  );
  test('failed CAS requires explicit exact-ID reconciliation '
      'without prompt replay', () async {
    final f = Fixture();
    addTearDown(f.close);
    await f.initial();
    f.failCommit = true;
    expect((await f.infer()).success, false);
    final connections = f.connections;
    expect((await f.infer()).error?.code, 'acp_session_rebind_pending');
    expect(f.connections, connections);
    await expectLater(
      f.adapter.reconcileSessionBinding(
        workingDirectory: '/canonical-candidate',
        mcpServers: const [],
      ),
      throwsA(
        isA<AcpSessionPersistenceRefusal>().having(
          (e) => e.code,
          'code',
          'acp_session_rebind_reconciliation_scope',
        ),
      ),
    );
    f.failCommit = false;
    final reconciled = await f.adapter.reconcileSessionBinding(
      workingDirectory: '/canonical-candidate',
      mcpServers: [
        {'name': 'owner', 'type': 'http', 'url': f.descriptor},
      ],
    );
    expect(reconciled.sessionId, 'persistent');
    expect(
      f.wires[2].methods.where((m) => m['method'] == 'session/load'),
      hasLength(1),
    );
    expect(
      f.wires[2].methods.where(
        (m) => m['method'] == 'session/new' || m['method'] == 'session/prompt',
      ),
      isEmpty,
    );
    expect((await f.infer()).success, true);
    expect(
      f.wires[2].methods.where((m) => m['method'] == 'session/prompt'),
      hasLength(1),
    );
  });
  test(
    'foreign previous provider cannot stage even with port installed',
    () async {
      final f = Fixture();
      addTearDown(f.close);
      await f.initial();
      final old = f.stored!;
      // Force persisted foreign cursor through a fresh adapter without memory.
      final wire = RebindWire();
      final adapter = AcpInferenceClient(
        command: 'unused',
        conversationKey: 'conversation',
        providerIdentity: 'foreign',
        clientFactory: () async => wire.client,
        sessionPersistence: AcpSessionPersistence(
          read: (_) async => old,
          save: (_) async => fail('must not save'),
          authorize: (_, _) async => true,
          rebind: AcpSessionRebindPort(
            stage: (_, _) async => fail('must not stage'),
            authorize: (_, _, _) async => true,
            commit: (_, _, _) async => true,
          ),
        ),
      );
      expect(
        (await adapter.infer(f.request)).error?.code,
        'acp_stored_session_binding_changed',
      );
      expect(
        wire.methods.where((m) => '${m['method']}'.startsWith('session/')),
        isEmpty,
      );
      await adapter.dispose();
      await wire.output.close();
    },
  );
}
