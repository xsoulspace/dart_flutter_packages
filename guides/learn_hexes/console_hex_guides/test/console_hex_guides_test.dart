import 'package:console_hex_guides/hex.dart';
import 'package:test/test.dart';

void main() {
  group('Hex', () {
    test('Constructor and Properties', () {
      final hex = Hex(1, -2, 1);
      expect(hex.q, equals(1));
      expect(hex.r, equals(-2));
      expect(hex.s, equals(1));
    });

    test('Constructor Throws Exception for Invalid Coordinates', () {
      expect(() => Hex(1, 2, 3), throwsException);
    });

    test('Equality', () {
      final hex1 = Hex(1, -2, 1);
      final hex2 = Hex(1, -2, 1);
      final hex3 = Hex(0, 0, 0);
      expect(hex1, equals(hex2));
      expect(hex1, isNot(equals(hex3)));
    });

    test('hashCode', () {
      final hex1 = Hex(1, -2, 1);
      final hex2 = Hex(1, -2, 1);
      expect(hex1.hashCode, equals(hex2.hashCode));
    });

    test('Addition', () {
      final hex1 = Hex(1, -2, 1);
      final hex2 = Hex(3, -1, -2);
      expect(hex1 + hex2, equals(Hex(4, -3, -1)));
    });

    test('Subtraction', () {
      final hex1 = Hex(1, -2, 1);
      final hex2 = Hex(3, -1, -2);
      expect(hex1 - hex2, equals(Hex(-2, -1, 3)));
    });

    test('Multiplication', () {
      final hex = Hex(1, -2, 1);
      expect(hex * 2, equals(Hex(2, -4, 2)));
    });

    test('Negation', () {
      final hex = Hex(1, -2, 1);
      expect(-hex, equals(Hex(-1, 2, -1)));
    });

    test('ToString', () {
      final hex = Hex(1, -2, 1);
      expect(hex.toString(), equals('Hex(1, -2, 1)'));
    });
  });
}
