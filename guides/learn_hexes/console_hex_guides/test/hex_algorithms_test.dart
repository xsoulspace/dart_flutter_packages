// test/hex_algorithms_test.dart
import 'package:console_hex_guides/hex.dart';
import 'package:console_hex_guides/axial.dart';
import 'package:console_hex_guides/conversions.dart';
import 'package:console_hex_guides/hex_algorithms.dart';
import 'package:test/test.dart';

void main() {
  group('Hex Algorithms', () {
    final originHex = Hex(0, 0, 0);
    final originAxial = Axial(0, 0);

    group('Neighbors', () {
      test('Cube Neighbors of Origin', () {
        // Expected: E, NE, NW, W, SW, SE
        // Hex(1,0,-1), Hex(1,-1,0), Hex(0,-1,1), Hex(-1,0,1), Hex(-1,1,0), Hex(0,1,-1)
        final neighbors = List.generate(6, (i) => cubeNeighbor(originHex, i));
        expect(neighbors[0], Hex(1, 0, -1)); // E
        expect(neighbors[1], Hex(1, -1, 0)); // NE
        expect(neighbors[2], Hex(0, -1, 1)); // NW
        expect(neighbors[3], Hex(-1, 0, 1)); // W
        expect(neighbors[4], Hex(-1, 1, 0)); // SW
        expect(neighbors[5], Hex(0, 1, -1)); // SE
      });

      test('Axial Neighbors of Origin', () {
        final neighbors = List.generate(6, (i) => axialNeighbor(originAxial, i));
        expect(neighbors[0], Axial(1, 0));
        expect(neighbors[1], Axial(1, -1));
        expect(neighbors[2], Axial(0, -1));
        expect(neighbors[3], Axial(-1, 0));
        expect(neighbors[4], Axial(-1, 1));
        expect(neighbors[5], Axial(0, 1));
      });

      test('Cube Neighbor of (1,1,-2) direction 0 (E)', () {
        expect(cubeNeighbor(Hex(1,1,-2), 0), Hex(2,1,-3));
      });
       test('Axial Neighbor of (1,1) direction 0 (E)', () {
        expect(axialNeighbor(Axial(1,1), 0), Axial(2,1));
      });
    });

    group('Distances', () {
      test('Cube Distance', () {
        expect(cubeDistance(Hex(0,0,0), Hex(0,0,0)), 0);
        expect(cubeDistance(Hex(1,0,-1), Hex(0,0,0)), 1);
        expect(cubeDistance(Hex(1,0,-1), Hex(3,0,-3)), 2); // (2,0,-2) -> 2
        expect(cubeDistance(Hex(1,-2,1), Hex(-1,2,-1)), 4); // (-2,4,-2) -> 4
      });
      test('Axial Distance', () {
        expect(axialDistance(Axial(0,0), Axial(0,0)), 0);
        expect(axialDistance(Axial(1,0), Axial(0,0)), 1);
        expect(axialDistance(Axial(1,0), Axial(3,0)), 2);
        expect(axialDistance(Axial(1,-2), Axial(-1,2)), 4);
      });
    });

    group('Line Drawing', () {
      test('Cube Line Draw (straight)', () {
        final line = cubeLineDraw(Hex(0,0,0), Hex(3,0,-3));
        expect(line, [Hex(0,0,0), Hex(1,0,-1), Hex(2,0,-2), Hex(3,0,-3)]);
      });
      test('Cube Line Draw (diagonal)', () {
        final line = cubeLineDraw(Hex(0,0,0), Hex(2,2,-4)); // Should pass through (1,1,-2)
        expect(line, contains(Hex(1,1,-2)));
        expect(line.first, Hex(0,0,0));
        expect(line.last, Hex(2,2,-4));
        expect(line.length, cubeDistance(Hex(0,0,0), Hex(2,2,-4)) + 1);
      });
       test('Axial Line Draw', () {
        final line = axialLineDraw(Axial(0,0), Axial(3,0));
        expect(line, [Axial(0,0), Axial(1,0), Axial(2,0), Axial(3,0)]);
      });
    });

    group('Rotation (around origin)', () {
      final h = Hex(1, 0, -1); // East
      test('Cube Rotate Right', () {
        expect(cubeRotateRight(h), Hex(0, 1, -1));   // SE
        expect(cubeRotateRight(Hex(0,1,-1)), Hex(-1, 1, 0)); // SW
      });
      test('Cube Rotate Left', () {
        expect(cubeRotateLeft(h), Hex(1, -1, 0));    // NE
        expect(cubeRotateLeft(Hex(1,-1,0)), Hex(0,-1,1)); // NW
      });
      final a = Axial(1,0);
      test('Axial Rotate Right', () {
        expect(axialRotateRight(a), Axial(0, 1)); // SE
      });
       test('Axial Rotate Left', () {
        expect(axialRotateLeft(a), Axial(1, -1)); // NE
      });
    });

    group('Reflection (across origin axes)', () {
        final h = Hex(1, -2, 1); // A specific hex
        final a = cubeToAxial(h); // Axial(1, -2)

        test('Cube Reflect Q', () { expect(cubeReflectQ(h), Hex(1, 1, -2)); });
        test('Cube Reflect R', () { expect(cubeReflectR(h), Hex(1, -2, 1)); }); // No change if s == q
        test('Cube Reflect S', () { expect(cubeReflectS(h), Hex(-2, 1, 1)); });

        test('Axial Reflect Q (q-axis, like x-axis)', () {
            // q' = q, r' = -q-r
            expect(axialReflectQ(a), Axial(1, -1 - (-2))); // Axial(1, 1)
            expect(axialReflectQ(Axial(2,3)), Axial(2, -2-3)); // Axial(2, -5)
        });
        test('Axial Reflect R (r-axis, like y-axis)', () {
            // q' = -q-r, r' = r
            expect(axialReflectR(a), Axial(-1 - (-2), -2)); // Axial(1, -2)
            expect(axialReflectR(Axial(2,3)), Axial(-2-3, 3)); // Axial(-5, 3)
        });
        test('Axial Reflect S (s-axis, q+r=0 line)', () {
            // q' = -r, r' = -q
            expect(axialReflectS(a), Axial(-(-2), -1)); // Axial(2, -1)
            expect(axialReflectS(Axial(2,3)), Axial(-3,-2));
        });
    });

    group('Rings and Spirals', () {
      test('Cube Ring radius 0', () {
        expect(cubeRing(originHex, 0), [originHex]);
      });
      test('Cube Ring radius 1', () {
        final ring1 = cubeRing(originHex, 1);
        expect(ring1.length, 6);
        expect(ring1, contains(Hex(1,0,-1)));
        expect(ring1, isNot(contains(originHex)));
      });
      test('Cube Ring radius 2', () {
        final ring2 = cubeRing(originHex, 2);
        expect(ring2.length, 12);
        expect(ring2, contains(Hex(2,0,-2))); // A corner of radius 2 ring
        expect(ring2, contains(Hex(1,1,-2))); // A side hex of radius 2 ring
      });
      test('Axial Ring radius 1', () {
        final ring1 = axialRing(originAxial, 1);
        expect(ring1.length, 6);
        expect(ring1, contains(Axial(1,0)));
      });
      test('Cube Spiral radius 1', () {
        final spiral1 = cubeSpiral(originHex, 1); // Center + Ring 1
        expect(spiral1.length, 1 + 6);
        expect(spiral1, contains(originHex));
        expect(spiral1, contains(Hex(1,0,-1)));
      });
       test('Axial Spiral radius 1', () {
        final spiral1 = axialSpiral(originAxial, 1);
        expect(spiral1.length, 1 + 6);
        expect(spiral1, contains(originAxial));
        expect(spiral1, contains(Axial(1,0)));
      });
    });

    group('Range', () {
        test('Cube Range N=0', () {
            expect(cubeRange(originHex, 0), [originHex]);
        });
        test('Cube Range N=1', () {
            final range1 = cubeRange(originHex, 1);
            expect(range1.length, 7); // Center + 6 neighbors
            expect(range1, unorderedEquals([
                Hex(0,0,0), Hex(1,0,-1), Hex(1,-1,0), Hex(0,-1,1),
                Hex(-1,0,1), Hex(-1,1,0), Hex(0,1,-1)
            ]));
        });
        test('Cube Range N=1 (offset center)', () {
            final center = Hex(10,20,-30);
            final range1 = cubeRange(center, 1);
            expect(range1.length, 7);
            expect(range1, contains(center));
            expect(range1, contains(center + Hex(1,0,-1)));
        });
         test('Axial Range N=1', () {
            final range1 = axialRange(originAxial, 1);
            expect(range1.length, 7);
             expect(range1, unorderedEquals([
                Axial(0,0), Axial(1,0), Axial(1,-1), Axial(0,-1),
                Axial(-1,0), Axial(-1,1), Axial(0,1)
            ]));
        });
    });

  });
}
