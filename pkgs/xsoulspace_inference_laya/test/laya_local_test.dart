import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_laya/xsoulspace_inference_laya.dart';

void main() {
  group('LayaServeRuntime', () {
    test(
      'attach mode: healthy server flips readiness without spawning',
      () async {
        var spawns = 0;
        final runtime = LayaServeRuntime(
          httpClient: MockClient((_) async => http.Response('ok', 200)),
          processStarter: (_, _, _) async {
            spawns++;
            throw StateError('must not spawn in attach mode');
          },
        );

        expect(await runtime.ensureRunning(), isTrue);
        expect(runtime.isReady, isTrue);
        expect(runtime.status.$1, LayaRuntimeState.ready);
        expect(spawns, 0);
        await runtime.dispose();
      },
    );

    test('attach mode: health miss records unavailable, no process', () async {
      final runtime = LayaServeRuntime(
        httpClient: MockClient(
          (_) async => throw StateError('connection refused'),
        ),
      );

      expect(await runtime.ensureRunning(), isFalse);
      expect(runtime.status.$1, LayaRuntimeState.unavailable);
      expect(runtime.status.$2, contains('no laya-serve answering'));
      await runtime.dispose();
    });

    test('spawn mode: starts the process and waits for health', () async {
      var healthy = false;
      ManagedServeProcess? spawned;
      final runtime = LayaServeRuntime(
        spawnOnMiss: true,
        pollInterval: const Duration(milliseconds: 5),
        healthTimeout: const Duration(seconds: 2),
        httpClient: MockClient(
          (_) async =>
              healthy ? http.Response('ok', 200) : throw StateError('refused'),
        ),
        processStarter: (executable, arguments, environment) async {
          expect(executable, 'laya-serve');
          return spawned = _FakeProcess();
        },
      );

      final ensure = runtime.ensureRunning();
      // Flip health shortly after spawn so the poll loop observes both
      // sides deterministically.
      Future<void>.delayed(const Duration(milliseconds: 50), () {
        healthy = true;
      });
      unawaited(ensure);

      // Wait for readiness with a bounded loop.
      for (var i = 0; i < 200 && !runtime.isReady; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(runtime.isReady, isTrue);
      expect(spawned, isNotNull);
      await runtime.dispose();
    });

    test('spawn mode: early process exit fails fast', () async {
      final process = _FakeProcess()..exit();
      final runtime = LayaServeRuntime(
        spawnOnMiss: true,
        pollInterval: const Duration(milliseconds: 5),
        healthTimeout: const Duration(seconds: 5),
        httpClient: MockClient((_) async => throw StateError('refused')),
        processStarter: (_, _, _) async => process,
      );

      expect(await runtime.ensureRunning(), isFalse);
      expect(runtime.status.$1, LayaRuntimeState.unavailable);
      expect(runtime.status.$2, contains('exited before becoming healthy'));
      await runtime.dispose();
    });

    test('stop kills only the spawned process', () async {
      final process = _FakeProcess();
      var spawnedYet = false;
      final runtime = LayaServeRuntime(
        spawnOnMiss: true,
        pollInterval: const Duration(milliseconds: 5),
        healthTimeout: const Duration(seconds: 2),
        httpClient: MockClient(
          (_) async => spawnedYet
              ? http.Response('ok', 200)
              : throw StateError('refused'),
        ),
        processStarter: (_, _, _) async {
          spawnedYet = true;
          return process;
        },
      );

      expect(await runtime.ensureRunning(), isTrue);
      await runtime.stop();

      expect(process.killed, isTrue);
      expect(runtime.status.$1, LayaRuntimeState.stopped);
      await runtime.dispose();
    });
  });

  group('LayaLocalDecisionProvider', () {
    test('reports honest local capability facts and delegated readiness', () {
      final provider = _provider();

      expect(provider.id, 'laya_local');
      expect(
        provider.capabilities.executionLocation,
        DecisionExecutionLocation.local,
      );
      expect(
        provider.capabilities.networkRequirement,
        DecisionNetworkRequirement.none,
      );
      // Detached runtime => unavailable readiness, not a fake ready.
      expect(provider.readiness.isReady, isFalse);
      expect(provider.readiness.reasonCode, 'server_not_running');
    });

    test('decide before the runtime is ready is typed unavailable', () async {
      var requests = 0;
      final provider = _provider(
        httpClient: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );

      final outcome = await provider.decide(_request());

      expect(outcome, isA<DecisionUnavailable>());
      expect((outcome as DecisionUnavailable).failure.retryable, isTrue);
      expect(requests, 0);
    });

    test('ready runtime dispatches over the System One wire', () async {
      late http.Request captured;
      final runtime = LayaServeRuntime(
        httpClient: MockClient((_) async => http.Response('ok', 200)),
      );
      final provider = LayaLocalDecisionProvider(
        runtime: runtime,
        apiKey: 'k',
        httpClient: MockClient((final request) async {
          captured = request;
          return http.Response(jsonEncode(_successPayload()), 200);
        }),
      );
      await runtime.ensureRunning();

      final outcome = await provider.decide(_request());

      expect(outcome, isA<DecisionCompleted>());
      expect(captured.url.path, '/v1/systemone');
      expect(provider.readiness.isReady, isTrue);
      await runtime.dispose();
    });
  });
}

DecisionRequest _request() => DecisionRequest(
  correlation: DecisionCorrelation(
    requestId: const DecisionRequestId('req-a'),
    cutId: const DecisionCutId('cut-a'),
    stateRevision: const DecisionStateRevision('rev-a'),
    cancellationId: const DecisionCancellationId('cancel-a'),
  ),
  state: 'Verification failed after the semantic edit.',
  questions: <FiniteChoiceQuestion>[
    FiniteChoiceQuestion(
      id: const DecisionQuestionId('next_operation'),
      version: const DecisionQuestionVersion('v1'),
      candidateSetId: const DecisionCandidateSetId('candidates-a'),
      instructions: 'Which grounded semantic operation should be proposed?',
      options: const <DecisionOption>[
        DecisionOption(
          id: DecisionOptionId('apply_edit'),
          description: 'Apply the grounded semantic edit',
        ),
        DecisionOption(
          id: DecisionOptionId('insufficient_evidence'),
          description: 'Gather more evidence before proposing',
        ),
      ],
      abstainOptionId: const DecisionOptionId('insufficient_evidence'),
    ),
  ],
);

LayaLocalDecisionProvider _provider({final http.Client? httpClient}) =>
    LayaLocalDecisionProvider(
      runtime: LayaServeRuntime(
        httpClient:
            httpClient ?? MockClient((_) async => http.Response('ok', 200)),
      ),
      apiKey: 'k',
      httpClient: httpClient,
    );

Map<String, Object?> _successPayload() => <String, Object?>{
  'id': 'generation-1',
  'model': 'laya-20260918',
  'provider': 'laya-serve',
  'answers': <String, Object?>{
    'next_operation': <String, Object?>{
      'type': 'choice',
      'choice': 'apply_edit',
      'probabilities': <String, double>{
        'apply_edit': 0.8,
        'insufficient_evidence': 0.2,
      },
    },
  },
  'usage': <String, Object?>{'input_tokens': 275, 'output_tokens': 20},
};

final class _FakeProcess implements ManagedServeProcess {
  final Completer<void> _exit = Completer<void>();
  bool killed = false;

  void exit() {
    if (!_exit.isCompleted) _exit.complete();
  }

  @override
  int get pid => 424242;

  @override
  void kill() {
    killed = true;
    exit();
  }

  @override
  Future<void> get done => _exit.future;
}
