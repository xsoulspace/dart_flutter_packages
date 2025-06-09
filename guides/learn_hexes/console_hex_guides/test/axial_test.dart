// test/axial_test.dart
import 'package:console_hex_guides/axial.dart';
import 'package:test/test.dart';

void main() {
  group('Axial Coordinates', () {
    test('Constructor and properties', () {
      final axial = Axial(1, 2);
      expect(axial.q, 1);
      expect(axial.r, 2);
    });

    test('Equality', () {
      final a1 = Axial(1, 2);
      final a2 = Axial(1, 2);
      final a3 = Axial(2, 1);
      expect(a1 == a2, isTrue);
      expect(a1 == a3, isFalse);
      expect(a1.hashCode == a2.hashCode, isTrue);
    });

    test('ToString', () {
      final axial = Axial(-1, -2);
      expect(axial.toString(), 'Axial(-1, -2)');
    });

    test('Addition', () {
      final a = Axial(1, 2);
      final b = Axial(3, 4);
      expect(a + b, Axial(4, 6));
    });

    test('Subtraction', () {
      final a = Axial(4, 6);
      final b = Axial(1, 2);
      expect(a - b, Axial(3, 4));
    });

    test('Scalar Multiplication', () {
      final a = Axial(1, 2);
      expect(a * 3, Axial(3, 6));
    });
  });
}
