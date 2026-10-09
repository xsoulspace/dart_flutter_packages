import 'dart:async';
import 'dart:io';

import 'package:async_parallel/async_parallel.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_openrouter/laya_server.dart';
import 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart';

void main() {
  test(
    'FIFO admission stays occupied until physical work settles; drain owns unload',
    () async {
      final executor = _ControlledExecutor();
      var disposed = 0;
      final engine = AsyncLayaDecisionEngine(
        engine: const _Engine(),
        executor: executor,
        maxPending: 2,
        disposeEngine: () => disposed++,
      );
      final a = engine.answerDecisions(_query('actor-a private evidence'));
      final b = engine.answerDecisions(_query('actor-b private evidence'));
      expect(engine.pending, 2);
      await expectLater(
        engine.answerDecisions(_query('overflow')),
        throwsA(isA<LayaServingException>()),
      );
      expect(executor.states, ['actor-a private evidence']);
      var closed = false;
      final close = engine.dispose().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, false);
      expect(disposed, 0);
      await expectLater(
        engine.answerDecisions(_query('after-close')),
        throwsA(isA<LayaServingException>()),
      );
      executor.release();
      expect((await a)['q']!.probabilities, {'a': .7, 'b': .3});
      await Future<void>.delayed(Duration.zero);
      expect(executor.states, [
        'actor-a private evidence',
        'actor-b private evidence',
      ]);
      expect(engine.pending, 1);
      expect(disposed, 0);
      executor.release();
      await b;
      await close;
      await engine.dispose();
      expect(engine.pending, 0);
      expect(disposed, 1);
    },
  );

  test(
    'caller cancellation preserves correlation and shared physical capacity',
    () async {
      final executor = _ControlledExecutor();
      final engine = AsyncLayaDecisionEngine(
        engine: const _Engine(),
        executor: executor,
      );
      final server = LayaDecisionServer(engine: engine);
      await server.start();
      final provider = LayaServerDecisionProvider(
        endpoint: server.url.replace(path: '/v1/systemone'),
        maxTransientRetries: 0,
      );
      final first = provider.decide(_request('a'));
      while (executor.states.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await provider.cancel(const DecisionCancellationId('cancel-a'));
      final cancelled = await first;
      expect(cancelled, isA<DecisionCancelled>());
      expect(cancelled.correlation.requestId, const DecisionRequestId('req-a'));
      expect(engine.pending, 1);
      final second = provider.decide(_request('b'));
      while (engine.pending != 2) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(executor.states, ['a']);
      executor.release();
      while (executor.states.length != 2) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(executor.states, ['a', 'b']);
      executor.release();
      final completed = await second;
      expect(completed, isA<DecisionCompleted>());
      expect(completed.correlation.requestId, const DecisionRequestId('req-b'));
      await provider.dispose();
      await server.stop();
      await engine.dispose();
    },
  );

  test(
    'physical error releases slot and next private request still succeeds',
    () async {
      final executor = _ControlledExecutor();
      final engine = AsyncLayaDecisionEngine(
        engine: const _Engine(),
        executor: executor,
      );
      final failed = engine.answerDecisions(_query('a'));
      final checked = expectLater(failed, throwsA(isA<StateError>()));
      final next = engine.answerDecisions(_query('b'));
      executor.fail();
      await checked;
      await Future<void>.delayed(Duration.zero);
      executor.release();
      expect((await next)['q']!.optionId, 'a');
      await engine.dispose();
    },
  );

  test(
    'existing isolate executor keeps owner timers responsive during blocking inference',
    () async {
      final engine = AsyncLayaDecisionEngine(engine: const _BlockingEngine());
      var ticks = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 5),
        (_) => ticks++,
      );
      try {
        await engine.answerDecisions(_query('only this job'));
        expect(ticks, greaterThan(3));
      } finally {
        timer.cancel();
        await engine.dispose();
      }
    },
  );

  test('native async serving runs actual shared model with owner progress', () async {
    if (Platform.environment['LAYA_ASYNC_NATIVE_PROBE'] != '1') {
      return markTestSkipped(
        'opt in with LAYA_ASYNC_NATIVE_PROBE=1; no model quality claim from fixtures',
      );
    }
    var ticks = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 10),
      (_) => ticks++,
    );
    final engine = await AsyncLayaDecisionEngine.loadNative();
    try {
      final before = ticks;
      final results = await Future.wait([
        engine.answerDecisions(
          _query('The user asked actor A to gather evidence before editing.'),
        ),
        engine.answerDecisions(
          _query(
            'Actor B already verified its own evidence and proposes a change.',
          ),
        ),
      ]);
      expect(ticks, greaterThan(before));
      for (final result in results) {
        final answer = result['q']!;
        expect(
          answer.probabilities.values.reduce((a, b) => a + b),
          closeTo(1, 1e-6),
        );
        expect(answer.confidence.isFinite, true);
        expect(
          answer.answerConfidence,
          answer.probabilities.values.reduce((a, b) => a > b ? a : b),
        );
      }
      // Real local wire cancellation abandons only actor A's outcome; actor B
      // still gets its own correlated calibrated result from the shared model.
      final server = LayaDecisionServer(engine: engine);
      final seen = Completer<void>();
      server.onRequest = (_) {
        if (!seen.isCompleted) seen.complete();
      };
      await server.start();
      final provider = LayaServerDecisionProvider(
        endpoint: server.url.replace(path: '/v1/systemone'),
        maxTransientRetries: 0,
        timeout: const Duration(seconds: 30),
      );
      try {
        final first = provider.decide(_request('native-a'));
        await seen.future;
        await provider.cancel(const DecisionCancellationId('cancel-native-a'));
        expect(await first, isA<DecisionCancelled>());
        expect(engine.pending, 1);
        final second = await provider.decide(_request('native-b'));
        expect(second, isA<DecisionCompleted>());
        expect(
          second.correlation.requestId,
          const DecisionRequestId('req-native-b'),
        );
      } finally {
        await provider.dispose();
        await server.stop();
      }
      // Public diagnostics only; no request state or actor evidence is logged.
      // ignore: avoid_print
      print(
        'native async shared model: requests=${results.length} ownerTicks=${ticks - before} calibrated=${results.map((r) => r['q']!.probabilities).toList()}',
      );
    } finally {
      timer.cancel();
      await engine.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

LayaDecisionQuery _query(String state) => LayaDecisionQuery(
  model: 'laya',
  state: state,
  questions: {
    'q': const LayaDecisionQuestion(
      id: 'q',
      instructions: 'What should this actor do?',
      criteria: {
        'a': 'Gather evidence before editing',
        'b': 'Propose the verified change',
      },
    ),
  },
);

final class _Engine implements CalibratedLayaDecisionEngine {
  const _Engine();
  @override
  Map<String, String> answer(LayaDecisionQuery query) => {'q': 'a'};
  @override
  Map<String, LayaDecisionResult> answerDecisions(LayaDecisionQuery query) => {
    'q': const LayaDecisionResult(
      optionId: 'a',
      probabilities: {'a': .7, 'b': .3},
      confidence: .2,
      answerConfidence: .7,
      actProbability: .4,
    ),
  };
}

final class _BlockingEngine implements CalibratedLayaDecisionEngine {
  const _BlockingEngine();
  @override
  Map<String, String> answer(LayaDecisionQuery query) => {'q': 'a'};
  @override
  Map<String, LayaDecisionResult> answerDecisions(LayaDecisionQuery query) {
    final watch = Stopwatch()..start();
    while (watch.elapsedMilliseconds < 100) {}
    return const _Engine().answerDecisions(query);
  }
}

final class _ControlledExecutor extends IsolateExecutor {
  final states = <String>[];
  final gates = <Completer<void>>[];
  int released = 0;
  @override
  Future<R> compute<Q, R>(FutureOr<R> Function(Q) function, Q message) async {
    // Deliberately in-process executor verifies admission/lifecycle independently
    // of the separate real-isolate responsiveness test.
    final input =
        message
            as ({CalibratedLayaDecisionEngine engine, LayaDecisionQuery query});
    states.add(input.query.state);
    final gate = Completer<void>();
    gates.add(gate);
    await gate.future;
    return await function(message);
  }

  void release() => gates[released++].complete();
  void fail() =>
      gates[released++].completeError(StateError('physical failure'));
}

DecisionRequest _request(String actor) => DecisionRequest(
  correlation: DecisionCorrelation(
    requestId: DecisionRequestId('req-$actor'),
    cutId: DecisionCutId('cut-$actor'),
    stateRevision: DecisionStateRevision('rev-$actor'),
    cancellationId: DecisionCancellationId('cancel-$actor'),
  ),
  state: actor,
  questions: [
    FiniteChoiceQuestion(
      id: const DecisionQuestionId('q'),
      version: const DecisionQuestionVersion('v1'),
      candidateSetId: DecisionCandidateSetId('options-$actor'),
      instructions: 'What should this actor do?',
      abstainOptionId: const DecisionOptionId('a'),
      options: const [
        DecisionOption(
          id: DecisionOptionId('a'),
          description: 'Gather evidence',
        ),
        DecisionOption(
          id: DecisionOptionId('b'),
          description: 'Propose change',
        ),
      ],
    ),
  ],
);
