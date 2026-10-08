import 'dart:typed_data';

/// Content-defined chunking via gear-hash boundary markers (ADR 0042 §1).
///
/// Same bytes → same chunks regardless of offsets; a small edit re-chunks
/// only near the edit, so unchanged chunks keep their addresses and dedupe
/// across re-exports. Parameters adopted from ADR 0042 (Lore-derived):
/// 32 KiB floor, 64 KiB average, 256 KiB ceiling.
///
/// This is the simple single-mask cut rule; FastCDC's dual-mask
/// normalization is a refinement that only moves boundaries — the address
/// set changes, never the guarantees (determinism + edit locality).
final class ContentDefinedChunker {
  const ContentDefinedChunker({
    this.minSize = 32 * 1024,
    this.averageSize = 64 * 1024,
    this.maxSize = 256 * 1024,
  });

  /// No chunk smaller than this (boundary markers are ignored before it).
  final int minSize;

  /// The boundary-marker density target: `log2` of this is the mask width.
  final int averageSize;

  /// Hard cut regardless of markers.
  final int maxSize;

  /// Deterministic 64-bit gear table (fixed-seed LCG; identical on every
  /// platform and run — chunk addresses must never drift).
  static final Uint64List _gear = _buildGearTable();

  static Uint64List _buildGearTable() {
    final table = Uint64List(256);
    var state = 0x9e3779b97f4a7c15;
    for (var i = 0; i < 256; i++) {
      // SplitMix64 finalizer over a fixed golden-ratio step.
      state += 0x9e3779b97f4a7c15;
      var z = state;
      z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9;
      z = (z ^ (z >> 27)) * 0x94d049bb133111eb;
      table[i] = z ^ (z >> 31);
    }
    return table;
  }

  /// Cuts [bytes] into content-defined slices (start/end offsets).
  List<ChunkSlice> chunk(final List<int> bytes) {
    final slices = <ChunkSlice>[];
    final length = bytes.length;
    if (length == 0) return slices;
    final mask = (1 << (_log2(averageSize))) - 1;
    var start = 0;
    var hash = 0;
    var i = 0;
    while (start < length) {
      final hardEnd = start + maxSize < length ? start + maxSize : length;
      var end = hardEnd;
      // Boundary search: markers only count after the floor.
      for (var j = start + minSize; j < hardEnd; j++) {
        hash = ((hash << 1) + _gear[bytes[j] & 0xff]) & _mask64;
        if (hash & mask == 0) {
          end = j + 1;
          break;
        }
      }
      slices.add(ChunkSlice(start: start, end: end));
      start = end;
      hash = 0;
    }
    return slices;
  }

  static const _mask64 = 0xFFFFFFFFFFFFFFFF;

  static int _log2(final int value) {
    var bits = 0;
    var v = value;
    while (v > 1) {
      v >>= 1;
      bits++;
    }
    return bits;
  }
}

/// One cut region of the input, `bytes[start:end]`.
final class ChunkSlice {
  const ChunkSlice({required this.start, required this.end});

  final int start;
  final int end;

  int get length => end - start;

  @override
  bool operator ==(final Object other) =>
      other is ChunkSlice && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'ChunkSlice($start..$end)';
}
