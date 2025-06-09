// lib/axial.dart
import 'dart:math';

import 'package:console_hex_guides/hex.dart'; // Assuming Hex is Cube

class Axial {
  final int q;
  final int r;

  Axial(this.q, this.r);

  @override
  String toString() => 'Axial($q, $r)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Axial && runtimeType == other.runtimeType && q == other.q && r == other.r;

  @override
  int get hashCode => q.hashCode ^ r.hashCode;

  // Basic arithmetic (optional for Axial directly, but can be useful)
  Axial operator +(Axial other) => Axial(q + other.q, r + other.r);
  Axial operator -(Axial other) => Axial(q - other.q, r - other.r);
  Axial operator *(int scalar) => Axial(q * scalar, r * scalar);
}
