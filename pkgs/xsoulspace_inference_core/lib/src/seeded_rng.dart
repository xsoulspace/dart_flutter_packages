/// A counter-based deterministic random source for a seeded inference
/// request.
///
/// The draw is a pure function of (seed, position): the value at position
/// `p` never depends on global RNG state, on how many other requests are in
/// flight, or on how many positions were drawn before it. A request that
/// carries a seed therefore reproduces in isolation, and batch composition
/// cannot change a single number it produced.
///
/// This is the sanctioned draw for a request that carries a seed
/// (`GenerationOptions.seed`): the carrier says a seed was asked for, and
/// this class is how that seed becomes actual numbers.
///
/// It is COUNTER-based, not a stateful global stream: the 64-bit state is
/// recomputed from (seed, position) on every draw, so there is no hidden
/// state to snapshot and no ordering hazard between concurrent requests.
/// The mixing function is SplitMix64 (finalizer `0x9E3779B97F4A7C15`), and
/// a rejected draw is a separate stream again, keyed by (seed, position,
/// attempt).
///
/// The idea was reviewed from DeepSeek's DeepInfer
/// (`github.com/deepseek-ai/DeepInfer`, Apache-2.0), specifically its
/// `deepinfer/model_executor/layers/tilelang_ops/random_sampling.py`
/// counter-based sampler (`seq_seed` + `sample_position` + stream id).
///
/// Non-claims: this is not a cryptographic RNG, and it promises nothing
/// about any provider's output — only that a draw from a given seed and
/// position is fixed.
// The 64-bit literals below are not representable as JavaScript numbers.
// ignore_for_file: avoid_js_rounded_ints
library;

class SeededRng {
  /// Creates a generator whose draws depend only on [seed] and on the
  /// position of the draw within this instance's sequence.
  ///
  /// A negative seed is rejected loudly: a seed is a key into a
  /// deterministic sequence, and a negative key has no meaning here.
  SeededRng(int seed) : _seed = seed {
    if (seed < 0) {
      throw ArgumentError.value(seed, 'seed', 'must be a non-negative seed');
    }
  }

  /// The seed this generator was created with.
  int get seed => _seed;

  final int _seed;

  /// The position of the next draw within this instance's sequence.
  ///
  /// The value at a position is a pure function of (seed, position), so
  /// this counter is the only state the generator carries.
  int _position = 0;

  /// The next uniform double in `[0, 1)`, with 53 bits of precision.
  double nextDouble() {
    final value = _mix64(_stateAt(_position++));
    return (value >>> 11) * _twoPowMinus53;
  }

  /// The next uniform integer in `[0, max)`.
  ///
  /// The draw is unbiased: it uses rejection sampling rather than a
  /// modulo of a smaller range, so every value in `[0, max)` is equally
  /// likely and no value is favoured by a remainder.
  ///
  /// Throws [ArgumentError] when [max] is not greater than zero — a caller
  /// that asks for a range of zero or less gets a loud failure, never a
  /// silent zero.
  int nextInt(int max) {
    if (max <= 0) {
      throw ArgumentError.value(max, 'max', 'must be greater than 0');
    }

    // One position per call: a rejected draw never shifts the main
    // sequence, so a position's value does not depend on how many
    // rejections happened anywhere else.
    final base = _stateAt(_position++);
    final tail = _tailSize(max);

    var attempt = 0;
    while (true) {
      final raw = attempt == 0
          ? _mix64(base)
          : _mix64(base + attempt * _rejectionSalt);
      // The top 63 bits of the draw: a non-negative int in `[0, 2^63)`.
      final value = raw >>> 1;
      // The draw range is `2^63`; the last `tail` values of it do not fill
      // a whole block of `max` and would bias the result, so they are
      // rejected. `value + tail` overflows into a negative int exactly
      // when the value falls in that tail.
      if (value + tail >= 0) {
        return value % max;
      }
      attempt++;
    }
  }

  /// The next full 64-bit draw.
  ///
  /// Dart's `int` is a signed 64-bit value, so the returned pattern is
  /// signed: the top bit is the sign bit. All 64 bits are still random —
  /// only the interpretation of the top one is.
  int nextInt64() => _mix64(_stateAt(_position++));

  /// The SplitMix64 state at [position]: the seed advanced by that many
  /// increments.
  int _stateAt(int position) => _seed + (position + 1) * _goldenGamma;

  /// The size of the biased tail of the 63-bit draw range for [max]: the
  /// remainder of `2^63` divided by [max].
  ///
  /// `2^63` itself is not representable as a signed 64-bit `int`, so the
  /// remainder is computed from `2^62` instead.
  static int _tailSize(int max) {
    if (max > _twoPow62) {
      // `2^63 = max + (2^63 - max)` with a single block, so the tail is
      // everything from `max` upwards.
      return _twoPow62 - (max - _twoPow62);
    }
    final remainder = _twoPow62 % max;
    return (remainder * 2) % max;
  }

  /// The SplitMix64 finalizer over a 64-bit state.
  ///
  /// The 64-bit arithmetic is exact on the Dart VM, where `int` is a 64-bit
  /// two's-complement value whose arithmetic wraps modulo `2^64` and whose
  /// `>>>` is an unsigned shift. It is not exact on the web compiler, where
  /// `int` is a double. This package is not web-compilable anyway
  /// (`env_config.dart` imports `dart:io`), so the constraint is recorded
  /// here rather than paid for with a slower arbitrary-precision path.
  static int _mix64(int state) {
    var z = state;
    z = ((z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9) & _uint64Mask;
    z = ((z ^ (z >>> 27)) * 0x94D049BB133111EB) & _uint64Mask;
    return (z ^ (z >>> 31)) & _uint64Mask;
  }

  /// The SplitMix64 increment.
  static const int _goldenGamma = 0x9E3779B97F4A7C15;

  /// The salt that separates a rejection retry from the main sequence.
  static const int _rejectionSalt = 0xD1B54A32D192ED03;

  /// The 64-bit mask.
  ///
  /// In Dart this literal is the signed 64-bit value `-1`, so masking with
  /// it is the identity: a Dart `int` already is a 64-bit two's-complement
  /// value whose arithmetic wraps modulo `2^64`. The mask is kept on every
  /// step to state the uint64 domain the mixing function is defined in.
  static const int _uint64Mask = 0xFFFFFFFFFFFFFFFF;

  /// `2^62`, the largest power of two a signed 64-bit `int` holds exactly.
  static const int _twoPow62 = 0x4000000000000000;

  /// `2^-53`, the scale that turns 53 random bits into a double in
  /// `[0, 1)`.
  static const double _twoPowMinus53 = 1.0 / 9007199254740992.0;
}
