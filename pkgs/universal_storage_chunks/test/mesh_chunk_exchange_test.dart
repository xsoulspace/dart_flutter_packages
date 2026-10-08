import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_storage_chunks/universal_storage_chunks.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

/// The fake pair's close does not propagate a done event to the peer's
/// inbound stream (by design — sessions die independently), so absorption
/// is observed through the store, never through serve() returning.
Future<void> _until(final Future<bool> Function() probe) async {
  for (var i = 0; i < 500; i++) {
    if (await probe()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition not reached within 5s');
}

void main() {
  test('fetch moves verified chunks from a serving peer into the sink',
      () async {
    final serverStore = MemoryChunkStore();
    final serverBlobs = ChunkedBlobStore(chunks: serverStore);
    final manifest = await serverBlobs.putBytes(
      List<int>.generate(200 * 1024, (i) => i % 251),
    );

    final pair = FakeMeshPair.paired();
    final clientSink = MemoryChunkStore();

    final clientSession = await pair.a.connect(
      const MeshPeerRecord(peerId: 'device-b', displayName: 'B'),
    );
    pair.b.incoming.listen((final session) {
      unawaited(MeshChunkExchange.serve(session: session, store: serverStore));
    });

    final received = await MeshChunkExchange.fetch(
      session: clientSession,
      addresses: manifest.chunks,
      sink: clientSink,
    );
    await clientSession.close();

    expect(received, manifest.chunks.length);

    // The fetched set materializes identically on the client side.
    final clientBlobs = ChunkedBlobStore(chunks: clientSink);
    final restored = await clientBlobs.getBytes(manifest);
    expect(restored.length, manifest.size);
  });

  test('a lying server yields absent chunks on the client, never bad bytes',
      () async {
    final serverStore = MemoryChunkStore();
    final serverBlobs = ChunkedBlobStore(chunks: serverStore);
    final manifest = await serverBlobs.putBytes(
      List<int>.generate(150 * 1024, (i) => i % 241),
    );

    // Disk rot / malicious rewrite, simulated one level up: the server's
    // GET answers tampered bytes for one victim address. The wire hash
    // check is the last line — the client must adopt nothing.
    final victim = manifest.chunks.first;
    final lying = _LyingStore(serverStore, victim, Uint8List(1024));

    final pair = FakeMeshPair.paired();
    final clientSink = MemoryChunkStore();
    final clientSession = await pair.a.connect(
      const MeshPeerRecord(peerId: 'device-b', displayName: 'B'),
    );
    pair.b.incoming.listen((final session) {
      unawaited(MeshChunkExchange.serve(session: session, store: lying));
    });

    final received = await MeshChunkExchange.fetch(
      session: clientSession,
      addresses: manifest.chunks,
      sink: clientSink,
    );
    await clientSession.close();

    expect(received, manifest.chunks.length - 1);
    expect(
      await clientSink.has(victim),
      isFalse,
      reason: 'tampered bytes must never be adopted under any address',
    );
  });

  test('push ships verified chunks over a dialed session; serve absorbs them',
      () async {
    final senderBlobs = ChunkedBlobStore(chunks: MemoryChunkStore());
    final manifest = await senderBlobs.putBytes(
      List<int>.generate(300 * 1024, (i) => (i * 7) % 256),
    );

    final pair = FakeMeshPair.paired();
    final receiverStore = MemoryChunkStore();
    pair.b.incoming.listen((final session) {
      unawaited(
        MeshChunkExchange.serve(session: session, store: receiverStore),
      );
    });

    final pusherSession = await pair.a.connect(
      const MeshPeerRecord(peerId: 'device-b', displayName: 'B'),
    );
    final sent = await MeshChunkExchange.push(
      session: pusherSession,
      addresses: manifest.chunks,
      store: senderBlobs.chunks,
    );
    await pusherSession.close();
    await _until(() => receiverStore.has(manifest.chunks.last));

    expect(sent, manifest.chunks.length);
    // The receiver assembles identical bytes — the dialer-only topology
    // shipped a blob with no second server.
    final receiverBlobs = ChunkedBlobStore(chunks: receiverStore);
    final restored = await receiverBlobs.getBytes(manifest);
    expect(restored.length, manifest.size);
  });

  test('serve PoP-rejects a pushed lie and keeps honest chunks flowing',
      () async {
    final senderStore = MemoryChunkStore();
    final senderBlobs = ChunkedBlobStore(chunks: senderStore);
    final manifest = await senderBlobs.putBytes(
      List<int>.generate(64 * 1024, (i) => i % 253),
    );
    final lie = List<int>.filled(1024, 0xAB);

    final pair = FakeMeshPair.paired();
    final receiverStore = MemoryChunkStore();
    pair.b.incoming.listen((final session) {
      unawaited(
        MeshChunkExchange.serve(session: session, store: receiverStore),
      );
    });

    final session = await pair.a.connect(
      const MeshPeerRecord(peerId: 'device-b', displayName: 'B'),
    );
    // A pushed chunk whose bytes do not hash to its address…
    await session.send(
      MeshChunkProtocol.encode({
        'v': 1,
        'type': MeshChunkExchange.chunkType,
        'address': manifest.chunks.first,
        'bytes': base64Encode(lie),
      }),
    );
    // …followed by an honest push of the real chunks.
    final sent = await MeshChunkExchange.push(
      session: session,
      addresses: manifest.chunks,
      store: senderBlobs.chunks,
    );
    await session.close();
    await _until(() => receiverStore.has(manifest.chunks.first));

    expect(sent, manifest.chunks.length);
    expect(
      await receiverStore.has(manifest.chunks.first),
      isTrue,
      reason: 'the honest push filled the gap the lie left',
    );
    final receiverBlobs = ChunkedBlobStore(chunks: receiverStore);
    expect((await receiverBlobs.getBytes(manifest)).length, manifest.size);
  });
}

/// A store that answers one victim address with tampered bytes — the
/// adversary the on-receipt hash check exists for.
final class _LyingStore implements ChunkStore {
  _LyingStore(this._inner, this._victimAddress, this._lie);

  final ChunkStore _inner;
  final String _victimAddress;
  final List<int> _lie;

  @override
  Future<void> put(final List<int> bytes, {required final String address}) =>
      _inner.put(bytes, address: address);

  @override
  Future<bool> has(final String address) => _inner.has(address);

  @override
  Future<Uint8List?> get(final String address) async {
    if (address == _victimAddress) return Uint8List.fromList(_lie);
    return _inner.get(address);
  }
}
