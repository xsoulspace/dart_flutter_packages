// Micro-benchmark for the pure-Dart laya decision path.
//
// Measures, in order:
//   1. engine  — ScriptedLayaDecisionEngine.answer (no I/O)
//   2. wire    — raw HTTP POST /v1/systemone round-trips (loopback)
//   3. provider— LayaServerDecisionProvider.decide (validation + parse)
//   4. handler — the canonical host decision handler loop (afm seam is
//      exercised by the harness integration test; this file keeps the
//      provider-level numbers reproducible inside the package)
//
// Run: dart run benchmark/laya_benchmark.dart [--seconds=N]
// Deterministic engine, loopback only; numbers are machine-relative (Apple
// Silicon, debug or AOT as run) — record the machine and mode with results.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart';
import 'package:xsoulspace_inference_openrouter/laya_server.dart';

Future<void> main(final List<String> args) async {
  final seconds = args
      .where((a) => a.startsWith('--seconds='))
      .map((a) => int.tryParse(a.split('=').last) ?? 3)
      .first;
  const questionsPerRequest = 16;

  _banner('laya decision path benchmark');
  _line('mode: ${Platform.executable} ${Platform.version.split(' ').first}');
  _line('per-run budget: ${seconds}s per scenario (min 200 ops)');

  // -- fixtures ---------------------------------------------------------------
  final engine = ScriptedLayaDecisionEngine(<LayaDecisionPin>[
    const LayaDecisionPin('q0', '"opt_0"'),
  ]);
  final server = LayaDecisionServer(engine: engine);
  await server.start();
  final systemOneUrl = server.url.replace(path: '/v1/systemone');
  final client = http.Client();
  final provider = LayaServerDecisionProvider(
    endpoint: systemOneUrl,
    timeout: const Duration(seconds: 10),
    httpClient: client,
  );

  // -- 1. engine only ----------------------------------------------------------
  final engineQuery = LayaDecisionQuery(
    model: 'laya',
    state: _state,
    questions: {
      for (var i = 0; i < questionsPerRequest; i++)
        'q$i': LayaDecisionQuestion(
          id: 'q$i',
          instructions: 'Pick the row label.',
          criteria: {for (var o = 0; o < 8; o++) 'opt_$o': '"opt_$o"'},
        ),
    },
  );
  final engineOps = _measure(
    seconds: seconds,
    op: () {
      engine.reset();
      engine.answer(engineQuery);
    },
  );
  _result(
    'engine.answer (16 questions x 8 options)',
    ops: engineOps.$1,
    seconds: engineOps.$2,
    latencies: engineOps.$3,
  );

  // -- 2. raw wire -------------------------------------------------------------
  final wireBody = jsonEncode(<String, Object?>{
    'model': 'laya',
    'state': _state,
    'questions': <String, Object?>{
      for (var i = 0; i < questionsPerRequest; i++)
        'q$i': <String, Object?>{
          'type': 'choice',
          'instructions': 'Pick the row label.',
          'criteria': {for (var o = 0; o < 8; o++) 'opt_$o': '"opt_$o"'},
        },
    },
  });
  // Warm the connection before measuring.
  await client.post(
    systemOneUrl,
    body: wireBody,
    headers: const {'content-type': 'application/json'},
  );
  final wireOps = await _measureAsync(
    seconds: seconds,
    op: () => client.post(
      systemOneUrl,
      body: wireBody,
      headers: const {'content-type': 'application/json'},
    ),
  );
  _result(
    'wire POST /v1/systemone (16q, keep-alive)',
    ops: wireOps.$1,
    seconds: wireOps.$2,
    latencies: wireOps.$3,
    unit: 'requests',
  );

  // -- 3. provider round-trip ---------------------------------------------------
  // The provider enforces single-use cancellation ids; allocate fresh
  // correlation per decide.
  final providerSingle = await _measureAsync(
    seconds: seconds,
    op: () => provider.decide(_request(questionCount: 1)),
  );
  _result(
    'provider.decide (1 question)',
    ops: providerSingle.$1,
    seconds: providerSingle.$2,
    latencies: providerSingle.$3,
    unit: 'decisions',
  );
  final providerWave = await _measureAsync(
    seconds: seconds,
    op: () => provider.decide(_request(questionCount: questionsPerRequest)),
  );
  _result(
    'provider.decide ($questionsPerRequest questions)',
    ops: providerWave.$1,
    seconds: providerWave.$2,
    latencies: providerWave.$3,
    unit: 'decisions',
  );

  // Throughput framing at the recorded numbers:
  _line('');
  _line(
    'questions/s (provider wave): '
    '${(providerWave.$1 * questionsPerRequest / providerWave.$2).toStringAsFixed(0)}',
  );
  _line(
    'engine-only ceiling: '
    '${(engineOps.$1 * questionsPerRequest / engineOps.$2).toStringAsFixed(0)} questions/s',
  );

  await provider.dispose();
  client.close();
  await server.stop();
}

const String _state =
    'Verification failed after the semantic edit. The opChain must be '
    're-derived from the grounded symbols before the next proposal.';

DecisionRequest _request({required final int questionCount}) => DecisionRequest(
  correlation: DecisionCorrelation(
    requestId: DecisionRequestId(
      'bench-${DateTime.now().microsecondsSinceEpoch}',
    ),
    cutId: const DecisionCutId('bench-cut'),
    stateRevision: const DecisionStateRevision('bench-rev'),
    cancellationId: DecisionCancellationId(
      'bench-cancel-${DateTime.now().microsecondsSinceEpoch}-${_uid++}',
    ),
  ),
  state: _state,
  questions: <FiniteChoiceQuestion>[
    for (var i = 0; i < questionCount; i++)
      FiniteChoiceQuestion(
        id: DecisionQuestionId('q$i'),
        version: const DecisionQuestionVersion('v1'),
        candidateSetId: const DecisionCandidateSetId('bench-candidates'),
        instructions: 'Pick the row label.',
        options: <DecisionOption>[
          for (var o = 0; o < 8; o++)
            DecisionOption(
              id: DecisionOptionId('opt_$o'),
              description: '"opt_$o"',
            ),
        ],
        abstainOptionId: const DecisionOptionId('opt_7'),
      ),
  ],
);

int _uid = 0;

typedef _Ops = (int, double, List<int>); // count, seconds, micros

_Ops _measure({required final int seconds, required final void Function() op}) {
  final micros = <int>[];
  final stopwatch = Stopwatch()..start();
  var ops = 0;
  while (stopwatch.elapsed < Duration(seconds: seconds) || ops < 200) {
    final t0 = stopwatch.elapsedMicroseconds;
    op();
    micros.add(stopwatch.elapsedMicroseconds - t0);
    ops++;
  }
  final elapsed = stopwatch.elapsedMicroseconds / 1e6;
  return (ops, elapsed, micros);
}

Future<_Ops> _measureAsync({
  required final int seconds,
  required final Future<Object?> Function() op,
}) async {
  final micros = <int>[];
  final stopwatch = Stopwatch()..start();
  var ops = 0;
  while (stopwatch.elapsed < Duration(seconds: seconds) || ops < 200) {
    final t0 = stopwatch.elapsedMicroseconds;
    await op();
    micros.add(stopwatch.elapsedMicroseconds - t0);
    ops++;
  }
  final elapsed = stopwatch.elapsedMicroseconds / 1e6;
  return (ops, elapsed, micros);
}

void _result(
  final String label, {
  required final int ops,
  required final double seconds,
  required final List<int> latencies,
  final String unit = 'ops',
}) {
  final sorted = List<int>.of(latencies)..sort();
  double pct(final double p) =>
      sorted[min(sorted.length - 1, (p * sorted.length).floor())] / 1000.0;
  _line(
    '$label: ${ops.toStringAsFixed(0)} $unit in ${seconds.toStringAsFixed(2)}s '
    '= ${(ops / seconds).toStringAsFixed(0)} $unit/s | '
    'p50 ${pct(0.50).toStringAsFixed(2)}ms '
    'p95 ${pct(0.95).toStringAsFixed(2)}ms '
    'p99 ${pct(0.99).toStringAsFixed(2)}ms '
    'max ${pct(1.0).toStringAsFixed(2)}ms',
  );
}

void _banner(final String text) => _line('== $text ==');

void _line(final String text) => stdout.writeln(text);
