import 'dart:convert';

import 'package:test/test.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_mesh/universal_storage_mesh.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

/// Web-backed replica semantics.
///
/// Production web builds select a `localStorage`-backed store via
/// compile-time conditional import (falling back to in-memory when
/// `localStorage` is unavailable). The VM cannot run `localStorage`, so
/// these tests exercise the exact same provider code path with an
/// injected [MemoryMeshKvStore] — the web fallback backing — and a
/// `storePath` that would be a filesystem path on io platforms.
void main() {
  Future<MeshStorageProvider> webReplica(MemoryMeshKvStore backing) async {
    final provider = MeshStorageProvider(kvStoreFactory: (_) => backing);
    await provider.initWithConfig(
      MeshStorageConfig(
        storePath: '/ignored/by/web/backing',
        peerId: 'web-peer',
        displayName: 'Web Peer',
      ),
    );
    return provider;
  }

  test('MemoryMeshKvStore read/write/list roundtrip', () async {
    final store = MemoryMeshKvStore();
    expect(await store.read('missing'), isNull);
    await store.write('peers.json', '[]');
    await store.write('docs/a.json', '{}');
    expect(await store.read('peers.json'), '[]');
    expect(await store.list('docs/'), ['docs/a.json']);
    expect(await store.list('peers'), ['peers.json']);
  });

  test('init + registerPeer + peers list on a web-style backing', () async {
    final provider = await webReplica(MemoryMeshKvStore());
    expect(await provider.isAuthenticated(), isTrue);
    await provider.registerPeer(
      const MeshPeerRecord(peerId: 'host-1', displayName: 'Host'),
    );
    expect(provider.peers.map((final p) => p.peerId), ['host-1']);
  });

  test('peer records and docs persist across a reload', () async {
    final backing = MemoryMeshKvStore();
    final first = await webReplica(backing);
    await first.registerPeer(
      const MeshPeerRecord(peerId: 'host-1', displayName: 'Host'),
    );
    await first.createFile('notes/todo.txt', 'pair the host');

    // Simulated reload: a fresh provider over the same persisted state
    // (on web, what localStorage restores; without localStorage this is
    // the documented session-only behavior).
    final second = await webReplica(backing);
    expect(second.peers.map((final p) => p.peerId), ['host-1']);
    expect(await second.getFile('notes/todo.txt'), 'pair the host');
    expect((await second.listDirectory('notes')).map((final e) => e.name), [
      'todo.txt',
    ]);
  });

  test('sync() is a no-op without transports (web: none attached)', () async {
    final provider = await webReplica(MemoryMeshKvStore());
    await provider.registerPeer(
      const MeshPeerRecord(peerId: 'host-1', displayName: 'Host'),
    );
    await provider.sync(); // Must not throw without any transport.
    expect(provider.peers, isNotEmpty);
  });

  test('web backing keeps the documented shard/registry layout', () async {
    final backing = MemoryMeshKvStore();
    final provider = await webReplica(backing);
    await provider.registerPeer(
      const MeshPeerRecord(peerId: 'host-1', displayName: 'Host'),
    );
    await provider.createFile('a/b.txt', 'x');
    expect(await backing.list('docs/'), [
      'docs/${Uri.encodeComponent('a/b.txt').replaceAll('/', '%2F')}.json',
    ]);
    final registry =
        (jsonDecode(await backing.read('peers.json') ?? '') as List<dynamic>)
            .cast<Map<String, dynamic>>();
    expect(registry.single['peer_id'], 'host-1');
  });

  test(':memory: mode stays ephemeral (unchanged behavior)', () async {
    final provider = MeshStorageProvider(
      kvStoreFactory: (_) {
        throw StateError('must not be called for :memory:');
      },
    );
    await provider.initWithConfig(
      MeshStorageConfig(storePath: ':memory:', peerId: 'p'),
    );
    await provider.registerPeer(
      const MeshPeerRecord(peerId: 'host-1', displayName: 'Host'),
    );
    expect(provider.peers.single.peerId, 'host-1');
    await provider.dispose();
  });
}
