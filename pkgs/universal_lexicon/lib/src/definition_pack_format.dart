/// The DefinitionPack container, format version 1.
///
/// Layout (all integers little-endian):
///
/// ```text
/// header  (24 B): 'LXDF' | u32 version | u32 blockCount
///                 | u32 entryCount | u64 indexOffset
/// data        : blockCount independently compressed blocks,
///               back to back. A block is UTF-8 lines
///               `word \t partOfSpeech \t definition \n`
///               (partOfSpeech may be empty).
/// index       : blockCount × (u32 offset, u32 compressedLength)
///               then entryCount × (u32 fnv1a32(word), u32 blockId),
///               sorted by hash — the whole index is small enough
///               (~12 B/entry) to hold in memory.
/// ```
///
/// Lookup: hash the word → binary search the hash index (collisions
/// are legal, so block candidates are verified by exact word match) →
/// decompress ONE block through the reader's LRU cache.
library;

import 'dart:convert';
import 'dart:typed_data';

const List<int> definitionPackMagic = <int>[0x4C, 0x58, 0x44, 0x46]; // 'LXDF'
const int definitionPackVersion = 1;
const int definitionPackHeaderLength = 24;
const int definitionPackEntriesPerBlock = 64;

/// FNV-1a 32-bit over the UTF-8 bytes of the lowercased word.
int definitionWordHash(final String word) {
  var hash = 0x811C9DC5;
  for (final byte in utf8.encode(word.toLowerCase())) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

/// Writes the 24-byte header into [sink]; returns the header bytes so
/// the caller can patch `indexOffset` (u64 at byte 16) once the data
/// section length is known.
ByteData writeDefinitionPackHeader(
  final BytesBuilder sink, {
  required final int blockCount,
  required final int entryCount,
}) {
  final header = ByteData(definitionPackHeaderLength)
    ..setUint8(0, definitionPackMagic[0])
    ..setUint8(1, definitionPackMagic[1])
    ..setUint8(2, definitionPackMagic[2])
    ..setUint8(3, definitionPackMagic[3])
    ..setUint32(4, definitionPackVersion, Endian.little)
    ..setUint32(8, blockCount, Endian.little)
    ..setUint32(12, entryCount, Endian.little);
  sink.add(header.buffer.asUint8List());
  return header;
}
