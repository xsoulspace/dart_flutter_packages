import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_mesh/universal_storage_mesh.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';
import 'package:universal_storage_world/universal_storage_world.dart';

/// Interest-managed exchange scenarios (ADR 0048): the peer's published
/// [InterestSelection] gates what a replica DELIVERS; priority orders the
/// delta; the budget caps it. The world "relevancy filter" — sync cost
/// follows the subscriber's working set, not the whole world.
void main() {
  late Directory dirA;
  late Directory dirB;
  late MeshStorageProvider replicaA;
  late MeshStorageProvider replicaB;
  late FakeMeshPair pair;

  setUp(() async {
    dirA = await Directory.systemTemp.createTemp('mesh_ix_a_');
    dirB = await Directory.systemTemp.createTemp('mesh_ix_b_');
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
  });

  tearDown(() async {
    await replicaA.dispose();
    await replicaB.dispose();
    await dirA.delete(recursive: true);
    await dirB.delete(recursive: true);
  });

  test('subscription gates delivery: out-of-zone members never arrive', () async {
    await replicaA.createFile('zones/dungeon/room-1', 'in-zone');
    await replicaA.createFile('zones/forest/room-1', 'out-of-zone');
    await replicaA.createFile('notes/misc', 'unrelated');

    // B subscribes to the dungeon sector only.
    replicaB.setInterest(const MemberPrefixInterest({'zones/dungeon/'}));

    await replicaA.sync();

    expect(await replicaB.getFile('zones/dungeon/room-1'), 'in-zone');
    expect(await replicaB.getFile('zones/forest/room-1'), isNull);
    expect(await replicaB.getFile('notes/misc'), isNull);
  });

  test('no subscription means the wildcard (full delivery, old behavior)',
      () async {
    await replicaA.createFile('zones/dungeon/room-1', 'a');
    await replicaA.createFile('zones/forest/room-1', 'b');

    await replicaA.sync();

    expect(await replicaB.getFile('zones/dungeon/room-1'), 'a');
    expect(await replicaB.getFile('zones/forest/room-1'), 'b');
  });

  test('budget caps the delta per exchange; later pulses finish the job',
      () async {
    for (var i = 0; i < 5; i++) {
      await replicaA.createFile('bulk/doc-$i', 'payload-$i');
    }

    // B wants everything but only 2 ops per exchange.
    replicaB.setInterest(const AllInterest());
    replicaB.setIncomingBudget(2);

    await replicaA.sync();
    var received = (await replicaB.listDirectory('bulk')).length;
    expect(received, 2, reason: 'budget caps one exchange to 2 ops');

    await replicaA.sync();
    received = (await replicaB.listDirectory('bulk')).length;
    expect(received, 4);

    await replicaA.sync();
    received = (await replicaB.listDirectory('bulk')).length;
    expect(received, 5, reason: 'pulses converge the rest incrementally');
  });

  test('priority orders the delta: ranked member crosses the wire first',
      () async {
    await replicaA.createFile('bulk/aaa', 'first-written');
    await replicaA.createFile('bulk/zzz', 'must-arrive-first');

    replicaB.setInterest(const AllInterest());
    // B ranks zzz ahead; with a budget of one op, ONLY the ranked member
    // may cross this exchange — outcome-level proof of ordering.
    replicaB.setDeliveryPriority({'bulk/zzz': 0});
    replicaB.setIncomingBudget(1);

    await replicaA.sync();

    expect(await replicaB.getFile('bulk/zzz'), 'must-arrive-first');
    expect(await replicaB.getFile('bulk/aaa'), isNull);
  });

  test('memberRefs lists live members with their version vectors; urnOf '
      'names through the resolver', () async {
    await replicaA.createFile('docs/a', 'a');
    await replicaA.createFile('docs/b', 'b');
    await replicaA.createFile('docs/gone', 'x');
    await replicaA.deleteFile('docs/gone');

    final refs = replicaA.memberRefs().map((final r) => r.docId).toSet();
    expect(refs, {'docs/a', 'docs/b'});

    expect(replicaA.urnOf('docs/a').value, 'world://local/docs/a');
  });

  test('tolerates a pre-0048 responder that sends no sub frame', () async {
    // A hand-scripted peer speaking the OLD script (hello + vv + delta,
    // no sub). Our side must consume the sub-less handshake and still
    // converge their delta — and our own sub frame must not confuse the
    // (simulated) old receive loop, which skips unknown frames.
    final scripted = ScriptedOldPeerTransport();
    final freshA = MeshStorageProvider();
    final dir = await Directory.systemTemp.createTemp('mesh_ix_old_');
    addTearDown(() async {
      await freshA.dispose();
      await dir.delete(recursive: true);
    });
    await freshA.initWithConfig(
      MeshStorageConfig(storePath: dir.path, peerId: 'device-a'),
    );
    freshA.attachTransport(scripted);
    await freshA.registerPeer(
      const MeshPeerRecord(peerId: 'elder', displayName: 'Elder'),
    );
    await freshA.createFile('docs/new-to-old', 'cross-version');

    await expectLater(freshA.sync(), completes);
    expect(scripted.receivedDelta, isNotNull, reason: 'we served the elder');
    // And the exchange completing AT ALL is the compat proof: the elder
    // speaks the old script (hello + vv + delta, never a sub) while our
    // side sent one — the sub frame is purely additive on the wire.
  });
}

/// A scripted peer speaking the pre-0048 script: hello + vv + delta, no
/// sub frame. Proves the sub frame is additive: it receives our hello,
/// skips our sub (unknown type), consumes our vv, and answers.
final class ScriptedOldPeerTransport implements MeshTransport {
  final _incoming = StreamController<MeshSession>();

  /// The delta we (the old peer) received from the real replica.
  Map<String, Object?>? receivedDelta;

  @override
  Stream<MeshSession> get incoming => _incoming.stream;

  @override
  Future<MeshSession> connect(final MeshPeerRecord peer) async {
    final fromReplica = StreamController<Uint8List>();
    final fromPeer = StreamController<Uint8List>();
    final replicaSession = _ScriptedSession(
      inbound: fromReplica.stream,
      onSend: fromPeer.add,
    );
    unawaited(_serve(fromPeer.stream, fromReplica));
    return replicaSession;
  }

  Future<void> _serve(
    final Stream<Uint8List> replicaFrames,
    final StreamController<Uint8List> toReplica,
  ) async {
    await for (final frame in replicaFrames) {
      final message =
          Map<String, Object?>.from(
            jsonDecode(utf8.decode(frame)) as Map<dynamic, dynamic>,
          );
      switch (message['type']) {
        case 'delta':
          receivedDelta = message;
        case 'hello':
          toReplica.add(
            _frame({
              'type': 'hello',
              'peer_id': 'elder',
              'display_name': 'Elder',
            }),
          );
        case 'vv':
          // The elder has nothing; announce an empty world.
          toReplica.add(_frame({'type': 'vv', 'docs': <String, Object?>{}}));
          toReplica.add(
            _frame({'type': 'delta', 'ops': <Object?>[], 'states': <Object?>[]}),
          );
      }
    }
  }

  Uint8List _frame(final Map<String, Object?> message) =>
      Uint8List.fromList(utf8.encode(jsonEncode(message)));
}

final class _ScriptedSession implements MeshSession {
  _ScriptedSession({
    required Stream<Uint8List> inbound,
    required void Function(Uint8List) onSend,
  }) : _inbound = inbound,
       _onSend = onSend;

  final Stream<Uint8List> _inbound;
  final void Function(Uint8List) _onSend;

  @override
  String get remotePeerId => 'elder';

  @override
  Stream<Uint8List> get inbound => _inbound;

  @override
  Future<void> send(final Uint8List payload) async => _onSend(payload);

  @override
  Future<void> close() async {}
}
