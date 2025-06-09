class Hex {
  final int q;
  final int r;
  final int s;

  Hex(this.q, this.r, this.s) {
    if (q + r + s != 0) {
      throw Exception("q + r + s must be 0");
    }
  }

  @override
  String toString() {
    return "Hex($q, $r, $s)";
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Hex &&
          runtimeType == other.runtimeType &&
          q == other.q &&
          r == other.r &&
          s == other.s;

  @override
  int get hashCode => q.hashCode ^ r.hashCode ^ s.hashCode;

  Hex operator +(Hex other) {
    return Hex(q + other.q, r + other.r, s + other.s);
  }

  Hex operator -(Hex other) {
    return Hex(q - other.q, r - other.r, s - other.s);
  }

  Hex operator *(int k) {
    return Hex(q * k, r * k, s * k);
  }

  Hex operator -() {
    return Hex(-q, -r, -s);
  }
}
