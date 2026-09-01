import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_mesh/universal_storage_mesh.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

/// Two-replica scenarios against the scripted fake transport — the ADR 0010
/// milestone: provider semantics proven headless before any radio code.
void main() {
  late Directory dirA;
  late Directory dirB;
  late MeshStorageProvider replicaA;
  late MeshStorageProvider replicaB;
  late FakeMeshPair pair;

  setUp(() async {
    dirA = await Directory.systemTemp.createTemp('mesh_a_');
    dirB = await Directory.systemTemp.createTemp('mesh_b_');
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
    // B is the responder side of A-initiated sessions; it also initiates
    // its own sync() calls through the same transport when needed.
    replicaB.attachTransport(pair.b);

    await replicaA.registerPeer(
      const MeshPeerRecord(peerId: 'device-b', displayName: 'B'),
    );
    await replicaB.registerPeer(
      const MeshPeerRecord(peerId: 'device-a', displayName: 'A'),
    );
  });

  tearDown(() async {
    await replicaA.dispose();
    await replicaB.dispose();
    await dirA.delete(recursive: true);
    await dirB.delete(recursive: true);
  });

  test('write on A reaches B after one sync session', () async {
    await replicaA.createFile('notes/todo.json', '{"done":false}');

    await replicaA.sync();

    expect(await replicaB.getFile('notes/todo.json'), '{"done":false}');
    // And A learned nothing new but stays intact.
    expect(await replicaA.getFile('notes/todo.json'), '{"done":false}');
  });

  test('offline writes on both sides converge in both directions', () async {
    await replicaA.createFile('a-only.txt', 'written-on-a');
    await replicaB.createFile('b-only.txt', 'written-on-b');

    await replicaA.sync();

    expect(await replicaB.getFile('a-only.txt'), 'written-on-a');
    expect(await replicaA.getFile('b-only.txt'), 'written-on-b');
  });

  test('deletions propagate as tombstones', () async {
    await replicaA.createFile('temp/gone.txt', 'value');
    await replicaA.sync();
    expect(await replicaB.getFile('temp/gone.txt'), 'value');

    await replicaA.deleteFile('temp/gone.txt');
    await replicaA.sync();

    expect(await replicaA.getFile('temp/gone.txt'), isNull);
    expect(await replicaB.getFile('temp/gone.txt'), isNull);
  });

  test('concurrent conflicting writes converge to the same winner', () async {
    // Both replicas write the same path while disconnected. HLC total
    // order (wall, counter, actorId) must pick one deterministic winner.
    await replicaA.createFile('conflict/x.json', 'from-a');
    await replicaB.createFile('conflict/x.json', 'from-b');

    // Both initiate sessions (sequential, symmetric protocol).
    await replicaA.sync();
    await replicaB.sync();

    final atA = await replicaA.getFile('conflict/x.json');
    final atB = await replicaB.getFile('conflict/x.json');
    expect(atA, isNotNull);
    expect(atA, atB, reason: 'both replicas must agree on the winner');
    expect(atA, anyOf('from-a', 'from-b'));
  });

  test('unreachable peer does not break local work or sync()', () async {
    await replicaA.createFile('offline/keep.txt', 'local-first');

    pair.a.failNextConnect = true;
    await expectLater(replicaA.sync(), completes);
    // Local state untouched by failed connectivity.
    expect(await replicaA.getFile('offline/keep.txt'), 'local-first');

    // Link returns; next sync converges.
    await replicaA.sync();
    expect(await replicaB.getFile('offline/keep.txt'), 'local-first');
  });

  test('replica state survives process restart (persistence)', () async {
    await replicaA.createFile('durable/note.md', '# persists');
    await replicaB.createFile('durable/other.md', 'b-data');
    await replicaA.sync();

    // Recreate both replicas from their store directories.
    final revivedA = MeshStorageProvider();
    await revivedA.initWithConfig(
      MeshStorageConfig(storePath: dirA.path, peerId: 'device-a'),
    );
    final revivedB = MeshStorageProvider();
    await revivedB.initWithConfig(
      MeshStorageConfig(storePath: dirB.path, peerId: 'device-b'),
    );
    addTearDown(() async {
      await revivedA.dispose();
      await revivedB.dispose();
    });

    expect(await revivedA.getFile('durable/note.md'), '# persists');
    expect(await revivedB.getFile('durable/other.md'), 'b-data');

    // Revived replicas still converge with each other.
    await revivedA.sync();
    expect(await revivedB.getFile('durable/note.md'), '# persists');
  });
}
