// The reference literals below are full 64-bit values and are not
// representable as JavaScript numbers. The package is not web-compilable
// anyway, so the constraint is recorded here rather than paid for.
// ignore_for_file: avoid_js_rounded_ints

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// Golden vectors for the seeded draw.
///
/// `seeded_rng_test.dart` proves the COUNTER-BASED PROPERTIES of
/// [SeededRng]: that a draw is a function of (seed, position), that a fresh
/// instance replays the same sequence, that no global state perturbs it.
/// Those properties are exactly what a WRONG generator also satisfies — a
/// constant, a biased counter, a subtly different mixer all pass them.
///
/// This file closes the other half: it pins the OUTPUT to canonical
/// SplitMix64, so the doc comment's claim ("the mixing function is
/// SplitMix64") is proven rather than asserted. A reproducibility contract
/// whose bytes can drift without any test noticing is not a contract.
///
/// The vectors below were produced by an INDEPENDENT reference
/// implementation written in Python 3 (not by running the Dart code and
/// pasting its output — that would prove nothing). The reference
/// re-derives the canonical algorithm as published by Sebastiano Vigna in
/// the public-domain `splitmix64.c` (Steele/Lea/Flood 2014, the
/// fixed-increment form of Java 8's `SplittableRandom`):
///
/// ```c
/// uint64_t next() {
///   uint64_t z = (x += 0x9e3779b97f4a7c15);
///   z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9;
///   z = (z ^ (z >> 27)) * 0x94d049bb133111eb;
///   return z ^ (z >> 31);
/// }
/// ```
///
/// The Python reference used Python's arbitrary-precision integers masked to
/// 64 bits (`& 0xFFFFFFFFFFFFFFFF`) to emulate C's `uint64_t` exactly, and
/// it advanced the state by adding the golden gamma on EVERY draw before
/// mixing — the same order as the C source.
///
/// The Dart implementation advances the state the same way: its state at
/// position `p` is `seed + (p + 1) * 0x9E3779B97F4A7C15`, i.e. the gamma is
/// added once per draw and BEFORE the mix, so draw 0 mixes `seed + gamma`.
///
/// ## uint64 -> signed int64 conversion
///
/// The reference produces UNSIGNED 64-bit values. Dart's `int` is a SIGNED
/// 64-bit two's-complement value and `nextInt64()` returns the draw with
/// the top bit as the SIGN bit, so each reference value was converted
/// before being written down as a literal:
///
/// ```text
/// signed = u >= 2^63 ? u - 2^64 : u
/// ```
///
/// This is exactly the kind of step that silently breaks a golden test: the
/// same 64 bits are two different Dart literals, and a test that compares
/// the unsigned number would fail forever while proving nothing. The
/// unsigned form of every vector is kept here as a comment so the
/// conversion stays auditable.
///
/// The `nextDouble()` vectors are exact too, not approximate: the draw
/// keeps 53 bits and scales them by `2^-53`, and a 53-bit integer scaled
/// by a power of two is exactly representable in binary64. Both sides
/// compute the identical rational, so the doubles are compared with exact
/// equality. (The exactness claim rests on the INTEGER vectors; the doubles
/// are a projection of the same draws.)
void main() {
  group('SeededRng golden vectors (canonical SplitMix64)', () {
    test(
      'splitmix64 nextInt64 matches the independent reference for seed 0',
      () {
        // Unsigned: 0xE220A8397B1DCDAF, 0x6E789E6AA1B965F4, 0x06C45D188009454F,
        // 0xF88BB8A8724C81EC, 0x1B39896A51A8749B, 0x53CB9F0C747EA2EA,
        // 0x2C829ABE1F4532E1, 0xC584133AC916AB3C.
        const expected = <int>[
          -2152535657050944081,
          7960286522194355700,
          487617019471545679,
          -537132696929009172,
          1961750202426094747,
          6038094601263162090,
          3207296026000306913,
          -4214222208109204676,
        ];

        final rng = SeededRng(0);
        for (var i = 0; i < expected.length; i++) {
          expect(
            rng.nextInt64(),
            expected[i],
            reason: 'draw $i for seed 0 must match the reference exactly',
          );
        }
      },
    );

    test(
      'splitmix64 nextInt64 matches the independent reference for seed 1',
      () {
        // Unsigned: 0x910A2DEC89025CC1, 0xBEEB8DA1658EEC67, 0xF893A2EEFB32555E,
        // 0x71C18690EE42C90B, 0x71BB54D8D101B5B9, 0xC34D0BFF90150280,
        // 0xE099EC6CD7363CA5, 0x85E7BB0F12278575.
        const expected = <int>[
          -7995527694508729151,
          -4689498862643123097,
          -534904783426661026,
          8196980753821780235,
          8195237237126968761,
          -4373826470845021568,
          -2262517385565684571,
          -8797857673641491083,
        ];

        final rng = SeededRng(1);
        for (var i = 0; i < expected.length; i++) {
          expect(
            rng.nextInt64(),
            expected[i],
            reason: 'draw $i for seed 1 must match the reference exactly',
          );
        }
      },
    );

    test(
      'splitmix64 nextInt64 matches the independent reference for seed 42',
      () {
        // Unsigned: 0xBDD732262FEB6E95, 0x28EFE333B266F103, 0x47526757130F9F52,
        // 0x581CE1FF0E4AE394, 0x9BC585A244823F2, 0xDE4431FA3C80DB06,
        // 0x37E9671C45376D5D, 0xCCF635EE9E9E2FA4.
        const expected = <int>[
          -4767286540954276203,
          2949826092126892291,
          5139283748462763858,
          6349198060258255764,
          701532786141963250,
          -2430762948046562554,
          4028864712777624925,
          -3677692746721775708,
        ];

        final rng = SeededRng(42);
        for (var i = 0; i < expected.length; i++) {
          expect(
            rng.nextInt64(),
            expected[i],
            reason: 'draw $i for seed 42 must match the reference exactly',
          );
        }
      },
    );

    test('splitmix64 nextInt64 matches the independent reference for the large '
        'seed 1234567890123456789', () {
      // Unsigned: 0x9904EEE77E231DB2, 0x70EE7EB0313EC9B8, 0x77005BF062E5F76F,
      // 0xA205DFB3DFFA7EDB, 0xAD9B5F369EB21CE8, 0x63F327879359C99,
      // 0xB5628EB1FFB7E9C1, 0x6FECB54CDC505219.
      const expected = <int>[
        -7420543607978648142,
        8137580871910607288,
        8574954778522941295,
        -6771760501031797029,
        -5937046995562521368,
        450133980771359897,
        -5376578109976352319,
        8065020374432109081,
      ];

      final rng = SeededRng(1234567890123456789);
      for (var i = 0; i < expected.length; i++) {
        expect(
          rng.nextInt64(),
          expected[i],
          reason: 'draw $i for the large seed must match the reference exactly',
        );
      }
    });

    test(
      'splitmix64 nextInt64 matches the independent reference for the largest '
      'seed 2^63 - 1',
      () {
        // Unsigned: 0x2A67D7552E039EA7, 0xF20C01408082F947, 0xEC159351AF424190,
        // 0x2020319894995BFB, 0x532168FD38C3F6CB, 0x1CD287CC27FEE113,
        // 0x2D2C3418A72BFF27, 0x8C0F2BC06B2765D6.
        const expected = <int>[
          3055647633038352039,
          -1005427240264861369,
          -1435078927205645936,
          2314904739866303483,
          5990184416167851723,
          2076871689085313299,
          3255033911170563879,
          -8354410678317521450,
        ];

        final rng = SeededRng(9223372036854775807);
        for (var i = 0; i < expected.length; i++) {
          expect(
            rng.nextInt64(),
            expected[i],
            reason:
                'draw $i for the largest seed must match the reference '
                'exactly',
          );
        }
      },
    );

    test(
      'splitmix64 nextDouble matches the independent reference for seed 0',
      () {
        // The 53-bit projections of the seed-0 draws above.
        const expected = <double>[
          0.8833108082136426,
          0.43152799704850997,
          0.026433771592597743,
          0.9708819781538285,
        ];

        final rng = SeededRng(0);
        for (var i = 0; i < expected.length; i++) {
          expect(
            rng.nextDouble(),
            expected[i],
            reason: 'draw $i for seed 0 must match the reference exactly',
          );
        }
      },
    );

    test(
      'splitmix64 nextDouble matches the independent reference for seed 42',
      () {
        // The 53-bit projections of the seed-42 draws above.
        const expected = <double>[
          0.7415648787718233,
          0.1599103928769201,
          0.27860113025513866,
          0.34419071652363753,
        ];

        final rng = SeededRng(42);
        for (var i = 0; i < expected.length; i++) {
          expect(
            rng.nextDouble(),
            expected[i],
            reason: 'draw $i for seed 42 must match the reference exactly',
          );
        }
      },
    );

    test('two fresh instances reproduce the same golden vector', () {
      // The batch-invariance claim rests on this: a request that carries a
      // seed reproduces in isolation, so a fresh instance must emit the
      // very same bytes as the reference — not merely "the same as some
      // other instance".
      const expected = <int>[
        -4767286540954276203,
        2949826092126892291,
        5139283748462763858,
        6349198060258255764,
        701532786141963250,
        -2430762948046562554,
        4028864712777624925,
        -3677692746721775708,
      ];

      for (final instance in [SeededRng(42), SeededRng(42)]) {
        for (var i = 0; i < expected.length; i++) {
          expect(
            instance.nextInt64(),
            expected[i],
            reason:
                'a fresh instance must replay the reference vector, '
                'draw $i',
          );
        }
      }
    });
  });
}
