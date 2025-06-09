// lib/hex_algorithms.dart
import 'dart:math';
import 'package:console_hex_guides/hex.dart';
import 'package:console_hex_guides/axial.dart';
import 'package:console_hex_guides/conversions.dart'; // For potential internal use or if needed by users

// --- Neighbors ---

// Cube directions (order: E, NE, NW, W, SW, SE) - matches RedBlobGames for pointy top
// For flat top, the order might be different or interpretation of dx,dy,dz changes.
// This is one common setup.
final List<Hex> cubeDirections = [
  Hex(1, 0, -1), Hex(1, -1, 0), Hex(0, -1, 1),
  Hex(-1, 0, 1), Hex(-1, 1, 0), Hex(0, 1, -1),
];

// Axial directions (derived from cube directions)
final List<Axial> axialDirections = [
  Axial(1, 0), Axial(1, -1), Axial(0, -1),
  Axial(-1, 0), Axial(-1, 1), Axial(0, 1),
];

Hex cubeNeighbor(Hex hex, int direction) {
  return hex + cubeDirections[direction % 6];
}

Axial axialNeighbor(Axial hex, int direction) {
  return hex + axialDirections[direction % 6];
}

// --- Distances ---

int cubeDistance(Hex a, Hex b) {
  final vec = a - b;
  return (vec.q.abs() + vec.r.abs() + vec.s.abs()) ~/ 2;
  // Or equivalently: max(vec.q.abs(), max(vec.r.abs(), vec.s.abs()));
  // The max form is often cited: return max(vec.q.abs(), max(vec.r.abs(), vec.s.abs()));
  // Let's use the max form as it's common and avoids division issues if Hex coords were not always even sums.
  // Hex class ensures q+r+s=0, so (abs(q)+abs(r)+abs(s)) will always be even.
  // return max(vec.q.abs(), max(vec.r.abs(), vec.s.abs()));
}

int axialDistance(Axial a, Axial b) {
  final vec = a - b;
  // Convert to cube to use cube_distance logic: Hex(vec.q, vec.r, -vec.q-vec.r)
  // Or directly: (abs(vec.q) + abs(vec.q + vec.r) + abs(vec.r)) / 2
  return (vec.q.abs() + (vec.q + vec.r).abs() + vec.r.abs()) ~/ 2;
}

// --- Line Drawing (Lerp and Rounding) ---

// Linear interpolation for floats
double _lerp(double a, double b, double t) {
  return a + (b - a) * t;
}

// Cube linear interpolation
Hex _cubeLerp(Hex a, Hex b, double t) {
  // For rounding, we need fractional hexes.
  // The Hex class currently takes ints. We'll do calculations with doubles and round at the end.
  double q = _lerp(a.q.toDouble(), b.q.toDouble(), t);
  double r = _lerp(a.r.toDouble(), b.r.toDouble(), t);
  double s = _lerp(a.s.toDouble(), b.s.toDouble(), t);
  return _cubeRound(q, r, s); // Round to nearest Hex
}

// Round fractional cube coordinates to the nearest hex
// This is a critical algorithm from the Red Blob Games guide
Hex _cubeRound(double fracQ, double fracR, double fracS) {
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
  return Hex(q, r, s); // This will throw if q+r+s != 0 after rounding, which is good.
}

List<Hex> cubeLineDraw(Hex a, Hex b) {
  int N = cubeDistance(a, b);
  if (N == 0) return [a];

  List<Hex> results = [];
  for (int i = 0; i <= N; i++) {
    results.add(_cubeLerp(a, b, i.toDouble() / N));
  }
  return results;
}

List<Axial> axialLineDraw(Axial a, Axial b) {
  // Convert to cube, draw line, then convert back
  // This is simpler than re-implementing lerp and round for axial.
  final Hex cubeA = axialToCube(a);
  final Hex cubeB = axialToCube(b);
  final List<Hex> cubeLine = cubeLineDraw(cubeA, cubeB);
  return cubeLine.map((hex) => cubeToAxial(hex)).toList();
}


// --- Rotation (around origin 0,0,0 or 0,0) ---
// Rotates right (clockwise)
Hex cubeRotateRight(Hex hex) {
  // [q, r, s] -> [-r, -s, -q] according to RedBlobGames (for their specific axis setup)
  // Let's verify: if q=1,r=0,s=-1 (East), then new hex is Hex(0, 1, -1) (South-East)
  // This is one step clockwise.
  return Hex(-hex.r, -hex.s, -hex.q);
}

Hex cubeRotateLeft(Hex hex) {
  // [q, r, s] -> [-s, -q, -r]
  return Hex(-hex.s, -hex.q, -hex.r);
}

Axial axialRotateRight(Axial axial) {
  // Convert to cube, rotate, convert back
  Hex cube = axialToCube(axial);
  Hex rotatedCube = cubeRotateRight(cube);
  return cubeToAxial(rotatedCube);
  // Or directly using matrix transformations if preferred, but cube is often easier.
  // q' = -r
  // r' = -s = -(-q-r) = q+r
  // return Axial(-axial.r, axial.q + axial.r); // This is for a different rotation system on RBG, need to match cube one
  // From Cube: q' = -r_old, r' = -s_old = -(-q_old-r_old) = q_old+r_old.
  // So new_q = -old_r, new_r = old_q + old_r. This matches one of the axial rotation formulas.
}

Axial axialRotateLeft(Axial axial) {
  Hex cube = axialToCube(axial);
  Hex rotatedCube = cubeRotateLeft(cube);
  return cubeToAxial(rotatedCube);
}


// --- Reflection (across axes passing through origin) ---
Hex cubeReflectQ(Hex h) { return Hex(h.q, h.s, h.r); } // Reflect across Q axis (swaps R and S)
Hex cubeReflectR(Hex h) { return Hex(h.s, h.r, h.q); } // Reflect across R axis
Hex cubeReflectS(Hex h) { return Hex(h.r, h.q, h.s); } // Reflect across S axis

Axial axialReflectQ(Axial axial) { // Reflect across q=0 axis (x-axis in axial)
  // s = -q-r. New s' is old r. New r' is old s. q' is old q.
  // q' = q
  // r' = -q-r (old s)
  return Axial(axial.q, -axial.q - axial.r);
}
Axial axialReflectR(Axial axial) { // Reflect across r=0 axis (y-axis in axial)
  // q' = -q-r (old s)
  // r' = r
  return Axial(-axial.q - axial.r, axial.r);
}
// Axial reflection over s=0 (q+r=0) is a bit more complex:
Axial axialReflectS(Axial axial) { // Reflect across s=0 (q+r=0) axis
    // q' = -r
    // r' = -q
    return Axial(-axial.r, -axial.q);
}


// --- Rings and Spirals ---
Hex cubeRingStep(Hex center, int radius, int step) {
    if (radius == 0) return center;
    Hex current = center + cubeDirections[4] * radius; // Start at a corner (e.g., direction 4, then move along i)
    for (int i = 0; i < step; i++) {
        current = cubeNeighbor(current, i ~/ radius); // Integer division gives the direction index
    }
    return current;
}

List<Hex> cubeRing(Hex center, int radius) {
  if (radius == 0) return [center];
  List<Hex> results = [];
  // Start at one corner of the hexagon ring
  Hex current = center + (cubeDirections[4] * radius); // Example starting direction
  for (int i = 0; i < 6; i++) { // For each of the 6 sides of the ring
    for (int j = 0; j < radius; j++) { // For each step along that side
      results.add(current);
      current = cubeNeighbor(current, i);
    }
  }
  return results;
}

List<Axial> axialRing(Axial center, int radius) {
  final Hex cubeCenter = axialToCube(center);
  final List<Hex> cubeResults = cubeRing(cubeCenter, radius);
  return cubeResults.map((h) => cubeToAxial(h)).toList();
}

List<Hex> cubeSpiral(Hex center, int maxRadius) {
  List<Hex> results = [center];
  for (int r = 1; r <= maxRadius; r++) {
    results.addAll(cubeRing(center, r));
  }
  return results;
}

List<Axial> axialSpiral(Axial center, int maxRadius) {
  final Hex cubeCenter = axialToCube(center);
  final List<Hex> cubeResults = cubeSpiral(cubeCenter, maxRadius);
  return cubeResults.map((h) => cubeToAxial(h)).toList();
}

// --- Range ---
List<Hex> cubeRange(Hex center, int N) {
  List<Hex> results = [];
  for (int q = -N; q <= N; q++) {
    for (int r = max(-N, -q - N); r <= min(N, -q + N); r++) {
      int s = -q - r;
      results.add(center + Hex(q, r, s));
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
