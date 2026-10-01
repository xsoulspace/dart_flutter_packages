import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'block_codec.dart';
import 'definition_entry.dart';
import 'definition_pack_format.dart';
import 'definition_store.dart';
import 'zlib_block_codec.dart';

/// Reads a DefinitionPack (format v1, built by [DefinitionPackBuilder])
/// with a CONSTANT small memory footprint:
///
/// - the caller holds the COMPRESSED file bytes (a 50k-entry pack is
///   ~2 MB) — often memory-mapped or loaded lazily by the app layer;
/// - the hash index (~12 B/entry) is parsed eagerly;
/// - blocks are decompressed ONE at a time through an LRU cache of
///   [maxCachedBlocks]; a lookup touches a few KB, never the pack.
///
/// No network, no server, no full-dictionary load — by construction.
final class DefinitionPack implements DefinitionStore {
  DefinitionPack(
    this._bytes, {
    this.maxCachedBlocks = 4,
    this.codec = const ZLibBlockCodec(),
  }) {
    if (_bytes.length < definitionPackHeaderLength) {
      throw ArgumentError('not a DefinitionPack: too short');
    }
    final header = ByteData.sublistView(
      _bytes,
      0,
      definitionPackHeaderLength,
    );
    for (var i = 0; i < 4; i++) {
      if (header.getUint8(i) != definitionPackMagic[i]) {
        throw ArgumentError('not a DefinitionPack: bad magic');
      }
    }
    final version = header.getUint32(4, Endian.little);
    if (version != definitionPackVersion) {
      throw ArgumentError('unsupported DefinitionPack version: $version');
    }
    blockCount = header.getUint32(8, Endian.little);
    entryCount = header.getUint32(12, Endian.little);
    final indexOffset = header.getUint64(16, Endian.little);

    final index = ByteData.sublistView(
      _bytes,
      indexOffset,
      _bytes.length,
    );
    var cursor = blockCount * 8;
    for (var i = 0; i < blockCount; i++) {
      _blockSpans.add(
        (
          index.getUint32(i * 8, Endian.little),
          index.getUint32(i * 8 + 4, Endian.little),
        ),
      );
    }
    for (var i = 0; i < entryCount; i++) {
      _hashIndex.add(
        (
          index.getUint32(cursor, Endian.little),
          index.getUint32(cursor + 4, Endian.little),
        ),
      );
      cursor += 8;
    }
  }

  final Uint8List _bytes;
  final BlockCodec codec;

  /// Parsed blocks kept resident (LRU). Four 64-entry blocks ≈ 30 KB.
  final int maxCachedBlocks;

  late final int blockCount;
  late final int entryCount;
  final List<(int, int)> _blockSpans = <(int, int)>[];
  final List<(int, int)> _hashIndex = <(int, int)>[]; // sorted by hash
  final LinkedHashMap<int, List<String>> _blockCache =
      LinkedHashMap<int, List<String>>();

  @override
  List<DefinitionEntry> lookup(final String word) {
    final probe = word.toLowerCase();
    final hash = definitionWordHash(probe);
    // Hash collisions are legal: gather every index entry with this
    // hash, decompress their blocks, and let the exact word match
    // decide.
    final first = _lowerBound(hash);
    final blocks = <int>{};
    for (var i = first; i < _hashIndex.length && _hashIndex[i].$1 == hash;
        i++) {
      blocks.add(_hashIndex[i].$2);
    }
    final matches = <DefinitionEntry>[];
    for (final blockId in blocks) {
      for (final line in _block(blockId)) {
        final fields = line.split('\t');
        if (fields.length >= 3 && fields[0] == probe) {
          matches.add(
            DefinitionEntry(
              word: fields[0],
              partOfSpeech: fields[1].isEmpty ? null : fields[1],
              definition: fields.sublist(2).join('\t'),
            ),
          );
        }
      }
    }
    matches.sort(
      (final a, final b) =>
          (a.partOfSpeech ?? '').compareTo(b.partOfSpeech ?? ''),
    );
    return matches;
  }

  @override
  String? definition(final String word) {
    final matches = lookup(word);
    return matches.isEmpty ? null : matches.first.definition;
  }

  /// Every entry in the pack, block-ordered — the boot-time bulk read
  /// for in-memory consumers. One decompression per block.
  List<DefinitionEntry> readAll() {
    final entries = <DefinitionEntry>[];
    for (var blockId = 0; blockId < blockCount; blockId++) {
      for (final line in _block(blockId)) {
        final fields = line.split('\t');
        if (fields.length < 3) continue;
        entries.add(
          DefinitionEntry(
            word: fields[0],
            partOfSpeech: fields[1].isEmpty ? null : fields[1],
            definition: fields.sublist(2).join('\t'),
          ),
        );
      }
    }
    return entries;
  }

  /// Number of blocks currently resident — the test seam for the LRU.
  @visibleForTesting
  int get cachedBlockCount => _blockCache.length;

  List<String> _block(final int blockId) {
    final cached = _blockCache.remove(blockId);
    if (cached != null) {
      _blockCache[blockId] = cached; // touch = move to most-recent
      return cached;
    }
    final (offset, length) = _blockSpans[blockId];
    final text = utf8.decode(
      codec.decode(_bytes.sublist(offset, offset + length)),
    );
    final lines = text.split('\n')..removeLast(); // trailing newline
    _blockCache[blockId] = lines;
    while (_blockCache.length > maxCachedBlocks) {
      _blockCache.remove(_blockCache.keys.first); // evict least-recent
    }
    return lines;
  }

  int _lowerBound(final int hash) {
    var lo = 0;
    var hi = _hashIndex.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_hashIndex[mid].$1 < hash) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}
