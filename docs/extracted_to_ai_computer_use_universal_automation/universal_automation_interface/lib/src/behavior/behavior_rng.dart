/// Deterministic, version-pinned PRNG for behavior synthesis.
///
/// `dart:math` `Random` explicitly does not guarantee stream stability
/// across Dart versions or platforms; synthesis must be replayable, so the
/// family ships its own generator: a splitmix32 expansion (`splitmix32-v1`)
/// seeds the four 32-bit words of an `xoshiro128**` state
/// (`xoshiro128starstar-v1`). Every operation is masked to 32 bits, so the
/// stream is bit-identical on the VM, dart2js, and ddc — unlike 64-bit
/// mixers, whose products cannot be represented exactly as JS doubles.
final class BehaviorRng {
  /// Creates a generator from a 64-bit [seed]; the seed is folded to 32
  /// bits (`low XOR high`) before expansion.
  factory BehaviorRng(int seed) {
    var state = (seed ^ (seed >>> 32)) & 0xffffffff;
    int splitmix32() {
      state = (state + 0x9e3779b9) & 0xffffffff;
      var z = state;
      z = ((z ^ (z >>> 16)) * 0x21f0aaad) & 0xffffffff;
      z = ((z ^ (z >>> 15)) * 0x735a2d97) & 0xffffffff;
      return (z ^ (z >>> 15)) & 0xffffffff;
    }

    return BehaviorRng._(
      splitmix32(),
      splitmix32(),
      splitmix32(),
      splitmix32(),
    );
  }

  BehaviorRng._(this._s0, this._s1, this._s2, this._s3);

  static int _rotl32(int x, int k) =>
      ((x << k) | (x >>> (32 - k))) & 0xffffffff;

  int _s0;
  int _s1;
  int _s2;
  int _s3;

  /// Identifiers pinned into plans and receipts; changing the construction
  /// is a breaking synthesis change and must bump these.
  static const String algorithmId = 'xoshiro128starstar-v1';

  /// Seeder identifier, pinned alongside [algorithmId].
  static const String seederId = 'splitmix32-v1';

  /// Next uniform 32-bit value.
  int nextUint32() {
    final result = _rotl32((_s1 * 5) & 0xffffffff, 7) * 9 & 0xffffffff;
    final t = (_s1 << 9) & 0xffffffff;
    var s0 = _s0;
    var s1 = _s1;
    var s2 = _s2;
    var s3 = _s3;
    s2 ^= s0;
    s3 ^= s1;
    s1 ^= s2;
    s0 ^= s3;
    s2 ^= t;
    s3 = _rotl32(s3, 11);
    _s0 = s0;
    _s1 = s1;
    _s2 = s2;
    _s3 = s3;
    return result;
  }

  /// Next uniform double in `[0, 1)` with 24 bits of entropy.
  double nextUnit() => (nextUint32() >>> 8) / 16777216.0;

  /// Next integer in `[min, max)`; [min] when the range is empty.
  int nextBetween(int min, int max) {
    if (max <= min) return min;
    return min + (nextUnit() * (max - min)).floor();
  }
}
