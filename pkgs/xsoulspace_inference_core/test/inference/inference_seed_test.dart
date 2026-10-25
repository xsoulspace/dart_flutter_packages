import 'dart:convert';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// The seed carrier contract (ADR 0059 — the composable request surface).
///
/// The core carries an optional integer seed end to end: both request
/// factories, the request map, the JSON codec, `copyWith`, the flat
/// `GenerationOptions` view and the options codec. What a provider does with
/// the value is the provider's business — it maps the seed to its own wire
/// parameter or reports an explicit warning. Core states no determinism.
void main() {
  group('InferenceRequest seed carrier', () {
    test('an unseeded request carries no seed at all', () {
      for (final request in [
        InferenceRequest(prompt: 'p'),
        InferenceRequest.structured(prompt: 'p'),
      ]) {
        expect(request.seed, isNull);
        expect(
          request.value.containsKey('seed'),
          isFalse,
          reason: 'an absent seed stays absent on the wire map',
        );
        expect(request.generationOptions.seed, isNull);
        expect(
          InferenceRequest.fromJson(request.value).seed,
          isNull,
          reason: 'the codec keeps an absent seed absent',
        );
      }
    });

    test('zero is a real seed and survives every hop', () {
      for (final request in [
        InferenceRequest(prompt: 'p', seed: 0),
        InferenceRequest.structured(prompt: 'p', seed: 0),
      ]) {
        expect(request.seed, 0);
        expect(request.value['seed'], 0);
        expect(
          request.value.containsKey('seed'),
          isTrue,
          reason: 'zero is carried, not dropped as absent',
        );
        expect(request.generationOptions.seed, 0);
        expect(InferenceRequest.fromJson(request.value).seed, 0);
        expect(request.copyWith(prompt: 'next').seed, 0);
        expect(
          request.copyWith(prompt: 'next').generationOptions.seed,
          0,
          reason: 'the options view keeps the zero seed',
        );
      }
    });

    test('a nonzero seed round-trips, copies, and composes', () {
      for (final request in [
        InferenceRequest(prompt: 'p', seed: 7),
        InferenceRequest.structured(prompt: 'p', seed: 7),
      ]) {
        expect(request.seed, 7);
        expect(request.value['seed'], 7);

        final restored = InferenceRequest.fromJson(
          jsonDecode(jsonEncode(request.value)) as Map<String, dynamic>,
        );
        expect(restored.seed, 7);
        expect(restored.generationOptions.seed, 7);

        final derived = request.copyWith(prompt: 'next', maxTokens: 64);
        expect(derived.seed, 7, reason: 'copyWith retains the seed');
        expect(derived.maxTokens, 64);
        expect(
          request.seed,
          7,
          reason: 'derivation never mutates the source request',
        );
      }
    });
  });

  group('GenerationOptions seed carrier', () {
    test('composes, copies, and JSON round-trips', () {
      const options = GenerationOptions(seed: 3);
      expect(options.toJson()['seed'], 3);
      expect(
        GenerationOptions.fromJson(
          jsonDecode(jsonEncode(options.toJson())) as Map<String, dynamic>,
        ).seed,
        3,
      );
      expect(
        options.copyWith(maxTokens: 128).seed,
        3,
        reason: 'copying other knobs retains the seed',
      );
    });

    test('empty options carry no seed on the wire map', () {
      expect(const GenerationOptions().toJson(), <String, dynamic>{});
      expect(GenerationOptions.fromJson(const {}).seed, isNull);
    });

    test('a zero seed round-trips through the options codec', () {
      const options = GenerationOptions(seed: 0);
      expect(options.toJson()['seed'], 0);
      expect(options.toJson().containsKey('seed'), isTrue);
      expect(GenerationOptions.fromJson(options.toJson()).seed, 0);
    });

    test('a model composes the seed with its other options', () {
      const model = Model(
        id: ModelId('seeded'),
        generationOptions: GenerationOptions(maxTokens: 128, seed: 5),
      );
      expect(model.generationOptions.seed, 5);
      expect(model.generationOptions.maxTokens, 128);
    });
  });

  test('the seed meta key is a stable, non-empty name', () {
    expect(inferenceSeedMetaKey, isNotEmpty);
    expect(inferenceSeedMetaKey, inferenceSeedMetaKey);
  });
}
