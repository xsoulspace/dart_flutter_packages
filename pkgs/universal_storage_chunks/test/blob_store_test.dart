import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_chunks/conformance.dart';
import 'package:universal_storage_chunks/universal_storage_chunks.dart';

void main() {
  group('MemoryChunkStore', () {
    chunkStoreConformanceTests(
      'MemoryChunkStore',
      create: () async => MemoryChunkStore(),
    );
  });

  group('FileChunkStore', () {
    chunkStoreConformanceTests('FileChunkStore', create: () async {
      final dir = await Directory.systemTemp.createTemp('chunks_conf_');
      addTearDown(() => dir.delete(recursive: true));
      return FileChunkStore(dir.path);
    });
  });

  group('ChunkedBlobStore', () {
    late MemoryChunkStore store;
    late ChunkedBlobStore blobs;

    setUp(() {
      store = MemoryChunkStore();
      blobs = ChunkedBlobStore(chunks: store);
    });

    test('putBytes → getBytes round-trips with root verification', () async {
      final bytes = List<int>.generate(200 * 1024, (i) => i % 251);
      final manifest = await blobs.putBytes(bytes, mime: 'image/png');

      expect(manifest.size, bytes.length);
      expect(manifest.mime, 'image/png');
      expect(manifest.chunks, isNotEmpty);

      final restored = await blobs.getBytes(manifest);
      expect(restored, bytes);
    });

    test('dedupe: identical content shares every chunk address', () async {
      final bytes = List<int>.generate(150 * 1024, (i) => (i * 31) % 256);
      final first = await blobs.putBytes(bytes);
      final countAfterFirst = store.length;
      final second = await blobs.putBytes(bytes);

      expect(second.root, first.root);
      expect(second.chunks, first.chunks);
      expect(store.length, countAfterFirst,
          reason: 'idempotent puts must not add chunks');
    });

    test('edit locality at the blob level: a small edit adds few chunks',
        () async {
      final bytes = List<int>.generate(300 * 1024, (i) => i % 199);
      final before = await blobs.putBytes(bytes);
      final countBefore = store.length;

      final edited = [...bytes]..[150 * 1024] ^= 0xFF;
      final after = await blobs.putBytes(edited);

      expect(after.root, isNot(before.root));
      expect(
        store.length - countBefore,
        lessThanOrEqualTo(4),
        reason: 'content-defined cuts: only chunks near the edit re-form',
      );
      // And the OLD version still materializes (LWW losers stay whole).
      expect(await blobs.getBytes(before), bytes);
    });

    test('missing chunks are detected and named', () async {
      final manifest = await blobs.putBytes(
        List<int>.generate(100 * 1024, (i) => i % 251),
      );
      // Simulate a partial replica: forget the last chunk address.
      final partial = ChunkManifest(
        root: manifest.root,
        size: manifest.size,
        chunks: manifest.chunks,
      );
      final missing = await partial.missingChunks(MemoryChunkStore());
      expect(missing, partial.chunks, reason: 'an empty store lacks all');
    });

    test('getBytes throws MissingChunksException on an incomplete store',
        () async {
      final bytes = List<int>.generate(200 * 1024, (i) => i % 241);
      final manifest = await blobs.putBytes(bytes);
      final emptyStore = ChunkedBlobStore(chunks: MemoryChunkStore());
      await expectLater(
        emptyStore.getBytes(manifest),
        throwsA(isA<MissingChunksException>()),
      );
    });

    test('progressive plan walks leading chunks first (mip order)', () async {
      final bytes = List<int>.generate(300 * 1024, (i) => i % 233);
      final manifest = await blobs.putBytes(bytes);
      final plan = blobs.planProgressive(manifest);

      expect(plan.isProgressive, isTrue);
      expect(plan.chunkPrefixes.first, [manifest.chunks.first]);
      expect(plan.chunkPrefixes.last, manifest.chunks);
      for (var i = 1; i < plan.chunkPrefixes.length; i++) {
        expect(
          plan.chunkPrefixes[i].length,
          plan.chunkPrefixes[i - 1].length + 1,
        );
      }
    });

    test('manifest json round-trip (the kernel-doc value shape)', () async {
      final bytes = List<int>.generate(80 * 1024, (i) => i % 229);
      final manifest = await blobs.putBytes(bytes, mime: 'model/gltf-binary');
      final restored = ChunkManifest.tryFromJson(manifest.toJson());
      expect(restored, isNotNull);
      expect(restored!.root, manifest.root);
      expect(restored.chunks, manifest.chunks);
      expect(restored.mime, 'model/gltf-binary');
      expect(ChunkManifest.tryFromJson('not a map'), isNull);
      expect(ChunkManifest.tryFromJson({'nope': 1}), isNull);
    });

    test('reachableAddresses unions manifests (local-GC helper)', () async {
      final a = await blobs.putBytes(List<int>.generate(70 * 1024, (i) => i));
      final b = await blobs.putBytes(List<int>.generate(70 * 1024, (i) => i * 3));
      final reachable = await blobs.reachableAddresses([a, b]);
      expect(reachable, {...a.chunks, ...b.chunks});
    });
  });
}
