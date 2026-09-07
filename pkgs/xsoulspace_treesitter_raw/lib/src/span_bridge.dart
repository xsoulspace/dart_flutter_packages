// ignore_for_file: lines_longer_as_80_chars

/// ADR 0035 §8 item 2 — the span bridge, written ONCE and tested with
/// multibyte golden tests (emoji + CJK): tree-sitter yields UTF-8 BYTE
/// offsets; `package:source_span` and Dart strings run on UTF-16 code
/// units. One untested conversion here is the classic silent corruption —
/// byte offsets used as code-unit offsets slice multibyte sources wrong.
///
/// UNIT DISCIPLINE (pinned):
/// - The meaning-tree `span_start` / `span_end` props remain UTF-8 BYTE
///   offsets (the fs span reader seeks the file in bytes) — tree-sitter
///   offsets plug in DIRECTLY, no conversion on that path.
/// - `package:source_span` projections (zoom clamps, error rendering)
///   convert through [Utf8Utf16SpanBridge] ONLY. Never index a Dart string
///   with a byte offset; never seek a file with a code-unit offset.
library;

import 'package:source_span/source_span.dart';

import 'source_parser.dart';

/// Converts UTF-8 byte offsets ↔ UTF-16 Dart code-unit offsets for ONE
/// source string, and projects tree spans onto `SourceSpan`s.
class Utf8Utf16SpanBridge {
  Utf8Utf16SpanBridge(String source) : _file = SourceFile.fromString(source) {
    // Rune-start index tables: parallel arrays over the decoded string's
    // runes — cuStarts[k] = code-unit index of rune k, byteStarts[k] = its
    // UTF-8 byte offset. Surrogate pairs count as 2 code units / 4 bytes;
    // BMP non-ASCII as 1 code unit / 2–3 bytes — the corruption cases.
    final units = <int>[];
    final bytes = <int>[];
    var byte = 0;
    var cu = 0;
    for (final rune in source.runes) {
      units.add(cu);
      bytes.add(byte);
      final len = rune < 0x80
          ? 1
          : rune < 0x800
          ? 2
          : rune < 0x10000
          ? 3
          : 4;
      byte += len;
      cu += rune < 0x10000 ? 1 : 2; // surrogate pair = 2 code units
    }
    // Sentinel end entry (EOF).
    units.add(cu);
    bytes.add(byte);
    _cuStarts = units;
    _byteStarts = bytes;
  }

  final SourceFile _file;
  late final List<int> _cuStarts;
  late final List<int> _byteStarts;

  /// UTF-8 byte offset → UTF-16 code-unit offset.
  ///
  /// A byte offset falling INSIDE a rune (never valid tree-sitter output;
  /// possible only for hand-mangled offsets) clamps UP to the rune start.
  int byteToCodeUnit(int byteOffset) {
    if (byteOffset < 0) return 0;
    // Binary search: largest k with _byteStarts[k] <= byteOffset.
    var lo = 0;
    var hi = _byteStarts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_byteStarts[mid] <= byteOffset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return _cuStarts[lo];
  }

  /// UTF-16 code-unit offset → UTF-8 byte offset (the reverse direction,
  /// for tests and for hosts holding code-unit offsets).
  int codeUnitToByte(int codeUnitOffset) {
    if (codeUnitOffset <= 0) return 0;
    var lo = 0;
    var hi = _cuStarts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_cuStarts[mid] <= codeUnitOffset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return _byteStarts[lo];
  }

  /// The UTF-8 byte offsets a node carries, as they feed the meaning
  /// tree's `span_start` / `span_end` props (fs span reader currency —
  /// unchanged, no conversion).
  ({int startByte, int endByte}) byteSpan(SourceNode node) =>
      (startByte: node.startByte, endByte: node.endByte);

  /// The source_span projection of [node] — UTF-16 code-unit offsets,
  /// line/column computed by source_span (the zoom/splice currency).
  SourceSpan span(SourceNode node) =>
      _file.span(byteToCodeUnit(node.startByte), byteToCodeUnit(node.endByte));

  /// Convenience: the source text a node covers, decoded correctly.
  String text(SourceNode node) => span(node).text;
}
