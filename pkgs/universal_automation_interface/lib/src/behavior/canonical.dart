import 'dart:convert';

import 'behavior_hash.dart';

/// Canonical JSON encoding for behavior artifacts (plans, profile hashes).
///
/// Determinism rules (ADR 0044): map keys are sorted; doubles are rejected
/// — callers quantize coordinates to integer hundredths-of-a-pixel and
/// times to integer microseconds, so no platform float formatting can leak
/// into a hash. Encoding is hand-rolled rather than `jsonEncode` because
/// the canonical form is a cross-version, cross-platform contract.
String canonicalJson(Object? value) {
  final buffer = StringBuffer();
  _write(buffer, value);
  return buffer.toString();
}

void _write(StringBuffer out, Object? value) {
  switch (value) {
    case null:
      out.write('null');
    case final bool flag:
      out.write(flag ? 'true' : 'false');
    case final int number:
      out.write(number);
    case final double _:
      throw ArgumentError(
        'canonicalJson rejects doubles; quantize to int '
        '(coordinates: ×100 grid, time: microseconds)',
      );
    case final String text:
      _writeString(out, text);
    case final List<Object?> list:
      out.write('[');
      for (var i = 0; i < list.length; i++) {
        if (i > 0) out.write(',');
        _write(out, list[i]);
      }
      out.write(']');
    case final Map<String, Object?> map:
      final keys = map.keys.toList()..sort();
      out.write('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) out.write(',');
        _writeString(out, keys[i]);
        out.write(':');
        _write(out, map[keys[i]]);
      }
      out.write('}');
    default:
      throw ArgumentError.value(
        value,
        'value',
        'canonicalJson supports null, bool, int, String, List, Map',
      );
  }
}

void _writeString(StringBuffer out, String text) {
  out.write('"');
  for (final rune in text.runes) {
    switch (rune) {
      case 0x22:
        out.write(r'\"');
      case 0x5c:
        out.write(r'\\');
      case 0x0a:
        out.write(r'\n');
      case 0x0d:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      case < 0x20:
        out.write('\\u${rune.toRadixString(16).padLeft(4, '0')}');
      default:
        out.writeCharCode(rune);
    }
  }
  out.write('"');
}

/// Quantizes logical pixels to the canonical hundredth-of-a-pixel grid.
int gridValue(double pixels) => (pixels * 100).round();

/// Restores logical pixels from the canonical hundredth grid.
double pixelsFromGrid(int grid) => grid / 100.0;

/// SHA-256 of the canonical form, hex-encoded. Used for profile hashes,
/// plan (stream) hashes, and receipt linkage.
String canonicalHash(Object? value) =>
    sha256Hex(utf8.encode(canonicalJson(value)));
