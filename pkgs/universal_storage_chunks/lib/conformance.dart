/// Behavioral conformance suite for [ChunkStore] implementations
/// (ADR 0042 §4).
///
/// Lives beside the types (a conformance package import here would form a
/// pub cycle: implementations necessarily depend on this package). Any
/// store — the shipped memory/file pair, a game's asset cache, a future
/// packfile store — opts in with one call:
///
/// ```dart
/// void main() {
///   chunkStoreConformanceTests(
///     'MyChunkStore',
///     create: () async => MyChunkStore(),
///   );
/// }
/// ```
library;

import 'package:test/test.dart';

import 'src/chunk_store.dart';

/// Factory producing a fresh, empty store per scenario.
typedef ChunkStoreFactory = Future<ChunkStore> Function();

/// Runs the full chunk-store conformance suite against a factory.
void chunkStoreConformanceTests(
  final String storeName, {
  required final ChunkStoreFactory create,
}) {
  const kilobyte = 1024;
  group('$storeName conformance', () {
    late ChunkStore store;

    setUp(() async {
      store = await create();
    });

    test('put → has → get round-trips bytes', () async {
      final bytes = List<int>.generate(4 * kilobyte, (i) => i % 251);
      final address = chunkAddress(bytes);
      await store.put(bytes, address: address);
      expect(await store.has(address), isTrue);
      expect(await store.get(address), bytes);
    });

    test('put is idempotent (chunks are immutable)', () async {
      final bytes = List<int>.generate(2 * kilobyte, (i) => i % 199);
      final address = chunkAddress(bytes);
      await store.put(bytes, address: address);
      await store.put(bytes, address: address);
      expect(await store.get(address), bytes);
    });

    test('get of a missing address is null', () async {
      const impossible =
          '0000000000000000000000000000000000000000000000000000000000000000';
      expect(
        await store.get(impossible),
        isNull,
        reason: '64 hex zeroes is a valid-shaped, near-impossible address',
      );
    });

    test('bytes that do not hash to their address are never served '
        '(proof of possession law)', () async {
      final bytes = List<int>.generate(kilobyte, (i) => i % 173);
      // Stored under a DIFFERENT address than its own hash: corruption,
      // a torn write, or a lying peer — the store must report absent,
      // never serve.
      final wrongAddress = 'f' * 64;
      await store.put(bytes, address: wrongAddress);
      expect(await store.get(wrongAddress), isNull);
    });

    test('a realistic large payload round-trips', () async {
      final bytes = List<int>.generate(512 * kilobyte, (i) => (i * 7) % 256);
      final address = chunkAddress(bytes);
      await store.put(bytes, address: address);
      expect(await store.get(address), bytes);
    });
  });
}
