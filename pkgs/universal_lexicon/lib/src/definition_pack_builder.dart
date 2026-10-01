import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'block_codec.dart';
import 'definition_entry.dart';
import 'definition_pack_format.dart';
import 'zlib_block_codec.dart';

/// Builds a DefinitionPack (format v1) from definition entries.
///
/// Entries are sorted by word first, so every sense of a word lands in
/// the SAME block (one decompression serves all senses), then chunked
/// into [entriesPerBlock] blocks. The hash index is sorted afterwards,
/// which is what makes lookups a binary search.
final class DefinitionPackBuilder {
  DefinitionPackBuilder({
    this.entriesPerBlock = definitionPackEntriesPerBlock,
    this.codec = const ZLibBlockCodec(),
  });

  final int entriesPerBlock;
  final BlockCodec codec;

  Uint8List build(final Iterable<DefinitionEntry> entries) {
    final sorted = entries.toList(growable: false)
      ..sort((final a, final b) => a.word.compareTo(b.word));
    if (sorted.isEmpty) {
      throw ArgumentError.value(entries, 'entries', 'must not be empty');
    }
    if (entriesPerBlock <= 0) {
      throw ArgumentError.value(
        entriesPerBlock,
        'entriesPerBlock',
        'must be positive',
      );
    }

    final sink = BytesBuilder(copy: false);
    final header = writeDefinitionPackHeader(
      sink,
      blockCount: 0,
      entryCount: sorted.length,
    );

    final blockSpans = <int>[]; // offset, length pairs
    final hashIndex = <(int, int)>[]; // (wordHash, blockId)

    for (var start = 0; start < sorted.length; start += entriesPerBlock) {
      final end = math.min(start + entriesPerBlock, sorted.length);
      final chunk = sorted.sublist(start, end);
      final payload = StringBuffer();
      for (final entry in chunk) {
        payload
          ..write(entry.word)
          ..write('\t')
          ..write(entry.partOfSpeech ?? '')
          ..write('\t')
          ..write(entry.definition)
          ..write('\n');
      }
      final compressed = codec.encode(utf8.encode(payload.toString()));
      final blockId = blockSpans.length ~/ 2;
      blockSpans..add(sink.length)..add(compressed.length);
      sink.add(compressed);
      for (final entry in chunk) {
        hashIndex.add((definitionWordHash(entry.word), blockId));
      }
    }
    hashIndex.sort((final a, final b) => a.$1.compareTo(b.$1));
    final indexOffset = sink.length;
    final index = ByteData((blockSpans.length + hashIndex.length * 2) * 4);
    for (var i = 0; i < blockSpans.length; i++) {
      index.setUint32(i * 4, blockSpans[i], Endian.little);
    }
    var cursor = blockSpans.length * 4;
    for (final (hash, blockId) in hashIndex) {
      index
        ..setUint32(cursor, hash, Endian.little)
        ..setUint32(cursor + 4, blockId, Endian.little);
      cursor += 8;
    }
    sink.add(index.buffer.asUint8List());

    // Patch the deferred header fields: the real block count and the
    // index offset (the index follows the data section).
    header
      ..setUint32(8, blockSpans.length ~/ 2, Endian.little)
      ..setUint64(16, indexOffset, Endian.little);
    return sink.toBytes();
  }
}
