import 'dart:convert';
import 'dart:io';

/// GPT-2-style byte-level BPE loaded from the checkpoint's
/// `tokenizer/tokenizer.json` — the tokenizer family the checkpoint ships
/// (ModernBERT/OLMo: NFC normalizer, ByteLevel pre-tokenizer with the GPT-2
/// split regex, BPE merges, added tokens).
///
/// The normalizer (NFC) is injected: pure Dart has no Unicode normalization,
/// and the native runtime exposes one (`mlx_native_normalize`). ASCII-only
/// callers work without it; multilingual text needs it for token parity.
final class LayaByteLevelTokenizer {
  LayaByteLevelTokenizer._(
    this._vocab,
    this._ranks,
    this._added,
    this.clsTokenId,
    this.sepTokenId,
    this.padTokenId,
    this.maskTokenId,
    this.maskLabel,
    this._nfc,
  );

  /// Loads `tokenizer.json` + `tokenizer_config.json` from
  /// [modelDir]/tokenizer.
  factory LayaByteLevelTokenizer.load(
    final String modelDir, {
    final String Function(String)? nfc,
  }) {
    final raw =
        jsonDecode(File('$modelDir/tokenizer/tokenizer.json').readAsStringSync());
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('tokenizer.json: expected an object');
    }
    final model = raw['model'] as Map<String, dynamic>;
    if (model['type'] != 'BPE') {
      throw FormatException(
        'tokenizer.json: unsupported model type ${model['type']} (expected BPE)',
      );
    }
    final vocab = <String, int>{};
    (model['vocab'] as Map).forEach((final key, final value) {
      vocab['$key'] = value as int;
    });
    final ranks = <String, int>{};
    final merges = model['merges'] as List;
    for (var i = 0; i < merges.length; i++) {
      final entry = merges[i];
      // Newer tokenizers serialize pairs as [a, b] arrays; older as "a b".
      final parts = entry is List
          ? ['${entry[0]}', '${entry[1]}']
          : '$entry'.split(' ');
      if (parts.length != 2) {
        throw FormatException('tokenizer.json: malformed merge "$entry"');
      }
      ranks['${parts[0]} ${parts[1]}'] = i;
    }
    final added = <String, int>{};
    for (final token in (raw['added_tokens'] as List? ?? const [])) {
      final entry = token as Map;
      added['${entry['content']}'] = entry['id'] as int;
    }
    final config =
        jsonDecode(File('$modelDir/tokenizer/tokenizer_config.json').readAsStringSync());
    String? contentOf(final Object? token) => token is Map
        ? (token['content'] ?? token['<mask>']) as String?
        : token as String?;
    final maskContent = contentOf(config['mask_token']);
    int resolve(final String? content) {
      if (content == null) return -1;
      return added[content] ?? vocab[content] ?? -1;
    }

    return LayaByteLevelTokenizer._(
      vocab,
      ranks,
      added,
      resolve(contentOf(config['cls_token'])),
      resolve(contentOf(config['sep_token'])),
      resolve(contentOf(config['pad_token'])),
      resolve(maskContent),
      maskContent ?? '[MASK]',
      nfc,
    );
  }

  final Map<String, int> _vocab;
  final Map<String, int> _ranks;
  final Map<String, int> _added;
  final String Function(String)? _nfc;

  final int clsTokenId;
  final int sepTokenId;
  final int padTokenId;
  final int maskTokenId;

  /// The mask token's surface form (`[MASK]`) — the prompt builder replaces
  /// literal mask text in inputs, matching the reference runtimes.
  final String maskLabel;

  final Map<String, List<int>> _cache = <String, List<int>>{};

  /// The GPT-2 split regex (ByteLevel pre-tokenizer, use_regex).
  static final RegExp _split = RegExp(
    r"'s|'t|'re|'ve|'m|'ll|'d| ?\p{L}+| ?\p{N}+| ?[^\s\p{L}\p{N}]+|\s+(?!\S)|\s+",
    unicode: true,
  );

  static final List<String> _byteToUnicode = _buildByteToUnicode();

  static List<String> _buildByteToUnicode() {
    final bytes = <int>[
      for (var b = 0x21; b <= 0x7e; b++) b,
      for (var b = 0xa1; b <= 0xac; b++) b,
      for (var b = 0xae; b <= 0xff; b++) b,
    ];
    final mapped = bytes.toList();
    var n = 0;
    for (var b = 0; b < 256; b++) {
      if (!bytes.contains(b)) {
        bytes.add(b);
        mapped.add(256 + n);
        n++;
      }
    }
    // Indexed BY BYTE VALUE — bytes[] is not position-aligned with values.
    final table = List<String>.filled(256, '');
    for (var i = 0; i < 256; i++) {
      table[bytes[i]] = String.fromCharCode(mapped[i]);
    }
    return table;
  }

  /// Encodes [text] without special tokens (the runtime always passes
  /// `add_special_tokens=False`; CLS/SEP are added by the prompt builder).
  List<int> encode(final String text) {
    final normalized = _nfc != null ? _nfc(text) : text;
    final ids = <int>[];
    var index = 0;
    while (index < normalized.length) {
      final added = _matchAdded(normalized, index);
      if (added != null) {
        ids.add(added.$2);
        index += added.$1.length;
        continue;
      }
      final segment = _matchPlain(normalized, index);
      ids.addAll(_encodePlain(segment));
      index += segment.length;
    }
    return ids;
  }

  /// Longest added-token match at [index], else null.
  (String, int)? _matchAdded(final String text, final int index) {
    (String, int)? best;
    for (final entry in _added.entries) {
      final content = entry.key;
      if (content.isNotEmpty && text.startsWith(content, index)) {
        if (best == null || content.length > best.$1.length) {
          best = (content, entry.value);
        }
      }
    }
    return best;
  }

  /// The next plain segment: one regex pre-token when one matches at
  /// [index], else a single character (unmatched text cannot be encoded).
  String _matchPlain(final String text, final int index) {
    final match = _split.matchAsPrefix(text, index);
    if (match != null) return text.substring(index, match.end);
    return text.substring(index, index + 1);
  }

  List<int> _encodePlain(final String piece) {
    final cached = _cache[piece];
    if (cached != null) return cached;
    final symbols = StringBuffer();
    for (final byte in utf8.encode(piece)) {
      symbols.write(_byteToUnicode[byte]);
    }
    var parts = symbols.toString().split('');
    // Lowest-rank pair merge, repeated (GPT-2 BPE).
    while (parts.length > 1) {
      var bestRank = -1;
      var bestIndex = -1;
      for (var i = 0; i < parts.length - 1; i++) {
        final rank = _ranks['${parts[i]} ${parts[i + 1]}'];
        if (rank != null && (bestRank == -1 || rank < bestRank)) {
          bestRank = rank;
          bestIndex = i;
        }
      }
      if (bestIndex == -1) break;
      parts = [
        ...parts.sublist(0, bestIndex),
        '${parts[bestIndex]}${parts[bestIndex + 1]}',
        ...parts.sublist(bestIndex + 2),
      ];
    }
    final ids = [
      for (final part in parts)
        _vocab[part] ??
            (throw FormatException('tokenizer: unknown BPE token "$part"')),
    ];
    _cache[piece] = ids;
    return ids;
  }
}
