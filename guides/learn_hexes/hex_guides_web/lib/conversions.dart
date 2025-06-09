// lib/conversions.dart
import 'package:hex_guides_web/hex.dart'; // Cube coordinates
import 'package:hex_guides_web/axial.dart';
import 'package:hex_guides_web/offset.dart';

// Cube to Axial
Axial cubeToAxial(Hex cube) {
  return Axial(cube.q, cube.r);
}

// Axial to Cube
Hex axialToCube(Axial axial) {
  return Hex(axial.q, axial.r, -axial.q - axial.r);
}

// Axial to Offset (odd-r: pointy top, odd rows shifted right)
OffsetCoord axialToOddROffset(Axial axial) {
  int col = axial.q + (axial.r - (axial.r & 1)) ~/ 2;
  int row = axial.r;
  return OffsetCoord(col, row);
}

// Offset (odd-r) to Axial
Axial oddROffsetToAxial(OffsetCoord offset) {
  int q = offset.col - (offset.row - (offset.row & 1)) ~/ 2;
  int r = offset.row;
  return Axial(q, r);
}

// Axial to Offset (even-r: pointy top, even rows shifted right)
OffsetCoord axialToEvenROffset(Axial axial) {
  int col = axial.q + (axial.r + (axial.r & 1)) ~/ 2;
  int row = axial.r;
  return OffsetCoord(col, row);
}

// Offset (even-r) to Axial
Axial evenROffsetToAxial(OffsetCoord offset) {
  int q = offset.col - (offset.row + (offset.row & 1)) ~/ 2;
  int r = offset.row;
  return Axial(q, r);
}

// Axial to Offset (odd-q: flat top, odd columns shifted down)
OffsetCoord axialToOddQOffset(Axial axial) {
  int col = axial.q;
  int row = axial.r + (axial.q - (axial.q & 1)) ~/ 2;
  return OffsetCoord(col, row);
}

// Offset (odd-q) to Axial
Axial oddQOffsetToAxial(OffsetCoord offset) {
  int q = offset.col;
  int r = offset.row - (offset.col - (offset.col & 1)) ~/ 2;
  return Axial(q, r);
}

// Axial to Offset (even-q: flat top, even columns shifted down)
OffsetCoord axialToEvenQOffset(Axial axial) {
  int col = axial.q;
  int row = axial.r + (axial.q + (axial.q & 1)) ~/ 2;
  return OffsetCoord(col, row);
}

// Offset (even-q) to Axial
Axial evenQOffsetToAxial(OffsetCoord offset) {
  int q = offset.col;
  int r = offset.row - (offset.col + (offset.col & 1)) ~/ 2;
  return Axial(q, r);
}

// Helper to demonstrate usage (optional, for testing)
void main() {
  // Cube <-> Axial
  Hex h1 = Hex(1, 2, -3);
  Axial a1 = cubeToAxial(h1);
  print('Cube $h1 to Axial: $a1');
  Hex h2 = axialToCube(a1);
  print('Axial $a1 to Cube: $h2');

  // Axial <-> Offset (odd-r)
  Axial a2 = Axial(1, 2);
  OffsetCoord o1 = axialToOddROffset(a2);
  print('Axial $a2 to OddR Offset: $o1');
  Axial a3 = oddROffsetToAxial(o1);
  print('OddR Offset $o1 to Axial: $a3');

  // Axial <-> Offset (even-r)
  OffsetCoord o2 = axialToEvenROffset(a2);
  print('Axial $a2 to EvenR Offset: $o2');
  Axial a4 = evenROffsetToAxial(o2);
  print('EvenR Offset $o2 to Axial: $a4');

  // Axial <-> Offset (odd-q)
  OffsetCoord o3 = axialToOddQOffset(a2);
  print('Axial $a2 to OddQ Offset: $o3');
  Axial a5 = oddQOffsetToAxial(o3);
  print('OddQ Offset $o3 to Axial: $a5');

  // Axial <-> Offset (even-q)
  OffsetCoord o4 = axialToEvenQOffset(a2);
  print('Axial $a2 to EvenQ Offset: $o4');
  Axial a6 = evenQOffsetToAxial(o4);
  print('EvenR Offset $o4 to Axial: $a6');
}
