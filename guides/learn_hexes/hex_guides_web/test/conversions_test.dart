// test/conversions_test.dart
import 'package:hex_guides_web/hex.dart';
import 'package:hex_guides_web/axial.dart';
import 'package:hex_guides_web/offset.dart';
import 'package:hex_guides_web/conversions.dart';
import 'package:test/test.dart';

void main() {
  group('Coordinate Conversions', () {
    final testHex = Hex(1, 2, -3);
    final testAxial = Axial(1, 2);

    test('Cube to Axial', () {
      expect(cubeToAxial(testHex), testAxial);
    });

    test('Axial to Cube', () {
      expect(axialToCube(testAxial), testHex);
    });

    group('Pointy Top (Axial <-> Offset)', () {
      // Odd-R
      // Axial(1,2) -> Offset(1 + (2-(2&1))/2, 2) = Offset(1 + (2-0)/2, 2) = Offset(1+1, 2) = Offset(2,2)
      final oddROffset = OffsetCoord(2, 2);
      test('Axial to OddR Offset', () {
        expect(axialToOddROffset(testAxial), oddROffset);
      });
      test('OddR Offset to Axial', () {
        expect(oddROffsetToAxial(oddROffset), testAxial);
      });

      // Axial(1,1) -> Offset(1 + (1-(1&1))/2, 1) = Offset(1 + (1-1)/2, 1) = Offset(1+0,1) = Offset(1,1)
      final testAxialOddRow = Axial(1,1);
      final oddROffsetOddRow = OffsetCoord(1,1);
      test('Axial to OddR Offset (odd row)', () {
        expect(axialToOddROffset(testAxialOddRow), oddROffsetOddRow);
      });
      test('OddR Offset to Axial (odd row)', () {
        expect(oddROffsetToAxial(oddROffsetOddRow), testAxialOddRow);
      });

      // Even-R
      // Axial(1,2) -> Offset(1 + (2+(2&1))/2, 2) = Offset(1 + (2+0)/2, 2) = Offset(1+1, 2) = Offset(2,2)
      final evenROffset = OffsetCoord(2, 2);
      test('Axial to EvenR Offset', () {
        expect(axialToEvenROffset(testAxial), evenROffset);
      });
      test('EvenR Offset to Axial', () {
        expect(evenROffsetToAxial(evenROffset), testAxial);
      });

      // Axial(1,1) -> Offset(1 + (1+(1&1))/2, 1) = Offset(1 + (1+1)/2, 1) = Offset(1+1,1) = Offset(2,1)
      final evenROffsetOddRow = OffsetCoord(2,1);
      test('Axial to EvenR Offset (odd row)', () {
        expect(axialToEvenROffset(testAxialOddRow), evenROffsetOddRow);
      });
      test('EvenR Offset to Axial (odd row)', () {
        expect(evenROffsetToAxial(evenROffsetOddRow), testAxialOddRow);
      });
    });

    group('Flat Top (Axial <-> Offset)', () {
      // Odd-Q
      // Axial(1,2) -> Offset(1, 2 + (1-(1&1))/2) = Offset(1, 2 + (1-1)/2) = Offset(1, 2+0) = Offset(1,2)
      final oddQOffset = OffsetCoord(1, 2);
      test('Axial to OddQ Offset', () {
        expect(axialToOddQOffset(testAxial), oddQOffset);
      });
      test('OddQ Offset to Axial', () {
        expect(oddQOffsetToAxial(oddQOffset), testAxial);
      });

      // Axial(2,1) -> Offset(2, 1 + (2-(2&1))/2) = Offset(2, 1 + (2-0)/2) = Offset(2, 1+1) = Offset(2,2)
      final testAxialOddCol = Axial(2,1);
      final oddQOffsetOddCol = OffsetCoord(2,2);
      test('Axial to OddQ Offset (odd col)', () {
        expect(axialToOddQOffset(testAxialOddCol), oddQOffsetOddCol);
      });
      test('OddQ Offset to Axial (odd col)', () {
        expect(oddQOffsetToAxial(oddQOffsetOddCol), testAxialOddCol);
      });

      // Even-Q
      // Axial(1,2) -> Offset(1, 2 + (1+(1&1))/2) = Offset(1, 2 + (1+1)/2) = Offset(1, 2+1) = Offset(1,3)
      final evenQOffset = OffsetCoord(1, 3);
      test('Axial to EvenQ Offset', () {
        expect(axialToEvenQOffset(testAxial), evenQOffset);
      });
      test('EvenQ Offset to Axial', () {
        expect(evenQOffsetToAxial(evenQOffset), testAxial);
      });

      // Axial(2,1) -> Offset(2, 1 + (2+(2&1))/2) = Offset(2, 1 + (2+0)/2) = Offset(2, 1+1) = Offset(2,2)
      final evenQOffsetOddCol = OffsetCoord(2,2);
      test('Axial to EvenQ Offset (odd col)', () {
        expect(axialToEvenQOffset(testAxialOddCol), evenQOffsetOddCol);
      });
      test('EvenQ Offset to Axial (odd col)', () {
        expect(evenQOffsetToAxial(evenQOffsetOddCol), testAxialOddCol);
      });
    });
  });
}
