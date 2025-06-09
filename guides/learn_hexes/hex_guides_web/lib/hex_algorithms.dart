// lib/hex_algorithms.dart
import 'dart:math';
import 'package:hex_guides_web/hex.dart'; // Adjusted for web project
import 'package:hex_guides_web/axial.dart'; // Adjusted for web project
import 'package:hex_guides_web/conversions.dart'; // Adjusted for web project

// --- Neighbors ---
final List<Hex> cubeDirections = [
  Hex(1, 0, -1), Hex(1, -1, 0), Hex(0, -1, 1),
  Hex(-1, 0, 1), Hex(-1, 1, 0), Hex(0, 1, -1),
];
final List<Axial> axialDirections = [
  Axial(1, 0), Axial(1, -1), Axial(0, -1),
  Axial(-1, 0), Axial(-1, 1), Axial(0, 1),
];
Hex cubeNeighbor(Hex hex, int direction) => hex + cubeDirections[direction % 6];
Axial axialNeighbor(Axial hex, int direction) => hex + axialDirections[direction % 6];

// --- Distances ---
int cubeDistance(Hex a, Hex b) {
  final vec = a - b;
  return (vec.q.abs() + vec.r.abs() + vec.s.abs()) ~/ 2;
}
int axialDistance(Axial a, Axial b) {
  final vec = a - b;
  return (vec.q.abs() + (vec.q + vec.r).abs() + vec.r.abs()) ~/ 2;
}

// --- Line Drawing (Lerp and Rounding) ---
double _lerp(double a, double b, double t) => a + (b - a) * t; // Keep _lerp private if only used here

// Public version of cubeLerp
Hex cubeLerp(Hex a, Hex b, double t) {
  double q = _lerp(a.q.toDouble(), b.q.toDouble(), t);
  double r = _lerp(a.r.toDouble(), b.r.toDouble(), t);
  double s = _lerp(a.s.toDouble(), b.s.toDouble(), t);
  return cubeRound(q, r, s); // Use public cubeRound
}

// Public rounding function, formerly _cubeRound
Hex cubeRound(double fracQ, double fracR, double fracS) {
  int q = fracQ.round();
  int r = fracR.round();
  int s = fracS.round();
  double qDiff = (q - fracQ).abs();
  double rDiff = (r - fracR).abs();
  double sDiff = (s - fracS).abs();
  if (qDiff > rDiff && qDiff > sDiff) {
    q = -r - s;
  } else if (rDiff > sDiff) {
    r = -q - s;
  } else {
    s = -q - r;
  }
  return Hex(q, r, s);
}

List<Hex> cubeLineDraw(Hex a, Hex b) {
  int N = cubeDistance(a, b);
  if (N == 0) return [a];
  List<Hex> results = [];
  for (int i = 0; i <= N; i++) {
    results.add(cubeLerp(a, b, i.toDouble() / N)); // Uses public cubeLerp
  }
  return results;
}
List<Axial> axialLineDraw(Axial a, Axial b) {
  final Hex cubeA = axialToCube(a);
  final Hex cubeB = axialToCube(b);
  final List<Hex> cubeLine = cubeLineDraw(cubeA, cubeB);
  return cubeLine.map((hex) => cubeToAxial(hex)).toList();
}

// --- Rotation ---
Hex cubeRotateRight(Hex hex) => Hex(-hex.r, -hex.s, -hex.q);
Hex cubeRotateLeft(Hex hex) => Hex(-hex.s, -hex.q, -hex.r);
Axial axialRotateRight(Axial axial) => cubeToAxial(cubeRotateRight(axialToCube(axial)));
Axial axialRotateLeft(Axial axial) => cubeToAxial(cubeRotateLeft(axialToCube(axial)));

// --- Reflection ---
Hex cubeReflectQ(Hex h) => Hex(h.q, h.s, h.r);
Hex cubeReflectR(Hex h) => Hex(h.s, h.r, h.q);
Hex cubeReflectS(Hex h) => Hex(h.r, h.q, h.s);
Axial axialReflectQ(Axial axial) => Axial(axial.q, -axial.q - axial.r);
Axial axialReflectR(Axial axial) => Axial(-axial.q - axial.r, axial.r);
Axial axialReflectS(Axial axial) => Axial(-axial.r, -axial.q);

// --- Rings and Spirals ---
List<Hex> cubeRing(Hex center, int radius) {
  if (radius == 0) return [center];
  List<Hex> results = [];
  Hex current = center + (cubeDirections[4] * radius);
  for (int i = 0; i < 6; i++) {
    for (int j = 0; j < radius; j++) {
      results.add(current);
      current = cubeNeighbor(current, i);
    }
  }
  return results;
}
List<Axial> axialRing(Axial center, int radius) =>
    cubeRing(axialToCube(center), radius).map((h) => cubeToAxial(h)).toList();

List<Hex> cubeSpiral(Hex center, int maxRadius) {
  List<Hex> results = [center];
  for (int r = 1; r <= maxRadius; r++) {
    results.addAll(cubeRing(center, r));
  }
  return results;
}
List<Axial> axialSpiral(Axial center, int maxRadius) =>
    cubeSpiral(axialToCube(center), maxRadius).map((h) => cubeToAxial(h)).toList();

// --- Range ---
List<Hex> cubeRange(Hex center, int N) {
  List<Hex> results = [];
  for (int q = -N; q <= N; q++) {
    for (int r = max(-N, -q - N); r <= min(N, -q + N); r++) {
      results.add(center + Hex(q, r, -q - r));
    }
  }
  return results;
}
List<Axial> axialRange(Axial center, int N) {
  List<Axial> results = [];
  for (int q = -N; q <= N; q++) {
    for (int r = max(-N, -q - N); r <= min(N, -q + N); r++) {
      results.add(center + Axial(q, r));
    }
  }
  return results;
}
