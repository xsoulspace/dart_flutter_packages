import 'dart:convert';
import 'dart:io';

import 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart';

/// R3b q8 latency probe (ADR 0054 evidence): median decision latency of the
/// loaded engine config (fp16, or LAYA_Q8=1 alternate-layer g32) over the
/// golden fixture cases. One config per process; reps over all cases; p50/p90.
LayaTypedQuestion _typedQuestion(final Map<String, dynamic> definition) {
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
                for (final entry
                    in crit.entries.cast<MapEntry<dynamic, dynamic>>())
                  '${entry.key}': entry.value == null
                      ? ''
                      : renderLayaCriterion(entry.value),
              }
            : null,
      );
  }
  throw FormatException('unknown golden question type $type');
}

Future<void> main(List<String> args) async {
  final reps = args.isNotEmpty ? int.parse(args.first) : 30;
  final goldenFile = File('test/fixtures/laya_golden_fp16.json');
  if (!goldenFile.existsSync()) {
    stderr.writeln('golden fixture absent');
    exit(66);
  }
  final cases = (jsonDecode(goldenFile.readAsStringSync()) as List<dynamic>)
      .cast<Map<String, dynamic>>();

  final engine = await NativeLayaDecisionEngine.load();
  Map<String, LayaTypedQuestion> questionsOf(Map<String, dynamic> golden) => {
        for (final entry
            in (golden['questions'] as Map).entries.cast<MapEntry<String, dynamic>>())
          entry.key: _typedQuestion(entry.value as Map<String, dynamic>),
      };

  // Warm-up pass (plan build, Metal pipeline caching).
  for (final golden in cases) {
    engine.decideTyped(
      state: golden['state'] is String
          ? golden['state'] as String
          : renderLayaJson(golden['state']),
      questions: questionsOf(golden),
    );
  }

  final samples = <double>[];
  for (var r = 0; r < reps; r++) {
    for (final golden in cases) {
      final sw = Stopwatch()..start();
      engine.decideTyped(
        state: golden['state'] is String
            ? golden['state'] as String
            : renderLayaJson(golden['state']),
        questions: questionsOf(golden),
      );
      sw.stop();
      samples.add(sw.elapsedMicroseconds / 1000.0);
    }
  }
  samples.sort();
  final p50 = samples[samples.length ~/ 2];
  final p90 =
      samples[(samples.length * 0.9).floor().clamp(0, samples.length - 1)];
  // ignore: avoid_print
  print('config=${Platform.environment['LAYA_Q8'] == null ? 'fp16' : 'q8-alt-g32'} '
      'n=${samples.length} p50=${p50.toStringAsFixed(2)}ms '
      'p90=${p90.toStringAsFixed(2)}ms');
  engine.dispose();
}
