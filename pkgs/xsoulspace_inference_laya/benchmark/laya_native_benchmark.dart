// Micro-benchmark for the NATIVE laya decision path (MLX via dart:ffi).
//
// Measures end-to-end decideTyped latency on the 'email' golden case
// (3 questions: choice + score + noul) and the choice-only wire shape the
// harness serves — model inference included, wire excluded (the loopback
// wire overhead is benchmarked in laya_benchmark.dart and is ~0.2ms p50).
//
// Run: dart run benchmark/laya_native_benchmark.dart [--seconds=N]
// Requires the native runtime (hook-built) and the laya-mlx weights;
// skips honestly when either is absent. Numbers are machine-relative —
// record the machine with results.
import 'dart:convert';
import 'dart:io';

import 'package:xsoulspace_inference_laya/xsoulspace_inference_laya.dart';

Future<void> main(final List<String> args) async {
  final seconds = args
      .where((a) => a.startsWith('--seconds='))
      .map((a) => int.tryParse(a.split('=').last) ?? 3)
      .first;
  final NativeLayaDecisionEngine engine;
  try {
    engine = await NativeLayaDecisionEngine.load();
  } on Object catch (error) {
    stderr.writeln('skip: $error');
    exit(0);
  }
  final golden = (jsonDecode(
          File('test/fixtures/laya_golden_fp16.json').readAsStringSync())
      as List<dynamic>)[0] as Map<String, dynamic>;
  final state = renderLayaJson(golden['state']);
  final questions = (golden['questions'] as Map<String, dynamic>)
      .map((id, def) => MapEntry(id, _typed(def as Map<String, dynamic>)));

  // Warmup (weights on GPU, kernel compile).
  for (var i = 0; i < 5; i++) {
    engine.decideTyped(state: state, questions: questions);
  }
  final latencies = <int>[];
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  var ops = 0;
  while (DateTime.now().isBefore(deadline)) {
    final watch = Stopwatch()..start();
    engine.decideTyped(state: state, questions: questions);
    latencies.add(watch.elapsedMicroseconds);
    ops++;
  }
  latencies.sort();
  double pct(final double p) =>
      latencies[(p * (latencies.length - 1)).round()] / 1000.0;
  // ignore: avoid_print
  print('native laya decideTyped (${questions.length} questions, '
      'email case): ops=$ops in ${seconds}s, '
      'p50=${pct(0.5).toStringAsFixed(1)}ms '
      'p99=${pct(0.99).toStringAsFixed(1)}ms '
      'max=${pct(1.0).toStringAsFixed(1)}ms');
  engine.dispose();
}

LayaTypedQuestion _typed(final Map<String, dynamic> def) {
  final instructions = def['instructions'];
  final text = instructions is String ? instructions : renderLayaJson(instructions);
  switch (def['type'] as String) {
    case 'choice':
      return LayaTypedQuestion.choice(text, {
        for (final e in (def['criteria'] as Map).entries)
          '${e.key}': '${e.value ?? ''}',
      });
    case 'score':
      return LayaTypedQuestion.score(
        text,
        [for (final l in def['criteria'] as List) '$l'],
      );
    case 'noul':
      return LayaTypedQuestion.noul(text);
  }
  throw FormatException('unknown type ${def['type']}');
}
