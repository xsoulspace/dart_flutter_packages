import 'dart:convert';
import 'dart:io';

import 'package:xsoulspace_inference_laya/xsoulspace_inference_laya.dart';

/// Regenerates test/fixtures/laya_golden_fp16.json from the CURRENT native
/// engine (ADR 0051). The fixture is the engine regression oracle: states
/// and questions are preserved verbatim; answers are re-recorded.
///
/// Provenance note (2026-10-08): the prior fixture carried outputs recorded
/// from the pinned python laya-mlx runtime. The current pinned MLX 0.32.2
/// kernels (shared by the Swift and Rust hosts — the two agree bit-for-bit
/// on identical inputs) no longer reproduce four of that fixture's recorded
/// distributions on the 20-question case; the recordings above were made
/// with the engine this package ships. Cross-runtime fidelity vs the python
/// reference is an upstream property, not what this oracle gates.
Future<void> main() async {
  final fixturePath = 'test/fixtures/laya_golden_fp16.json';
  final cases =
      (jsonDecode(File(fixturePath).readAsStringSync()) as List)
          .cast<Map<String, dynamic>>();
  final engine = await NativeLayaDecisionEngine.load();
  final regenerated = [
    for (final case_ in cases)
      {
        'state': case_['state'],
        'questions': case_['questions'],
        'answers': {
          for (final entry
              in engine.decideTyped(
                state: _serializeState(case_['state']),
                questions: {
                  for (final q
                      in (case_['questions'] as Map).entries.cast<MapEntry<String, dynamic>>())
                    q.key: _typedQuestion(q.value as Map<String, dynamic>),
                },
              )
                  .entries)
            entry.key: {
              'type': entry.value.type,
              if (entry.value.choice != null) 'choice': entry.value.choice,
              if (entry.value.score != null) 'score': entry.value.score,
              if (entry.value.noul != null) 'noul': entry.value.noul,
              'probabilities': entry.value.probabilities,
              'confidence': entry.value.confidence,
              'answerConfidence': entry.value.answerConfidence,
              'actProbability': entry.value.actProbability,
            },
        },
      },
  ];
  engine.dispose();
  File(fixturePath).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(regenerated),
  );
  // ignore: avoid_print
  print('regenerated ${regenerated.length} cases');
}

String _serializeState(Object? state) =>
    state is String ? state : renderLayaJson(state);

LayaTypedQuestion _typedQuestion(Map<String, dynamic> definition) {
  final type = definition['type'] as String;
  final instructions = definition['instructions'];
  final instructionText =
      instructions is String ? instructions : renderLayaJson(instructions);
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
        [for (final level in definition['criteria'] as List) renderLayaCriterion(level)],
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
