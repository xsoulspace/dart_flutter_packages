import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart';

/// The probability tolerance for a batched-vs-independent comparison.
///
/// The engine's own softmax (`decideTyped` in
/// laya_native_decision_engine.dart) runs in float64 on float32 logits, so
/// the softmax arithmetic contributes ~1e-16 and sets no floor. The floor is
/// set upstream, by the native forward: the trunk stores its activations in
/// float16 (model.rs: `ACT_DTYPE = Float16`), so a forward that batches
/// differently re-rounds intermediate activations at float16 granularity, and
/// the resulting logit shift propagates through the softmax. The softmax is
/// 1-Lipschitz in the max norm (|dp_i| <= max|d logit_j| / scale), and the
/// shipped calibration scales for these buckets are >= 1.25.
///
/// Measured on this machine against the fp16 laya-mlx checkpoint:
///   * a pure batch-SIZE change (same row, repeated) moved a probability by
///     at most 3.6e-4 — the float16 re-rounding floor;
///   * the native heterogeneous-batch path moved a probability by up to
///     0.86 on the SHORT rows (2 and 3 option markers) and by ~1.2e-4 to
///     3.6e-4 on the rows at the batch's full marker width.
///
/// 1e-3 admits the float16 re-rounding floor with ~3x headroom and rejects
/// the short-row defect by three orders of magnitude. 1e-6/1e-5 are NOT
/// defensible: they assume the native logits are bit-identical across
/// batch shapes, which a float16 trunk cannot deliver.
const double _probabilityTolerance = 1e-3;

/// The categorical decision a question resolves to — never a float: the
/// chosen option label for a choice question, the modal level for a score
/// question, the true/false side for a noul question.
///
/// The categorical verdict is compared with `==` (exact). The calibrated
/// readings (`score`, `noul`, the probability map) are floats and are
/// compared with [_probabilityTolerance]. A different verdict is a
/// different answer, not a rounding difference.
String _decision(LayaTypedDecision decision) {
  switch (decision.type) {
    case 'choice':
      return decision.choice!;
    case 'score':
    case 'noul':
      return _argmaxLabel(decision.probabilities);
  }
  throw StateError('unknown decision type ${decision.type}');
}

/// The label whose probability is highest, first-wins on a tie — the same
/// tie-break the engine's own argmax loop uses.
String _argmaxLabel(Map<String, double> probabilities) {
  var best = probabilities.keys.first;
  for (final entry in probabilities.entries) {
    if (entry.value > probabilities[best]!) {
      best = entry.key;
    }
  }
  return best;
}

/// The decision engine's batch-isolation contract, in the spirit of
/// DeepInfer's `DEEPINFER_BATCH_INVARIANT`: the DECISION a question
/// resolves to must not depend on which other questions share its batch, and
/// the published distribution must agree to within float tolerance.
///
/// The DECISION is compared exactly (`==`) — a different answer is a
/// different answer, never a rounding difference. The DISTRIBUTION is
/// compared with [_probabilityTolerance], because a native forward that
/// batches differently re-rounds its float16 activations and so returns
/// slightly different logits.
///
/// The batch is the 20-question fixture case: mixed choice/score/noul rows
/// of different marker widths (4, 3 and 2), i.e. the heterogeneous shape
/// whose shorter-row defect this contract exists to catch. Today the drift
/// through this public surface is exactly 0.0, because the Dart layer still
/// splits a multi-question batch into per-row native forwards (see
/// `forwardRows` in laya_native_decision_engine.dart). The tolerance is
/// sized for the shape the contract must keep holding once that split goes
/// away and the native path batches for real: it admits the float16
/// re-rounding floor and rejects the short-row defect by three orders of
/// magnitude.
///
/// Skips honestly (with the reason) when the golden fixture or the native
/// artifacts are absent; runs by default otherwise.
void main() {
  File? goldenFile;

  setUpAll(() async {
    goldenFile = await _goldenFixture();
  });

  test(
    'native mixed question batch agrees with each independent request',
    () async {
      final fixture = goldenFile;
      if (fixture == null) {
        return markTestSkipped('golden fixture absent');
      }
      final NativeLayaDecisionEngine engine;
      try {
        engine = await NativeLayaDecisionEngine.load();
      } on Object catch (error) {
        return markTestSkipped('native artifacts absent: $error');
      }
      addTearDown(engine.dispose);

      // The 20-question case: the widest heterogeneous batch the fixture
      // holds, so a batch-shape effect has every row width to act on.
      final cases = jsonDecode(fixture.readAsStringSync()) as List<dynamic>;
      final golden = cases.firstWhere(
        (candidate) =>
            (candidate as Map)['questions'] is Map &&
            ((candidate['questions'] as Map).length > 3),
        orElse: () => cases.first,
      ) as Map<String, dynamic>;

      final questions = <String, LayaTypedQuestion>{
        for (final entry
            in (golden['questions'] as Map).entries
                .cast<MapEntry<String, dynamic>>())
          entry.key: _typedQuestion(entry.value as Map<String, dynamic>),
      };
      final state = renderLayaJson(golden['state']);

      final batched = engine.decideTyped(state: state, questions: questions);
      for (final entry in questions.entries) {
        final independent = engine.decideTyped(
          state: state,
          questions: {entry.key: entry.value},
        )[entry.key]!;
        final inBatch = batched[entry.key]!;

        expect(
          _decision(inBatch),
          _decision(independent),
          reason:
              '${entry.key}: another question must not change this actor '
              'evidence decision',
        );

        for (final probability in independent.probabilities.entries) {
          expect(
            inBatch.probabilities[probability.key],
            closeTo(probability.value, _probabilityTolerance),
            reason:
                '${entry.key}/${probability.key}: another question must not '
                'change this actor evidence decision',
          );
        }

        if (independent.type == 'score') {
          // score = sum(level * p[level]) over `levels` levels, so its drift
          // is bounded by the sum of the level indices times the tolerance.
          final levels = independent.probabilities.length;
          expect(
            inBatch.score,
            closeTo(
              independent.score!,
              _probabilityTolerance * (levels * (levels - 1) / 2),
            ),
            reason:
                '${entry.key}: another question must not change this actor '
                'evidence decision',
          );
        }
        if (independent.type == 'noul') {
          // noul = p(true), one of the probabilities already compared above.
          expect(
            inBatch.noul,
            closeTo(independent.noul!, _probabilityTolerance),
            reason:
                '${entry.key}: another question must not change this actor '
                'evidence decision',
          );
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

/// The golden fixture, resolved from the package root when the test runs
/// from the workspace root, and package-relative otherwise. The package's
/// own `just test-one` runs with the package directory as the working
/// directory; the fallback keeps the test from false-skipping when it is
/// run from the workspace root.
Future<File?> _goldenFixture() async {
  final root = await resolveNativePackageRoot();
  for (final path in [
    if (root != null) '$root/test/fixtures/laya_golden_fp16.json',
    'test/fixtures/laya_golden_fp16.json',
  ]) {
    final file = File(path);
    if (file.existsSync()) return file;
  }
  return null;
}

LayaTypedQuestion _typedQuestion(Map<String, dynamic> definition) {
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
      return LayaTypedQuestion.score(instructionText, [
        for (final level in definition['criteria'] as List)
          renderLayaCriterion(level),
      ]);
    case 'noul':
      final crit = definition['criteria'];
      return LayaTypedQuestion.noul(
        instructionText,
        crit is Map
            ? {
                for (final entry
                    in crit.entries.cast<MapEntry<dynamic, dynamic>>())
                  '${entry.key}': renderLayaCriterion(
                    entry.value == null || entry.value == '' ? '' : entry.value,
                  ),
              }
            : null,
      );
  }
  throw FormatException('unknown golden question type $type');
}
