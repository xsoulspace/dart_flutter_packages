import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_mesh/universal_storage_mesh.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

/// Integration-level proof that mesh behaves as a drop-in
/// `StorageProvider` for applications (ADR 0010 milestone):
/// - multi-hop convergence through an intermediary replica,
/// - inbound sessions handled on the responder side,
/// - snapshot adoption when deltas exceed policy,
/// - provider contract usable without knowing about transports.
void main() {
  group('mesh integration readiness', () {
    late Directory dirA;
    late Directory dirB;
    late Directory dirC;
    late MeshStorageProvider a;
    late MeshStorageProvider b;
    late MeshStorageProvider c;
    late FakeMeshPair pairAB;
    late FakeMeshPair pairBC;

    setUp(() async {
      dirA = await Directory.systemTemp.createTemp('mesh_it_a_');
      dirB = await Directory.systemTemp.createTemp('mesh_it_b_');
      dirC = await Directory.systemTemp.createTemp('mesh_it_c_');
      pairAB = FakeMeshPair.paired(a: 'device-a', b: 'device-b');
      pairBC = FakeMeshPair.paired(a: 'device-b', b: 'device-c');

      Future<MeshStorageProvider> replica(
        final Directory dir,
        final String id,
      ) async {
        final p = MeshStorageProvider();
        await p.initWithConfig(
          MeshStorageConfig(storePath: dir.path, peerId: id),
        );
        return p;
      }

      a = await replica(dirA, 'device-a');
      b = await replica(dirB, 'device-b');
      c = await replica(dirC, 'device-c');

      // A↔B link and B↔C link. A and C have no direct link: B is the only
      // path between them (a relay-by-topology node, not by authority).
      a.attachTransport(pairAB.a);
      b.attachTransport(pairAB.b);
      b.attachTransport(pairBC.a);
      c.attachTransport(pairBC.b);

      await a.registerPeer(
        const MeshPeerRecord(peerId: 'device-b', displayName: 'B'),
      );
      await b.registerPeer(
        const MeshPeerRecord(peerId: 'device-a', displayName: 'A'),
      );
      await b.registerPeer(
        const MeshPeerRecord(peerId: 'device-c', displayName: 'C'),
      );
      await c.registerPeer(
        const MeshPeerRecord(peerId: 'device-b', displayName: 'B'),
      );
    });

    tearDown(() async {
      await a.dispose();
      await b.dispose();
      await c.dispose();
      await dirA.delete(recursive: true);
      await dirB.delete(recursive: true);
      await dirC.delete(recursive: true);
    });

    test('data flows A→B→C across two hops', () async {
      await a.createFile('shared/state.json', '{"step":1}');
      await a.sync();
      expect(await b.getFile('shared/state.json'), '{"step":1}');

      await b.sync(); // B pushes what it learned toward C.
      expect(await c.getFile('shared/state.json'), '{"step":1}');
    });

    test('inbound sessions converge state on the responder side', () async {
      // Only C writes; then B initiates. The exchange must apply C's data
      // on B via B's inbound handler path too when roles reverse.
      await c.createFile('from-c.txt', 'hello-from-c');

      // B initiates toward C: exercises initiator path on B.
      await b.sync();
      expect(await b.getFile('from-c.txt'), 'hello-from-c');

      // C initiates toward B: exercises responder/inbound path on B.
      await c.updateFile('from-c.txt', 'updated-by-c');
      await c.sync();
      expect(await b.getFile('from-c.txt'), 'updated-by-c');
    });

    test('concurrent edits from all replicas converge identically', () async {
      await a.createFile('doc.md', 'v-a');
      await b.createFile('other.md', 'v-b');
      await c.createFile('third.md', 'v-c');

      await a.sync();
      await b.sync();
      await c.sync();
      // Second round: A and C learn what B gathered from the other side.
      await a.sync();
      await c.sync();

      // Everyone converges to the same full document set.
      final atA = {
        await a.getFile('doc.md'),
        await a.getFile('other.md'),
        await a.getFile('third.md'),
      };
      final atC = {
        await c.getFile('doc.md'),
        await c.getFile('other.md'),
        await c.getFile('third.md'),
      };
      expect(atA, {'v-a', 'v-b', 'v-c'});
      expect(atC, atA);
    });

    test('compacted replica catches up via snapshot adoption', () async {
      await a.createFile('log/entry.txt', 'first');
      await a.sync();
      expect(await b.getFile('log/entry.txt'), 'first');

      // A compacts its log after B acknowledged; then more writes happen
      // while B is offline, and A compacts again before B returns.
      await a.compactDocs();
      await a.updateFile('log/entry.txt', 'second');
      await a.sync();
      await a.compactDocs();
      await a.updateFile('log/entry.txt', 'third');

      // B (still at "first") must catch up fully.
      await a.sync();
      expect(await b.getFile('log/entry.txt'), 'third');
    });

    test('provider works as plain StorageProvider with no transport', () async {
      // An app that never configures mesh peers still gets a working
      // local-first store: reads/writes succeed, sync is a no-op.
      final solo = MeshStorageProvider();
      final dir = await Directory.systemTemp.createTemp('mesh_solo_');
      addTearDown(() => dir.delete(recursive: true));
      await solo.initWithConfig(
        MeshStorageConfig(storePath: dir.path, peerId: 'solo'),
      );
      addTearDown(solo.dispose);

      await solo.createFile('app/settings.json', '{"theme":"dark"}');
      expect(await solo.getFile('app/settings.json'), '{"theme":"dark"}');
      await expectLater(solo.sync(), completes);
      expect(
        solo.declaredCapabilities.syncAvailability,
        SyncAvailability.withRemoteConfig,
      );
    });

    test('binary-safe payloads round-trip through sync', () async {
      // Opaque content is stored as a string register; verify arbitrary
      // UTF-16-ish text survives the wire encode/decode unchanged.
      final payload = String.fromCharCodes([
        0x00E9, 0x1F600, 0x4E2D, 0x0041, // é 😀 中 A
      ]);
      await a.createFile('blob/data.bin', payload);
      await a.sync();
      expect(await b.getFile('blob/data.bin'), payload);
    });
  });
}

extension on MeshStorageProvider {
  /// Triggers kernel-side log compaction of every local doc.
  Future<void> compactDocs() => compactAll();
}
