/// Laws of keyed certifications (PROGRAM.md Phase E / V-6): drift outside
/// the key is a new claim, and every drifted field must be NAMED — an empty
/// mismatch list is the only "same key".
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_weightmap/src/receipts.dart';

CertificationKey baseKey({
  String? baseDigest,
  String? tokenizerDigest,
  String quant = 'bf16',
  Map<String, Object?>? samplerConfig,
  String engineRev = 'mlx_native@rev-2026-11-05',
  String? batteryDigest,
}) => CertificationKey(
  baseDigest: baseDigest ?? 'aa' * 32,
  tokenizerDigest: tokenizerDigest ?? 'bb' * 32,
  quant: quant,
  samplerConfig: samplerConfig ??
      const {
        'greedy': true,
        'temperature': 0.0,
        'maxNewTokens': 32768,
        'budget': {'suite': 'MATH-500', 'cap': 32768},
      },
  engineRev: engineRev,
  batteryDigest: batteryDigest ?? 'cc' * 32,
);

void main() {
  test('fieldLabels is the frozen six-field vocabulary', () {
    expect(CertificationKey.fieldLabels, [
      'BASE_DIGEST',
      'TOKENIZER_DIGEST',
      'QUANT',
      'SAMPLER_CONFIG',
      'ENGINE_REV',
      'BATTERY_DIGEST',
    ]);
  });

  test('same key: matches names nothing', () {
    final k = baseKey();
    final copy = CertificationKey.fromJson(k.toJson());
    expect(k.matches(copy), isEmpty);
    expect(k.sameKeyAs(copy), isTrue);
    expect(k, copy);
    expect(k.hashCode, copy.hashCode);
  });

  test('each drifted field is named exactly', () {
    final k = baseKey();
    final drifts = <String, CertificationKey>{
      'BASE_DIGEST': baseKey(baseDigest: 'dd' * 32),
      'TOKENIZER_DIGEST': baseKey(tokenizerDigest: 'ee' * 32),
      'QUANT': baseKey(quant: '4bit'),
      'SAMPLER_CONFIG': baseKey(samplerConfig: const {'greedy': false}),
      'ENGINE_REV': baseKey(engineRev: 'mlx_native@rev-next'),
      'BATTERY_DIGEST': baseKey(batteryDigest: 'ff' * 32),
    };
    for (final label in CertificationKey.fieldLabels) {
      expect(k.matches(drifts[label]!), [label], reason: 'drift on $label');
      expect(drifts[label]!.matches(k), [label]); // symmetric
      expect(k.sameKeyAs(drifts[label]!), isFalse);
    }
  });

  test('multiple drifts are all named, in the stable canonical order', () {
    final k = baseKey();
    final drifted = baseKey(quant: '4bit', baseDigest: 'dd' * 32);
    // Named in fieldLabels order regardless of construction order.
    expect(k.matches(drifted), ['BASE_DIGEST', 'QUANT']);
  });

  test('samplerConfig: key order irrelevant, numeric type strict', () {
    final k = baseKey();
    // Same config, different insertion order and a re-typed equal value:
    final reordered = baseKey(samplerConfig: const {
      'budget': {'cap': 32768, 'suite': 'MATH-500'},
      'maxNewTokens': 32768,
      'temperature': 0.0,
      'greedy': true,
    });
    expect(k.matches(reordered), isEmpty);

    // Pre-registered strictness: 0 (int) is NOT 0.0 (double). A config whose
    // value types changed is not the frozen config.
    final retyped = baseKey(samplerConfig: const {
      'greedy': true,
      'temperature': 0,
      'maxNewTokens': 32768,
      'budget': {'suite': 'MATH-500', 'cap': 32768},
    });
    expect(k.matches(retyped), ['SAMPLER_CONFIG']);

    // Nested drift is drift.
    final nested = baseKey(samplerConfig: const {
      'greedy': true,
      'temperature': 0.0,
      'maxNewTokens': 32768,
      'budget': {'suite': 'GSM8K', 'cap': 32768},
    });
    expect(k.matches(nested), ['SAMPLER_CONFIG']);
  });

  test('json round-trip preserves equality', () {
    final k = baseKey();
    final wire = jsonEncode(k.toJson());
    final k2 = CertificationKey.fromJson(
      jsonDecode(wire) as Map<String, Object?>,
    );
    expect(k2, k);
    expect(k2.matches(k), isEmpty);
    expect(k2.toJson(), k.toJson());
    expect(k2.canonical(), k.canonical());
  });

  test('fromJson names missing and malformed fields', () {
    final full = baseKey().toJson();

    final missing = Map<String, Object?>.from(full)..remove('quant');
    expect(
      () => CertificationKey.fromJson(missing),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('MISSING_FIELD=quant'),
        ),
      ),
    );

    final missingSampler = Map<String, Object?>.from(full)
      ..remove('samplerConfig');
    expect(
      () => CertificationKey.fromJson(missingSampler),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('MISSING_FIELD=samplerConfig'),
        ),
      ),
    );

    final wrongType = Map<String, Object?>.from(full)..['engineRev'] = 42;
    expect(
      () => CertificationKey.fromJson(wrongType),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('MALFORMED_FIELD=engineRev'),
        ),
      ),
    );

    final wrongSampler = Map<String, Object?>.from(full)
      ..['samplerConfig'] = 'greedy';
    expect(
      () => CertificationKey.fromJson(wrongSampler),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('MALFORMED_FIELD=samplerConfig'),
        ),
      ),
    );
  });

  test('canonical form is stable text a receipt can digest', () {
    final k = baseKey();
    expect(k.canonical(), startsWith('{"baseDigest":"'));
    expect(k.canonical(), k.canonical());
    expect('$k', contains('CertificationKey('));
  });
}
