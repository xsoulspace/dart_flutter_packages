import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_storage_chunks/universal_storage_chunks.dart';

void main() {
  const chunker = ContentDefinedChunker();

  Uint8List payload(final int size, {final int seed = 7}) {
    final random = Random(seed);
    return Uint8List.fromList(
      List<int>.generate(size, (_) => random.nextInt(256)),
    );
  }

  group('ContentDefinedChunker', () {
    test('empty input yields zero chunks', () {
      expect(chunker.chunk(const []), isEmpty);
    });

    test('deterministic: same bytes → same slices, any number of runs', () {
      final bytes = payload(300 * 1024);
      final first = chunker.chunk(bytes);
      final second = chunker.chunk(bytes);
      expect(first, second);
      expect(first, isNotEmpty);
    });

    test('offset independence: a prefix shift preserves the tail cuts', () {
      // The content-defined law: chunk boundaries depend on CONTENT, not
      // position. Append bytes to the front; all chunks after the first
      // boundary must re-appear identically.
      final original = payload(400 * 1024);
      final shifted = [...payload(64 * 1024, seed: 99), ...original];
      final originalSlices = chunker.chunk(original).map((final s) {
        // Boundaries by content digest of the region instead of offsets.
        return chunkAddress(original.sublist(s.start, s.end));
      }).toSet();
      final shiftedSlices = chunker.chunk(shifted).map((final s) {
        return chunkAddress(shifted.sublist(s.start, s.end));
      }).toSet();
      // The shared content must dominate: most original chunk addresses
      // re-appear in the shifted cut.
      final shared = originalSlices.intersection(shiftedSlices);
      expect(shared.length, greaterThan(originalSlices.length * 0.6));
    });

    test('edit locality: one changed byte keeps most chunk addresses', () {
      final original = payload(300 * 1024);
      final edited = Uint8List.fromList(original);
      edited[edited.length ~/ 2] ^= 0xFF;
      Set<String> addresses(final Uint8List data) => chunker
          .chunk(data)
          .map((final s) => chunkAddress(data.sublist(s.start, s.end)))
          .toSet();
      final before = addresses(original);
      final after = addresses(edited);
      final shared = before.intersection(after);
      expect(
        shared.length,
        greaterThan(before.length * 0.5),
        reason: 'a single-byte edit must not invalidate the whole set',
      );
    });

    test('bounds: every slice within [minSize, maxSize] (except the tail)', () {
      final bytes = payload(1024 * 1024);
      for (final slice in chunker.chunk(bytes)) {
        expect(slice.length, lessThanOrEqualTo(chunker.maxSize));
        final isTail = slice.end == bytes.length;
        if (!isTail) {
          expect(slice.length, greaterThanOrEqualTo(chunker.minSize));
        }
      }
    });

    test('covers the input exactly, no gaps or overlaps', () {
      final bytes = payload(500 * 1024);
      final slices = chunker.chunk(bytes);
      expect(slices.first.start, 0);
      expect(slices.last.end, bytes.length);
      for (var i = 1; i < slices.length; i++) {
        expect(slices[i].start, slices[i - 1].end);
      }
    });
  });

  group('ChunkSlice', () {
    test('length and equality', () {
      const a = ChunkSlice(start: 0, end: 10);
      expect(a.length, 10);
      expect(a, const ChunkSlice(start: 0, end: 10));
    });
  });
}
