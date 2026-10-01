/// The LexiconPack container, format version 1 — the fast-boot word +
/// frequency pack (the whole vocabulary the keyboard decodes against).
///
/// Layout (little-endian):
///
/// ```text
/// header (16 B): 'LXLP' | u32 version | u32 wordCount | u32 byteLength
/// body       : ONE zlib-compressed UTF-8 section of sorted lines
///              `word \t quantizedFrequency \n`
///              (frequency quantized 0..1000; 1000 = most frequent)
/// ```
///
/// Unlike [DefinitionPack] there is no block index: a lexicon is loaded
/// ONCE at boot into a [ListLexicon] (a 10k-word pack decompresses in
/// single-digit ms) and then answers queries from memory. Words are
/// stored sorted, so the rebuilt lexicon keeps binary-search queries.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'block_codec.dart';
import 'list_lexicon.dart';
import 'zlib_block_codec.dart';

const List<int> lexiconPackMagic = <int>[0x4C, 0x58, 0x4C, 0x50]; // 'LXLP'
const int lexiconPackVersion = 1;
const int lexiconPackHeaderLength = 16;
const int lexiconPackMaxFrequency = 1000;

/// Builds a LexiconPack from words + normalized frequencies.
final class LexiconPackBuilder {
  LexiconPackBuilder({this.codec = const ZLibBlockCodec()});

  final BlockCodec codec;

  Uint8List build(final Map<String, double> frequencies) {
    if (frequencies.isEmpty) {
      throw ArgumentError.value(
        frequencies,
        'frequencies',
        'must not be empty',
      );
    }
    final words = frequencies.keys.toList()..sort();
    final payload = StringBuffer();
    for (final word in words) {
      final frequency = (frequencies[word] ?? 0.0).clamp(0.0, 1.0);
      payload
        ..write(word)
        ..write('\t')
        ..write((frequency * lexiconPackMaxFrequency).round())
        ..write('\n');
    }
    final compressed = codec.encode(utf8.encode(payload.toString()));

    final header = ByteData(lexiconPackHeaderLength)
      ..setUint8(0, lexiconPackMagic[0])
      ..setUint8(1, lexiconPackMagic[1])
      ..setUint8(2, lexiconPackMagic[2])
      ..setUint8(3, lexiconPackMagic[3])
      ..setUint32(4, lexiconPackVersion, Endian.little)
      ..setUint32(8, words.length, Endian.little)
      ..setUint32(12, compressed.length, Endian.little);

    final sink = BytesBuilder(copy: false)
      ..add(header.buffer.asUint8List())
      ..add(compressed);
    return sink.toBytes();
  }
}

/// Reads a LexiconPack into a [ListLexicon] — one decompression at
/// boot, queries from memory afterwards.
final class LexiconPack {
  LexiconPack(this._bytes) {
    if (_bytes.length < lexiconPackHeaderLength) {
      throw ArgumentError('not a LexiconPack: too short');
    }
    final header = ByteData.sublistView(
      _bytes,
      0,
      lexiconPackHeaderLength,
    );
    for (var i = 0; i < 4; i++) {
      if (header.getUint8(i) != lexiconPackMagic[i]) {
        throw ArgumentError('not a LexiconPack: bad magic');
      }
    }
    final version = header.getUint32(4, Endian.little);
    if (version != lexiconPackVersion) {
      throw ArgumentError('unsupported LexiconPack version: $version');
    }
    wordCount = header.getUint32(8, Endian.little);
    final bodyLength = header.getUint32(12, Endian.little);
    final body = _bytes.sublist(
      lexiconPackHeaderLength,
      lexiconPackHeaderLength + bodyLength,
    );
    _frequencies = _parse(utf8.decode(const ZLibBlockCodec().decode(body)));
  }

  final Uint8List _bytes;
  late final int wordCount;
  late final Map<String, double> _frequencies;

  /// The decoded words — the caller feeds this straight into
  /// [ListLexicon].
  Map<String, double> get frequencies => Map.unmodifiable(_frequencies);

  ListLexicon toLexicon() => ListLexicon(
    words: _frequencies.keys,
    frequencies: _frequencies,
  );

  Map<String, double> _parse(final String text) {
    final frequencies = <String, double>{};
    for (final line in text.split('\n')) {
      if (line.isEmpty) continue;
      final tab = line.indexOf('\t');
      if (tab <= 0) continue;
      final quantized = int.tryParse(line.substring(tab + 1)) ?? 0;
      frequencies[line.substring(0, tab)] =
          quantized / lexiconPackMaxFrequency;
    }
    return frequencies;
  }
}
