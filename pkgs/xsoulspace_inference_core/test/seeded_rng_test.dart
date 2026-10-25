import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// The sanctioned draw for a seeded request (ADR 0071 — the seed carrier).
///
/// The property under test is that a draw depends only on (seed, position):
/// it never depends on global RNG state, on how many other requests are in
/// flight, or on how many positions were drawn before it. That is what
/// makes a seeded request reproducible in isolation.
void main() {
  group('SeededRng determinism', () {
    test('the same seed produces the same sequence', () {
      final first = SeededRng(42);
      final second = SeededRng(42);

      for (var i = 0; i < 64; i++) {
        expect(
          first.nextDouble(),
          second.nextDouble(),
          reason: 'draw $i must match for the same seed',
        );
      }
    });

    test('different seeds produce divergent sequences', () {
      final first = SeededRng(42);
      final second = SeededRng(43);

      final firstSequence = List<double>.generate(
        32,
        (_) => first.nextDouble(),
      );
      final secondSequence = List<double>.generate(
        32,
        (_) => second.nextDouble(),
      );

      expect(
        firstSequence,
        isNot(equals(secondSequence)),
        reason: 'two different seeds must not walk the same path',
      );
    });

    test('a fresh instance reproduces the same sequence', () {
      final original = SeededRng(7);
      final originalSequence = List<double>.generate(
        32,
        (_) => original.nextDouble(),
      );

      // A brand new instance starts from position zero again, so the
      // sequence is a function of (seed, position) and not of history.
      final replay = SeededRng(7);
      final replaySequence = List<double>.generate(
        32,
        (_) => replay.nextDouble(),
      );

      expect(replaySequence, equals(originalSequence));
    });

    test('other instances do not perturb the sequence', () {
      final target = SeededRng(1234);
      final expected = List<double>.generate(32, (_) => target.nextDouble());

      // Consume a lot of other generators in between: if the draw read any
      // global state, this sequence would differ.
      final targetReplay = SeededRng(1234);
      final observed = <double>[];
      for (var i = 0; i < 32; i++) {
        final noise = SeededRng(i);
        for (var j = 0; j < 8; j++) {
          noise.nextDouble();
          noise.nextInt64();
        }
        observed.add(targetReplay.nextDouble());
      }

      expect(observed, equals(expected));
    });

    test('the seed is readable back', () {
      expect(SeededRng(99).seed, 99);
      expect(SeededRng(0).seed, 0);
    });
  });

  group('SeededRng nextDouble', () {
    test('stays in [0, 1)', () {
      final rng = SeededRng(2024);
      for (var i = 0; i < 10000; i++) {
        final value = rng.nextDouble();
        expect(value, greaterThanOrEqualTo(0.0));
        expect(value, lessThan(1.0));
      }
    });

    test('uses more than 32 bits of precision', () {
      final rng = SeededRng(5);
      final values = List<double>.generate(2000, (_) => rng.nextDouble());

      // Scale by 2^53: a 53-bit value becomes a whole number below 2^53.
      // A 32-bit double would land on a multiple of 2^21 there, so
      // requiring a non-multiple proves more than 32 bits are in play.
      const twoPow53 = 9007199254740992.0;
      const twoPow21 = 2097152;
      final fine = values
          .map((value) => (value * twoPow53).round())
          .where((scaled) => scaled % twoPow21 != 0)
          .length;
      expect(
        fine,
        greaterThan(values.length ~/ 2),
        reason: 'the draw must carry bits below the 32nd',
      );
    });
  });

  group('SeededRng nextInt', () {
    test('stays in [0, max)', () {
      final rng = SeededRng(31337);
      for (final max in [1, 2, 3, 7, 16, 1000]) {
        for (var i = 0; i < 2000; i++) {
          final value = rng.nextInt(max);
          expect(value, greaterThanOrEqualTo(0));
          expect(value, lessThan(max));
        }
      }
    });

    test('is unbiased across buckets', () {
      const max = 8;
      const draws = 10000;
      final rng = SeededRng(20240607);
      final buckets = List<int>.filled(max, 0);

      for (var i = 0; i < draws; i++) {
        buckets[rng.nextInt(max)] += 1;
      }

      const expected = draws / max;
      // The 95% band for a binomial bucket is about 2 * sqrt(n * p * (1-p)),
      // which is about 66 counts here. The band below is 5x that, so it
      // cannot flake on an unlucky but legitimate draw, while a modulo-
      // biased generator would be off by far more than 5 sigma.
      const tolerance = expected * 0.15;
      for (var bucket = 0; bucket < max; bucket++) {
        expect(
          buckets[bucket],
          closeTo(expected, tolerance),
          reason: 'bucket $bucket must hold its fair share of the draws',
        );
      }
    });

    test('max == 1 returns 0', () {
      final rng = SeededRng(1);
      for (var i = 0; i < 10; i++) {
        expect(rng.nextInt(1), 0);
      }
    });

    test('a non-positive max fails loudly', () {
      final rng = SeededRng(1);

      expect(() => rng.nextInt(0), throwsArgumentError);
      expect(() => rng.nextInt(-1), throwsArgumentError);
    });
  });

  group('SeededRng seed bounds', () {
    test('seed 0 and the largest positive seed both work', () {
      final zero = SeededRng(0);
      final largest = SeededRng(9223372036854775807);

      expect(zero.nextDouble(), greaterThanOrEqualTo(0.0));
      expect(zero.nextDouble(), lessThan(1.0));
      expect(largest.nextDouble(), greaterThanOrEqualTo(0.0));
      expect(largest.nextDouble(), lessThan(1.0));
      expect(zero.nextInt64(), isNot(equals(largest.nextInt64())));
    });

    test('a negative seed is rejected loudly', () {
      expect(() => SeededRng(-1), throwsArgumentError);
    });

    test('a negative seed is rejected by the validator too', () {
      expect(isValidInferenceSeed(-1), isFalse);
      expect(
        inferenceSeedError(-1),
        contains('0 <= seed'),
        reason: 'the reason must name the accepted range',
      );
    });
  });
}
