import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// The seed range contract of ADR 0071 — the seed carrier.
///
/// The carrier states no determinism; what it does state is that a seed is
/// an integer in `[0, 2^63)`. This is the validation that makes that
/// contract enforceable, and it is checked where a caller actually looks:
/// on the request.
void main() {
  group('inference seed range', () {
    test('null is valid — no seed requested is not an invalid seed', () {
      expect(isValidInferenceSeed(null), isTrue);
      expect(inferenceSeedError(null), isNull);
    });

    test('zero is a real seed and is valid', () {
      expect(isValidInferenceSeed(0), isTrue);
      expect(inferenceSeedError(0), isNull);
    });

    test('the largest seed below the bound is valid', () {
      const largest = 9223372036854775807; // 2^63 - 1
      expect(isValidInferenceSeed(largest), isTrue);
      expect(inferenceSeedError(largest), isNull);
    });

    test('the exclusive upper bound itself is invalid', () {
      // 2^63 is not representable as a Dart int on the VM, so the bound is
      // checked through the value the contract names.
      expect(inferenceSeedUpperBound, BigInt.one << 63);
      expect(inferenceSeedUpperBound, BigInt.parse('9223372036854775808'));
      expect(
        isValidInferenceSeed(9223372036854775808.0),
        isFalse,
        reason: '2^63 is outside the range',
      );
    });

    test('a negative seed is invalid', () {
      expect(isValidInferenceSeed(-1), isFalse);
      expect(inferenceSeedError(-1), isNotNull);
    });

    test('a huge value is invalid', () {
      expect(isValidInferenceSeed(1e30), isFalse);
      expect(inferenceSeedError(1e30), isNotNull);
    });

    test('a non-integer is invalid', () {
      expect(isValidInferenceSeed(1.5), isFalse);
      expect(inferenceSeedError(1.5), contains('integer'));
    });

    test('the error message names the bound', () {
      final error = inferenceSeedError(-1);
      expect(error, isNotNull);
      expect(
        error,
        contains('9223372036854775808'),
        reason: 'a caller must learn the contract, not just "invalid"',
      );
      expect(error, contains('0 <= seed'));
    });
  });

  group('validateInferenceSeed', () {
    test('accepts a valid seed and an absent seed', () {
      expect(validateInferenceSeed(null).success, isTrue);
      expect(validateInferenceSeed(0).success, isTrue);
      expect(validateInferenceSeed(42).success, isTrue);
    });

    test('reports the first problem with an invalid seed', () {
      final result = validateInferenceSeed(-1);
      expect(result.success, isFalse);
      expect(result.error?.code, errorCodeInferenceSeedInvalid);
      expect(result.error?.message, contains('9223372036854775808'));
    });
  });

  group('validateInferenceRequest with a seed', () {
    test('a request with a valid seed still validates', () {
      final result = validateInferenceRequest(
        InferenceRequest(prompt: 'hello', seed: 7),
      );
      expect(result.success, isTrue);
    });

    test('a request with a negative seed is rejected', () {
      final result = validateInferenceRequest(
        InferenceRequest(prompt: 'hello', seed: -1),
      );
      expect(result.success, isFalse);
      expect(result.error?.code, errorCodeInferenceSeedInvalid);
    });

    test('a request without a seed still validates', () {
      final result = validateInferenceRequest(
        InferenceRequest(prompt: 'hello'),
      );
      expect(result.success, isTrue);
    });
  });
}
