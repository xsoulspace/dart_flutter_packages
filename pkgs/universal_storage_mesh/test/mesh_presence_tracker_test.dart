import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_convergence/universal_storage_convergence.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_mesh/universal_storage_mesh.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

void main() {
  final t0 = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  group('presence fold (agent-queryable)', () {
    test('join makes a peer present with its details', () {
      const ttl = Duration(seconds: 30);
      final a = MeshPresenceTracker(actorId: 'device-a')
        ..announce(
          docId: 'notes/todo.json',
          event: MeshEphemeralEvent.join,
          now: t0,
          ttl: ttl,
          details: {'display': 'Alice', 'agent': 'writer-v2'},
        );

      final entries = a.presence('notes/todo.json');
      expect(entries, hasLength(1));
      expect(entries.single.peerId, 'device-a');
      expect(entries.single.lastEvent, MeshEphemeralEvent.join);
      expect(entries.single.details['display'], 'Alice');
      expect(entries.single.expiresAt, t0.add(ttl));
    });

    test('ping refreshes the entry, leave removes it from the fold', () {
      final a = MeshPresenceTracker(actorId: 'device-a')
        ..announce(docId: 'd', event: MeshEphemeralEvent.join, now: t0)
        ..announce(
          docId: 'd',
          event: MeshEphemeralEvent.ping,
          now: t0.add(const Duration(seconds: 5)),
        );

      expect(a.presence('d').single.lastEvent, MeshEphemeralEvent.ping);

      a.announce(
        docId: 'd',
        event: MeshEphemeralEvent.leave,
        now: t0.add(const Duration(seconds: 10)),
      );
      expect(a.presence('d'), isEmpty);
      // Tombstone expires like any ephemeral op; a later join re-enters.
      a.announce(
        docId: 'd',
        event: MeshEphemeralEvent.join,
        now: t0.add(const Duration(seconds: 11)),
      );
      expect(a.presence('d').single.lastEvent, MeshEphemeralEvent.join);
    });

    test('documents are independent folds', () {
      final a = MeshPresenceTracker(actorId: 'device-a')
        ..announce(docId: 'doc-1', event: MeshEphemeralEvent.join, now: t0);
      expect(a.presence('doc-1'), hasLength(1));
      expect(a.presence('doc-2'), isEmpty);
    });
  });

  group('ttl expiry', () {
    test('sweep expires entries past their ttl, idempotently', () {
      final a = MeshPresenceTracker(actorId: 'device-a')
        ..announce(
          docId: 'd',
          event: MeshEphemeralEvent.join,
          now: t0,
          ttl: const Duration(seconds: 30),
        );

      final atBoundary = t0.add(const Duration(seconds: 30));
      expect(a.presence('d', now: atBoundary), hasLength(1));
      expect(a.sweep(atBoundary), 0);
      expect(a.sweep(t0.add(const Duration(seconds: 31))), 1);
      expect(a.presence('d'), isEmpty);
      expect(a.sweep(t0.add(const Duration(seconds: 31))), 0);
    });

    test('handleFrame drops already-expired peer events', () {
      final a = MeshPresenceTracker(actorId: 'device-a');
      final b = MeshPresenceTracker(actorId: 'device-b');
      final frame = b.announce(
        docId: 'd',
        event: MeshEphemeralEvent.join,
        now: t0,
        ttl: const Duration(seconds: 30),
      );

      final expired = t0.add(const Duration(seconds: 31));
      expect(a.handleFrame(frame, now: expired), isTrue);
      expect(a.presence('d'), isEmpty);
    });
  });

  group('frame relay between trackers', () {
    test('join travels as an ephemeral frame and folds remotely', () async {
      final pair = FakeMeshPair.paired();
      final a = MeshPresenceTracker(actorId: 'device-a');
      final b = MeshPresenceTracker(actorId: 'device-b');

      // ignore: unawaited_futures
      pair.b.incoming.listen((session) async {
        await for (final bytes in session.inbound) {
          b.handleFrame(MeshEphemeralFrame.decode(bytes), now: t0);
        }
      });

      final session = await pair.a.connect(
        const MeshPeerRecord(peerId: 'device-b', displayName: 'B'),
      );
      await session.send(
        a
            .announce(
              docId: 'notes/todo.json',
              event: MeshEphemeralEvent.join,
              now: t0,
              details: {'display': 'Alice'},
            )
            .encode(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final entries = b.presence('notes/todo.json');
      expect(entries, hasLength(1));
      expect(entries.single.peerId, 'device-a');
      expect(entries.single.details['display'], 'Alice');
    });

    test('handleFrame rejects durable ops and forged actors', () {
      final a = MeshPresenceTracker(actorId: 'device-a');
      final b = MeshPresenceTracker(actorId: 'device-b');

      // A durable op smuggled into a frame must be refused.
      final doc = ConvergenceDoc(docId: 'd', actorId: 'device-b');
      final durable = doc.applyLocal({'k': 'k', 'v': 'v'}, t0);
      final forged = MeshEphemeralFrame(
        docId: 'd',
        fromPeerId: 'device-b',
        event: MeshEphemeralEvent.join,
        ttl: const Duration(seconds: 30),
        payload: {'op': durable.toJson()},
      );
      expect(a.handleFrame(forged, now: t0), isFalse);
      expect(a.presence('d'), isEmpty);

      // Actor mismatch between op and frame envelope is refused too.
      final joinFrame = b.announce(
        docId: 'd',
        event: MeshEphemeralEvent.join,
        now: t0,
      );
      final spoofed = MeshEphemeralFrame(
        docId: joinFrame.docId,
        fromPeerId: 'device-evil',
        event: joinFrame.event,
        ttl: joinFrame.ttl,
        payload: joinFrame.payload,
      );
      expect(a.handleFrame(spoofed, now: t0), isFalse);
    });
  });

  group('ephemeral frames never persist to the replica store', () {
    late Directory dirA;
    late Directory dirB;
    late MeshStorageProvider replicaA;
    late MeshStorageProvider replicaB;

    setUp(() async {
      dirA = await Directory.systemTemp.createTemp('mesh_presence_a_');
      dirB = await Directory.systemTemp.createTemp('mesh_presence_b_');
      replicaA = MeshStorageProvider();
      await replicaA.initWithConfig(
        MeshStorageConfig(storePath: dirA.path, peerId: 'device-a'),
      );
      replicaB = MeshStorageProvider();
      await replicaB.initWithConfig(
        MeshStorageConfig(storePath: dirB.path, peerId: 'device-b'),
      );
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

    test('presence stays out of anti-entropy and persisted docs', () async {
      // Durable content syncs over the replica transport…
      final syncPair = FakeMeshPair.paired();
      replicaA.attachTransport(syncPair.a);
      replicaB.attachTransport(syncPair.b);
      await replicaA.createFile('notes/todo.json', '{"done":false}');
      await replicaA.sync();
      expect(await replicaB.getFile('notes/todo.json'), '{"done":false}');

      // …while presence rides ephemeral frames on its own link and is
      // folded only into the (volatile) trackers — never the replicas.
      final presencePair = FakeMeshPair.paired();
      final trackerA = MeshPresenceTracker(actorId: 'device-a');
      final trackerB = MeshPresenceTracker(actorId: 'device-b');
      // ignore: unawaited_futures
      presencePair.b.incoming.listen((session) async {
        await for (final bytes in session.inbound) {
          trackerB.handleFrame(
            MeshEphemeralFrame.decode(bytes),
            now: DateTime.now(),
          );
        }
      });
      final session = await presencePair.a.connect(
        const MeshPeerRecord(peerId: 'device-b', displayName: 'B'),
      );
      await session.send(
        trackerA
            .announce(
              docId: 'notes/todo.json',
              event: MeshEphemeralEvent.join,
              details: {'display': 'Alice'},
            )
            .encode(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(trackerA.presence('notes/todo.json'), hasLength(1));
      expect(trackerB.presence('notes/todo.json'), hasLength(1));

      // A sync after the presence exchange must not ship presence ops.
      await replicaA.sync();

      for (final dir in [dirA, dirB]) {
        final docFiles =
            Directory('${dir.path}/docs')
                .listSync()
                .whereType<File>()
                .where((f) => f.path.endsWith('.json'))
                .toList();
        expect(docFiles, isNotEmpty);
        for (final file in docFiles) {
          final raw =
              jsonDecode(file.readAsStringSync()) as Map<dynamic, dynamic>;
          final doc = raw['doc'] as Map<dynamic, dynamic>;
          final state = doc['state'] as Map<dynamic, dynamic>;
          expect(
            state.keys.where((k) => (k as String) == 'device-a'),
            isEmpty,
            reason: 'presence must never reach durable state (${file.path})',
          );
          final ephemeralLog =
              (doc['ephemeral_log'] ?? const []) as List<dynamic>;
          expect(
            ephemeralLog,
            isEmpty,
            reason: 'no ephemeral ops may persist in the replica store '
                '(${file.path})',
          );
        }
      }

      // Fresh replicas restore durable content only — presence is gone.
      final reloadedB = MeshStorageProvider();
      await reloadedB.initWithConfig(
        MeshStorageConfig(storePath: dirB.path, peerId: 'device-b'),
      );
      addTearDown(reloadedB.dispose);
      expect(await reloadedB.getFile('notes/todo.json'), '{"done":false}');
      expect(await reloadedB.listDirectory('notes'), isNotEmpty);
    });
  });
}
