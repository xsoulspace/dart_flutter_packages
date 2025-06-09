// test/offset_test.dart
import 'package:console_hex_guides/offset.dart';
import 'package:test/test.dart';

void main() {
  group('Offset Coordinates', () {
    test('Constructor and properties', () {
      final offset = OffsetCoord(3, 4);
      expect(offset.col, 3);
      expect(offset.row, 4);
    });

    test('Equality', () {
      final o1 = OffsetCoord(3, 4);
      final o2 = OffsetCoord(3, 4);
      final o3 = OffsetCoord(4, 3);
      expect(o1 == o2, isTrue);
      expect(o1 == o3, isFalse);
      expect(o1.hashCode == o2.hashCode, isTrue);
    });

    test('ToString', () {
      final offset = OffsetCoord(-1, 0);
      expect(offset.toString(), 'OffsetCoord(-1, 0)');
    });
  });
}
