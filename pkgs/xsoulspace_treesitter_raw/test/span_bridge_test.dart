// Multibyte golden tests for the span bridge (ADR 0035 §8 item 2):
// byte ≠ code-unit offsets are the classic silent corruption — these
// tests make it loud. Pure Dart (no FFI).
import 'dart:convert';

import 'package:source_span/source_span.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_treesitter_raw/xsoulspace_treesitter_raw.dart';

SourceNode _node(int startByte, int endByte) => SourceNode(
  type: 'fixture',
  field: null,
  startByte: startByte,
  endByte: endByte,
  startRow: 0,
  startColumn: startByte,
  endRow: 0,
  endColumn: endByte,
  children: const [],
);

void main() {
  // 'const ' = 6 bytes/units; '日本語' = 9 bytes / 3 units; ' = "🚀火箭";'
  // ... hand-computed offsets below.
  const source = 'const 日本語 = "🚀";\nconst ascii = 1;\n';
  // Rune layout (code units):
  //  c(0) o(1) n(2) s(3) t(4) sp(5) 日(6) 本(7) 語(8) sp(9) =(10) sp(11)
  //  "(12) 🚀(13–14, surrogate pair) "(15) ;(16) \n(17)
  // Bytes (UTF-8):
  //  c=0..4, 日=6..8, 本=9..11, 語=12..14, sp=15, ==16, sp=17,
  //  "=18, 🚀=19..22 (4 bytes), "=23, ;=24
  group('Utf8Utf16SpanBridge byte↔code-unit conversion', () {
    late Utf8Utf16SpanBridge bridge;
    setUp(() => bridge = Utf8Utf16SpanBridge(source));

    test('ASCII prefix: byte offset == code-unit offset', () {
      expect(bridge.byteToCodeUnit(0), 0);
      expect(bridge.byteToCodeUnit(6), 6);
    });

    test('CJK: 3 bytes per char collapse to 1 code unit', () {
      // After '日本語' (9 bytes) we are at byte 15, code unit 9.
      expect(bridge.byteToCodeUnit(15), 9);
      // The second CJK char starts at byte 9 → code unit 7.
      expect(bridge.byteToCodeUnit(9), 7);
      // The third at byte 12 → code unit 8.
      expect(bridge.byteToCodeUnit(12), 8);
    });

    test('emoji: 4 bytes collapse to 2 code units (surrogate pair)', () {
      // 🚀 starts at byte 19 → code unit 13; ends at byte 23 → unit 15.
      expect(bridge.byteToCodeUnit(19), 13);
      expect(bridge.byteToCodeUnit(23), 15);
    });

    test('EOF sentinel', () {
      expect(bridge.byteToCodeUnit(source.length + 1000), source.length);
    });

    test('inverse conversion agrees (codeUnitToByte)', () {
      for (final byte in const [
        0,
        4,
        5,
        6,
        8,
        9,
        12,
        14,
        15,
        16,
        18,
        19,
        22,
        23,
      ]) {
        final cu = bridge.byteToCodeUnit(byte);
        expect(bridge.codeUnitToByte(cu), lessThanOrEqualTo(byte));
        expect(bridge.byteToCodeUnit(bridge.codeUnitToByte(cu)), cu);
      }
    });

    test('mid-rune byte offsets clamp UP to the rune start', () {
      // Bytes 7, 8 are inside 日; the projection must not split a rune.
      expect(bridge.byteToCodeUnit(7), 6);
      expect(bridge.byteToCodeUnit(8), 6);
      expect(bridge.byteToCodeUnit(21), 13); // inside 🚀
    });
  });

  group('span projection (the corruption detector)', () {
    late Utf8Utf16SpanBridge bridge;
    setUp(() => bridge = Utf8Utf16SpanBridge(source));

    test('GOLDEN: node spanning CJK+emoji decodes correctly', () {
      // The string literal "🚀": bytes 18..24 → code units 12..16.
      final node = _node(18, 24);
      final span = bridge.span(node);
      expect(span.text, '"🚀"');
      // Line 0, column 12 (code units) — NOT byte column 18.
      expect(span.start.line, 0);
      expect(span.start.column, 12);
      // The UTF-8 re-encode of the projected text is exactly the byte span.
      final reencoded = utf8.encode(span.text).length;
      expect(reencoded, node.endByte - node.startByte);
    });

    test('GOLDEN: node spanning the CJK identifier', () {
      final node = _node(6, 15); // '日本語'
      expect(bridge.span(node).text, '日本語');
    });

    test('NEGATIVE PROOF: byte offsets as code-unit offsets corrupt', () {
      // The naive bug this bridge exists to prevent: slicing the Dart
      // string with BYTE offsets. It must produce the WRONG text here —
      // proving these tests would catch a bridge regression.
      final corrupt = source.substring(18, 24);
      expect(corrupt, isNot('"🚀"'));
      final correct = bridge.span(_node(18, 24)).text;
      expect(correct, '"🚀"');
    });

    test('byteSpan keeps the meaning-tree prop currency (no conversion)', () {
      final node = _node(6, 15);
      final props = bridge.byteSpan(node);
      expect(props.startByte, 6);
      expect(props.endByte, 15);
    });

    test('SourceFile line/column sanity for multibyte lines', () {
      final f = SourceFile.fromString(source);
      // Code unit 6 (日) is on line 0; the span text starts at it.
      expect(f.getLine(6), 0);
      expect(f.getText(6, 9), '日本語');
    });
  });
}
