// The binary-member lane: manifests are ordinary members (sync ships
// them), bytes ride dedicated claimed sessions, and the protocol is
// dialer-symmetric (fetch AND push) so a dialer-only topology ships blobs
// with no second server. Also proves the three-plane split on ONE
// transport: sync, blobs, and a passthrough realtime consumer each see
// exactly their own dials.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_storage_chunks/universal_storage_chunks.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_mesh/universal_storage_mesh.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';
import 'package:universal_storage_world/universal_storage_world.dart';

StorageService _memoryStorage() => StorageService(MeshStorageProvider());

Future<StorageService> _init(final StorageService storage) async {
  await (storage.provider as MeshStorageProvider).initWithConfig(
    MeshStorageConfig(storePath: ':memory:', peerId: 't', displayName: 't'),
  );
  return storage;
}

/// The fake pair's close does not propagate a done event to the peer
/// (sessions die independently), so serve() lifetime is observed through
/// the store.
Future<void> _until(final Future<bool> Function() probe) async {
  for (var i = 0; i < 500; i++) {
    if (await probe()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition not reached within 5s');
}

void main() {
  test('publish writes the manifest member and fires the census entry', () async {
    final storage = await _init(_memoryStorage());
    final published = <String, ZoneMemberEntry>{};
    final lane = MeshBlobLane(
      storage: storage,
      blobs: ChunkedBlobStore(chunks: MemoryChunkStore()),
      onPublished: (final docId, final entry) => published[docId] = entry,
    );

    final manifest = await lane.publish(
      'vosges/phone/blobs/trace.json',
      List<int>.generate(200 * 1024, (i) => i % 251),
      mime: 'application/x-vosges-trace',
    );

    final stored = await lane.manifestOf('vosges/phone/blobs/trace.json');
    expect(stored, isNotNull);
    expect(stored!.root, manifest.root);
    expect(published['vosges/phone/blobs/trace.json'], isNotNull);
    final entry = published['vosges/phone/blobs/trace.json']!;
    expect(entry.kind, 'blob');
    expect(entry.meta['size'], manifest.size);
    expect(entry.meta['chunks'], manifest.chunks.length);

    await lane.unpublish('vosges/phone/blobs/trace.json');
    expect(await lane.manifestOf('vosges/phone/blobs/trace.json'), isNull);
  });

  test('fetchFrom pulls verified gaps from a serving peer and materializes',
      () async {
    final serverStorage = await _init(_memoryStorage());
    final serverChunks = MemoryChunkStore();
    final serverLane = MeshBlobLane(
      storage: serverStorage,
      blobs: ChunkedBlobStore(chunks: serverChunks),
    );
    final pair = FakeMeshPair.paired();
    serverLane.attachTransport(pair.a);

    const docId = 'vosges/desktop/blobs/bundle.json';
    final bytes = List<int>.generate(400 * 1024, (i) => (i * 13) % 256);
    await serverLane.publish(docId, bytes, mime: 'application/octet-stream');

    final clientStorage = await _init(_memoryStorage());
    final clientLane = MeshBlobLane(
      storage: clientStorage,
      blobs: ChunkedBlobStore(chunks: MemoryChunkStore()),
    );
    // The manifest reached the client through SYNC (simulated by copying
    // the member — the two-node e2e proves the real wire).
    await clientStorage.saveFile(docId, (await serverStorage.readFile(docId))!);

    var progressFired = false;
    final restored = await clientLane.fetchFrom(
      docId,
      dial: pair.b,
      peer: const MeshPeerRecord(peerId: 'device-a', displayName: 'A'),
      onProgress: (final fetched, final total) {
        progressFired = fetched == total;
      },
    );
    expect(restored.length, bytes.length);
    expect(progressFired, isTrue);
  });

  test('pushTo ships chunks to a serving peer without it ever dialing',
      () async {
    final receiverStorage = await _init(_memoryStorage());
    final receiverChunks = MemoryChunkStore();
    final receiverLane = MeshBlobLane(
      storage: receiverStorage,
      blobs: ChunkedBlobStore(chunks: receiverChunks),
    );
    final pair = FakeMeshPair.paired();
    receiverLane.attachTransport(pair.a);

    const docId = 'vosges/phone/blobs/capture.json';
    final bytes = List<int>.generate(300 * 1024, (i) => (i * 7) % 256);
    final senderLane = MeshBlobLane(
      storage: await _init(_memoryStorage()),
      blobs: ChunkedBlobStore(chunks: MemoryChunkStore()),
    );
    await senderLane.publish(docId, bytes);

    final sent = await senderLane.pushTo(
      docId,
      dial: pair.b,
      peer: const MeshPeerRecord(peerId: 'device-a', displayName: 'A'),
    );
    final manifest = await senderLane.manifestOf(docId);
    await _until(() => receiverChunks.has(manifest!.chunks.last));

    expect(sent, manifest!.chunks.length);
    final restored = await receiverLane.blobs.getBytes(manifest);
    expect(restored.length, bytes.length);
  });

  test('three planes on one transport route to exactly their consumers',
      () async {
    final hub = FakeMeshHub();
    final syncPlane = ClaimingMeshTransport(
      inner: hub,
      claim: looksLikeWorldSyncFrame,
    );
    final blobPlane = ClaimingMeshTransport(
      inner: syncPlane.passthrough,
      claim: looksLikeChunkFrame,
    );
    final realtime = <MeshSession>[];
    blobPlane.passthrough.incoming.listen(realtime.add);
    final syncDials = <MeshSession>[];
    syncPlane.incoming.listen(syncDials.add);
    final blobDials = <MeshSession>[];
    blobPlane.incoming.listen(blobDials.add);

    Uint8List frame(final Map<String, Object?> json) =>
        Uint8List.fromList(utf8.encode(jsonEncode(json)));

    hub.openSession('rt').receive(frame({'session_id': 's', 'event_type': 'x'}));
    hub
        .openSession('sync')
        .receive(frame({'v': 2, 'type': 'hello', 'peerId': 'p'}));
    hub
        .openSession('blob')
        .receive(frame({'v': 1, 'type': 'chunk-req', 'addresses': []}));
    await pumpEventQueue();

    expect(syncDials.single.remotePeerId, 'sync');
    expect(blobDials.single.remotePeerId, 'blob');
    expect(realtime.single.remotePeerId, 'rt');
  });

  test('the plane classifiers never cross-claim each other', () {
    Uint8List frame(final Map<String, Object?> json) =>
        Uint8List.fromList(utf8.encode(jsonEncode(json)));
    final syncHello = frame({'v': 2, 'type': 'hello'});
    final chunkReq = frame({'v': 1, 'type': 'chunk-req'});
    final gesture = frame({'session_id': 's', 'event_type': 'pointerMove'});

    expect(looksLikeWorldSyncFrame(syncHello), isTrue);
    expect(looksLikeChunkFrame(syncHello), isFalse);
    expect(looksLikeChunkFrame(chunkReq), isTrue);
    expect(looksLikeWorldSyncFrame(chunkReq), isFalse);
    expect(looksLikeWorldSyncFrame(gesture), isFalse);
    expect(looksLikeChunkFrame(gesture), isFalse);
  });
}
