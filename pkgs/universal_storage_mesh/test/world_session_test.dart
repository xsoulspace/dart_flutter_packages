import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_mesh/universal_storage_mesh.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';
import 'package:universal_storage_world/universal_storage_world.dart';

/// The extracted sync brain (ADR 0047 §3): participant seam ordering, the
/// coalescing host-driven pulse, and interest publication.
void main() {
  late Directory dirA;
  late Directory dirB;
  late MeshStorageProvider replicaA;
  late MeshStorageProvider replicaB;
  late FakeMeshPair pair;
  late StorageService storageA;
  late MeshWorldSession sessionA;

  setUp(() async {
    dirA = await Directory.systemTemp.createTemp('mesh_ws_a_');
    dirB = await Directory.systemTemp.createTemp('mesh_ws_b_');
    pair = FakeMeshPair.paired();

    replicaA = MeshStorageProvider();
    await replicaA.initWithConfig(
      MeshStorageConfig(storePath: dirA.path, peerId: 'device-a'),
    );
    replicaB = MeshStorageProvider();
    await replicaB.initWithConfig(
      MeshStorageConfig(storePath: dirB.path, peerId: 'device-b'),
    );

    replicaA.attachTransport(pair.a);
    replicaB.attachTransport(pair.b);

    await replicaA.registerPeer(
      const MeshPeerRecord(peerId: 'device-b', displayName: 'B'),
    );
    await replicaB.registerPeer(
      const MeshPeerRecord(peerId: 'device-a', displayName: 'A'),
    );

    storageA = StorageService(replicaA);
    sessionA = MeshWorldSession(storage: storageA, selfId: 'device-a');
  });

  tearDown(() async {
    await sessionA.dispose();
    await replicaA.dispose();
    await replicaB.dispose();
    await dirA.delete(recursive: true);
    await dirB.delete(recursive: true);
  });

  test('participant seam: flush → exchange → absorb → compact, in order',
      () async {
    final order = <String>[];
    sessionA.attachParticipant(
      _RecordingParticipant(
        onPhase: order.add,
        duringSync: () async {
          // The exchange runs while the participant is "between" its
          // flush and its absorb.
          await replicaA.createFile('docs/order-probe', 'written mid-cycle');
        },
      ),
    );

    await sessionA.pulse();

    expect(order, ['flush', 'absorb', 'compact']);
    expect(sessionA.isPeriodicPulseRunning, isFalse);
  });

  test('pulse coalesces: a pulse landing mid-cycle joins the flight',
      () async {
    final flushes = <int>[];
    final gate = Completer<void>();
    sessionA.attachParticipant(
      _RecordingParticipant(
        onPhase: (final phase) {
          if (phase == 'flush') flushes.add(flushes.length);
        },
        beforeFlush: () async {
          if (flushes.isEmpty) await gate.future;
        },
      ),
    );

    final first = sessionA.pulse();
    // Second pulse lands while the first cycle is parked in its flush.
    final second = sessionA.pulse();
    expect(identical(first, second), isTrue,
        reason: 'a coalescing pulse returns the in-flight cycle');

    gate.complete();
    await first;

    expect(flushes.length, 1, reason: 'exactly one cycle ran');
  });

  test('pulse surfaces the fold through onCycle even after a failed cycle',
      () async {
    pair.a.failNextConnect = true; // opportunistic skip — not a failure.
    var cycles = 0;
    sessionA.onCycle = () => cycles++;
    await sessionA.pulse();
    expect(cycles, 1);
  });

  test('end-to-end: a participant\'s flush crosses the mesh to a peer',
      () async {
    // Minimal stand-in for the app's DocReplicaStore seam: durable state
    // that flushes into the provider (the storage this session owns), so
    // the exchange ships it and the peer folds it.
    final docContent = <String, String>{'docs/session-e2e': 'via-session'};
    sessionA.attachParticipant(_FileBackedParticipant(replicaA, docContent));

    await sessionA.pulse();

    expect(await replicaB.getFile('docs/session-e2e'), 'via-session');
  });

  test('setInterest publishes through to a mesh-backed provider', () async {
    sessionA.setInterest(const MemberPrefixInterest({'zones/'}));
    // The selection lives on the provider (the exchange reads it); the
    // session is a pass-through.
    expect(replicaA.memberKind, 'file');
    sessionA.setInterest(null); // clear back to wildcard
    sessionA.setDeliveryPriority({'x': 1});
    sessionA.setIncomingBudget(3);
  });
}

/// A participant backed by plain provider files (the "whole-file member"
/// seam shape): flush publishes its durable map, absorb re-reads it.
final class _FileBackedParticipant implements MeshSyncParticipant {
  _FileBackedParticipant(this._provider, this._durable);

  final MeshStorageProvider _provider;
  final Map<String, String> _durable;

  @override
  Future<void> flush(final StorageService storage) async {
    for (final entry in _durable.entries) {
      await _provider.updateFile(entry.key, entry.value);
    }
  }

  @override
  Future<void> absorb(final StorageService storage) async {}

  @override
  Future<void> compact(final StorageService storage) async {}
}

/// A participant that records its phases and can park mid-phase.
final class _RecordingParticipant implements MeshSyncParticipant {
  _RecordingParticipant({
    required this.onPhase,
    this.beforeFlush,
    this.duringSync,
  });

  final void Function(String phase) onPhase;
  final Future<void> Function()? beforeFlush;
  final Future<void> Function()? duringSync;

  @override
  Future<void> flush(final StorageService storage) async {
    await beforeFlush?.call();
    onPhase('flush');
    await duringSync?.call();
  }

  @override
  Future<void> absorb(final StorageService storage) async {
    onPhase('absorb');
  }

  @override
  Future<void> compact(final StorageService storage) async {
    onPhase('compact');
  }
}
