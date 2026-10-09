import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart';

/// ADR 0054 R3 CALIBRATION gate: the engine with LAYA_Q8=1 (alternate
/// encoder layers affine-quantized to 8-bit at group 32 — the scope the
/// 2026-10-09 sensitivity study landed, see into_q8) must hold
///   - argmax agreement on every golden question (63/63),
///   - choice-probability drift ≤ 2e-2 vs the fp16 fixture,
///   - score/noul drift < 2e-2 (the fixture's own tolerance),
/// measured against the SAME fixture the fp16 oracle uses
/// (test/fixtures/laya_golden_fp16.json). The fixture is never regenerated
/// for this gate — a drift above 0.02 is a gate failure recorded in the
/// ADR, not a fixture change.
///
/// Skips honestly when the env, dylib, weights, or fixture are absent:
///   LAYA_Q8=1 dart test test/laya_native_q8_calibration_test.dart
void main() {
  final goldenFile = File('test/fixtures/laya_golden_fp16.json');
  final q8 = Platform.environment['LAYA_Q8'];

  test('q8 engine holds the calibration gates against the fp16 fixture',
      () async {
    if (q8 == null || q8.isEmpty) {
      return markTestSkipped('LAYA_Q8 not set — run with LAYA_Q8=1');
    }
    if (!goldenFile.existsSync()) {
      return markTestSkipped('golden fixture absent');
    }
    final NativeLayaDecisionEngine engine;
    try {
      engine = await NativeLayaDecisionEngine.load();
    } on Object catch (error) {
      return markTestSkipped('native artifacts absent: $error');
    }
    addTearDown(engine.dispose);

    final cases =
        jsonDecode(goldenFile.readAsStringSync()) as List<dynamic>;

    var questions = 0;
    var argmaxAgreements = 0;
    var maxProbError = 0.0;
    var maxOutputDrift = 0.0;
    for (final rawCase in cases) {
      final golden = rawCase as Map<String, dynamic>;
      final decisions = engine.decideTyped(
        state: _serializeState(golden['state']),
        questions: {
          for (final entry
              in (golden['questions'] as Map).entries.cast<MapEntry<String, dynamic>>())
            entry.key: _typedQuestion(entry.value as Map<String, dynamic>),
        },
      );
      final answers = golden['answers'] as Map<String, dynamic>;
      for (final entry in answers.entries) {
        final expected = entry.value as Map<String, dynamic>;
        final actual = decisions[entry.key]!;
        questions++;

        switch (expected['type'] as String) {
          case 'choice':
            if (expected['choice'] == actual.choice) {
              argmaxAgreements++;
            } else {
              // ignore: avoid_print
              print('MISMATCH ${entry.key} (${expected['type']}): '
                  'want ${expected['choice']}, got ${actual.choice}, '
                  'probs ${expected['probabilities']}');
            }
          case 'score':
            final expectedScore = (expected['score'] as num).toDouble();
            final drift = (expectedScore - actual.score!).abs();
            maxOutputDrift = maxDouble(maxOutputDrift, drift);
            if (drift < 0.02) {
              argmaxAgreements++;
            } else {
              // ignore: avoid_print
              print('MISMATCH ${entry.key} (score): want $expectedScore, '
                  'got ${actual.score}, drift $drift');
            }
          case 'noul':
            final expectedNoul = (expected['noul'] as num).toDouble();
            final drift = (expectedNoul - actual.noul!).abs();
            maxOutputDrift = maxDouble(maxOutputDrift, drift);
            if (drift < 0.02) {
              argmaxAgreements++;
            } else {
              // ignore: avoid_print
              print('MISMATCH ${entry.key} (noul): want $expectedNoul, '
                  'got ${actual.noul}, drift $drift');
            }
        }
        final expectedProbs = expected['probabilities'];
        if (expectedProbs is Map) {
          for (final prob in expectedProbs.entries) {
            maxProbError = maxDouble(
              maxProbError,
              ((prob.value as num).toDouble() - actual.probabilities[prob.key]!)
                  .abs(),
            );
          }
        }
      }
    }

    // CALIBRATION gates (ADR 0054 R3): never weakened, never bypassed.
    expect(argmaxAgreements, questions,
        reason: 'q8 argmax agreements $argmaxAgreements/$questions');
    expect(maxProbError, lessThanOrEqualTo(0.02),
        reason: 'q8 choice-prob drift $maxProbError exceeds 2e-2');
    expect(maxOutputDrift, lessThan(0.02),
        reason: 'q8 score/noul drift $maxOutputDrift exceeds 2e-2');
    // ignore: avoid_print
    print('laya q8 calibration: $argmaxAgreements/$questions, '
        'max prob drift $maxProbError, max output drift $maxOutputDrift');
  }, timeout: const Timeout(Duration(minutes: 5)));
}

String _serializeState(final Object? state) =>
    state is String ? state : renderLayaJson(state);

LayaTypedQuestion _typedQuestion(final Map<String, dynamic> definition) {
  final type = definition['type'] as String;
  final instructions = definition['instructions'];
  final instructionText = instructions is String
      ? instructions
      : renderLayaJson(instructions);
  switch (type) {
    case 'choice':
      final crit = definition['criteria'];
      return LayaTypedQuestion.choice(instructionText, {
        if (crit is Map)
          for (final entry in crit.entries.cast<MapEntry<dynamic, dynamic>>())
            '${entry.key}': renderLayaCriterion(
              entry.value == null || entry.value == '' ? '' : entry.value,
            )
        else
          for (final label in crit as List) '$label': '',
      });
    case 'score':
      return LayaTypedQuestion.score(
        instructionText,
        [
          for (final level in definition['criteria'] as List)
            renderLayaCriterion(level),
        ],
      );
    case 'noul':
      final crit = definition['criteria'];
      return LayaTypedQuestion.noul(
        instructionText,
        crit is Map
            ? {
                for (final entry in crit.entries.cast<MapEntry<dynamic, dynamic>>())
                  '${entry.key}': entry.value == null
                      ? ''
                      : renderLayaCriterion(entry.value),
              }
            : null,
      );
  }
  throw FormatException('unknown golden question type $type');
}

double maxDouble(final double a, final double b) => a > b ? a : b;
