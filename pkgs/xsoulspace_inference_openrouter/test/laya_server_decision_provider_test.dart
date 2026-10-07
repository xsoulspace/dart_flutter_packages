import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_openrouter/laya_server.dart';

void main() {
  group('LayaServerDecisionProvider', () {
    test('construction and local getters perform zero network requests', () {
      var requests = 0;
      final provider = _provider(
        MockClient((_) async {
          requests++;
          return _successResponse();
        }),
      );

      expect(provider.id, 'laya_server');
      expect(provider.readiness.isReady, isTrue);
      expect(
        provider.capabilities.executionLocation,
        DecisionExecutionLocation.local,
      );
      expect(
        provider.capabilities.networkRequirement,
        DecisionNetworkRequirement.none,
      );
      expect(requests, 0);
    });

    test(
      'keyless construction is ready: local servers usually run without auth',
      () {
        final provider = LayaServerDecisionProvider(
          httpClient: MockClient((_) async => _successResponse()),
        );
        expect(provider.readiness.isReady, isTrue);
      },
    );

    test(
      'defaults to the documented laya-serve endpoint and wire shape',
      () async {
        late http.Request captured;
        final provider = LayaServerDecisionProvider(
          httpClient: MockClient((final request) async {
            captured = request;
            return _successResponse(model: 'laya-en-20260918');
          }),
        );

        final outcome = await provider.decide(_request());

        expect(captured.url.scheme, 'http');
        expect(captured.url.host, '127.0.0.1');
        expect(captured.url.port, 8000);
        expect(captured.url.path, '/v1/systemone');
        expect(captured.headers.containsKey('authorization'), isFalse,
            reason: 'no credential configured, no header sent');
        final body = jsonDecode(captured.body) as Map<String, dynamic>;
        expect(body['model'], 'laya');
        expect(body['state'], _state);
        expect(body, isNot(contains('correlation')));
        final questions = body['questions'] as Map<String, dynamic>;
        expect(questions.keys, <String>['next_operation']);
        final question = questions['next_operation'] as Map<String, dynamic>;
        expect(question['type'], 'choice');
        expect(question['criteria'], <String, dynamic>{
          'apply_edit': 'Apply the grounded semantic edit',
          'insufficient_evidence': 'Gather more evidence before proposing',
        });
        expect(outcome, isA<DecisionCompleted>());
        final completed = outcome as DecisionCompleted;
        expect(completed.metadata.requestedModel, 'laya');
        expect(completed.metadata.resolvedModel, 'laya-en-20260918');
      },
    );

    test('supplied credentials are sent as a Bearer header', () async {
      late http.Request captured;
      final provider = LayaServerDecisionProvider(
        apiKey: 'laya-key',
        httpClient: MockClient((final request) async {
          captured = request;
          return _successResponse();
        }),
      );

      await provider.decide(_request());

      expect(captured.headers['authorization'], 'Bearer laya-key');
    });

    test(
      'diagnostic captures exact POST; observer exceptions cannot break calls',
      () async {
        late http.Request captured;
        final events = <Map<String, Object?>>[];
        final provider = LayaServerDecisionProvider(
          httpClient: MockClient((final request) async {
            captured = request;
            return _successResponse();
          }),
          onDiagnosticEvent: (final event) {
            events.add(event);
            throw StateError('diagnostic sink unavailable');
          },
        );
        final request = _request();

        final outcome = await provider.decide(request);

        expect(outcome, isA<DecisionCompleted>());
        expect(events.single['type'], 'laya.server.post');
        expect(events.single['uri'], captured.url.toString());
        expect(events.single['correlation'], request.correlation.toJson());
        expect(events.single.toString(), isNot(contains('laya-key')));
      },
    );

    test('confidence is optional on this wire and preserved when present',
        () async {
      final withoutConfidence = LayaServerDecisionProvider(
        httpClient: MockClient(
          (_) async => _successResponse(
            answerOverrides: <String, Object?>{'confidence': null},
          ),
        ),
      );
      final withConfidence = LayaServerDecisionProvider(
        httpClient: MockClient((_) async => _successResponse()),
      );

      final absent = await withoutConfidence.decide(_request());
      final present = await withConfidence.decide(_request());

      expect(absent, isA<DecisionCompleted>());
      expect((absent as DecisionCompleted).answers.single.confidence, isNull);
      expect(present, isA<DecisionCompleted>());
      expect((present as DecisionCompleted).answers.single.confidence, 0.6);
    });

    test('hundredth-rounded wire probabilities normalize with raw audit',
        () async {
      final provider = _provider(
        MockClient(
          (_) async => _successResponse(
            answerOverrides: <String, Object?>{
              'probabilities': <String, double>{
                'apply_edit': 0.99,
                'insufficient_evidence': 0.0,
              },
            },
          ),
        ),
      );

      final outcome = await provider.decide(_request());

      expect(outcome, isA<DecisionCompleted>());
      final metadata = (outcome as DecisionCompleted).metadata;
      expect(
        metadata.additional['probability_normalization'],
        isA<Map<String, Object?>>(),
      );
      final probabilities =
          (outcome.answers.single.probabilities)!;
      expect(probabilities.values.fold<double>(0, (a, b) => a + b), closeTo(1, 1e-9));
    });

    test('rejects oversized state before serialization or dispatch', () async {
      var requests = 0;
      final provider = LayaServerDecisionProvider(
        maxStateUtf8Bytes: 16,
        httpClient: MockClient((_) async {
          requests++;
          return _successResponse();
        }),
      );

      final outcome = await provider.decide(_request());

      expect(outcome, isA<DecisionUnsupported>());
      expect((outcome as DecisionUnsupported).failure.code,
          DecisionFailureCode.unsupported);
      expect(requests, 0);
    });

    test('operator-configured auth failures surface as typed unavailable',
        () async {
      final provider = LayaServerDecisionProvider(
        apiKey: 'wrong-key',
        httpClient: MockClient((_) async => http.Response('denied', 401)),
      );

      final outcome = await provider.decide(_request());

      expect(outcome, isA<DecisionUnavailable>());
      expect((outcome as DecisionUnavailable).failure.code,
          DecisionFailureCode.authentication);
    });

    test('maps 503 busy to retryable unavailable and bounds retries',
        () async {
      var requests = 0;
      final provider = LayaServerDecisionProvider(
        maxTransientRetries: 1,
        httpClient: MockClient((_) async {
          requests++;
          return http.Response('busy', 503);
        }),
      );

      final outcome = await provider.decide(_request());

      expect(requests, 2);
      expect(outcome, isA<DecisionUnavailable>());
      expect((outcome as DecisionUnavailable).failure.retryable, isTrue);
    });

    test('malformed JSON maps to typed malformed response', () async {
      final provider = _provider(
        MockClient((_) async => http.Response('not-json{', 200)),
      );

      final outcome = await provider.decide(_request());

      expect(outcome, isA<DecisionFailed>());
      expect((outcome as DecisionFailed).failure.code,
          DecisionFailureCode.malformedResponse);
    });

    test('never accepts an answer for an unknown or response-created option',
        () async {
      final unknownQuestion = _provider(
        MockClient(
          (_) async => _successResponse(
            extra: <String, Object?>{
              'answers': <String, Object?>{
                'next_operation': _answer(),
                'surprise_question': _answer(),
              },
            },
          ),
        ),
      );
      final inventedOption = _provider(
        MockClient(
          (_) async => _successResponse(
            answerOverrides: <String, Object?>{'choice': 'hallucinated'},
          ),
        ),
      );

      expect(await unknownQuestion.decide(_request()), isA<DecisionFailed>());
      expect(await inventedOption.decide(_request()), isA<DecisionFailed>());
    });

    test('constructs host correlation locally instead of response echoes',
        () async {
      final response = _successPayload()
        ..['request_id'] = 'untrusted-provider-request'
        ..['cut_id'] = 'untrusted-cut';
      final provider = _provider(
        MockClient((_) async => http.Response(jsonEncode(response), 200)),
      );

      final outcome = await provider.decide(_request());

      expect(outcome.correlation.requestId, const DecisionRequestId('req-a'));
      expect(outcome.correlation.cutId, const DecisionCutId('cut-a'));
    });

    test('cancel before dispatch blocks the request without a network call',
        () async {
      var requests = 0;
      final provider = _provider(
        MockClient((_) async {
          requests++;
          return _successResponse();
        }),
      );
      await provider.cancel(const DecisionCancellationId('cancel-a'));

      final outcome = await provider.decide(_request());

      expect(outcome, isA<DecisionCancelled>());
      expect(requests, 0);
    });

    test('cancel during dispatch discards the late response', () async {
      final response = Completer<http.Response>();
      final started = Completer<void>();
      final provider = _provider(
        MockClient((_) {
          started.complete();
          return response.future;
        }),
      );
      final pending = provider.decide(_request());
      await started.future;
      await provider.cancel(const DecisionCancellationId('cancel-a'));
      expect(await pending, isA<DecisionCancelled>());
      response.complete(_successResponse());
    });

    test('dispose blocks later dispatch and discards an in-flight response',
        () async {
      final started = Completer<void>();
      final response = Completer<http.Response>();
      var requests = 0;
      final provider = _provider(
        MockClient((_) {
          requests++;
          started.complete();
          return response.future;
        }),
      );
      final pending = provider.decide(_request());
      await started.future;
      await provider.dispose();
      expect(
        await pending.timeout(const Duration(milliseconds: 100)),
        isA<DecisionCancelled>(),
      );
      response.complete(_successResponse());
      final afterDispose = await provider.decide(_request(suffix: 'after'));
      expect(afterDispose, isA<DecisionFailed>());
      expect(
        (afterDispose as DecisionFailed).failure.code,
        DecisionFailureCode.disposed,
      );
      expect(requests, 1);
    });

    test('cancellation IDs are single-use within a provider instance',
        () async {
      final provider = _provider(MockClient((_) async => _successResponse()));
      await provider.cancel(const DecisionCancellationId('cancel-a'));
      final blocked = await provider.decide(_request());
      expect(blocked, isA<DecisionCancelled>());

      final reused = await provider.decide(_request());
      expect(reused, isA<DecisionFailed>());
      expect(
        (reused as DecisionFailed).failure.code,
        DecisionFailureCode.invalidRequest,
      );
    });
  });

  group('LayaServerReadinessProbe', () {
    test('answers true on a healthy local server', () async {
      final probe = LayaServerReadinessProbe(
        httpClient: MockClient((_) async => http.Response('{"status":"ok"}', 200)),
      );

      expect(await probe.ping(), isTrue);
      await probe.dispose();
    });

    test('answers false when nothing listens', () async {
      final probe = LayaServerReadinessProbe(
        httpClient: MockClient((_) async => throw StateError('refused')),
      );

      expect(await probe.ping(), isFalse);
      await probe.dispose();
    });
  });
}

const String _state = 'Verification failed after the semantic edit.';

LayaServerDecisionProvider _provider(
  final http.Client client, {
  final int maxTransientRetries = 0,
  final Duration timeout = const Duration(seconds: 1),
}) => LayaServerDecisionProvider(
  apiKey: 'laya-key',
  httpClient: client,
  timeout: timeout,
  maxTransientRetries: maxTransientRetries,
  retryDelay: Duration.zero,
);

DecisionRequest _request({
  final String suffix = 'a',
  final String state = _state,
  final DecisionCancellationId cancellationId = const DecisionCancellationId(
    'cancel-a',
  ),
  final List<FiniteChoiceQuestion>? questions,
}) => DecisionRequest(
  correlation: DecisionCorrelation(
    requestId: DecisionRequestId('req-$suffix'),
    cutId: DecisionCutId('cut-$suffix'),
    stateRevision: DecisionStateRevision('revision-$suffix'),
    cancellationId: cancellationId,
  ),
  state: state,
  questions: questions ?? <FiniteChoiceQuestion>[_question()],
);

FiniteChoiceQuestion _question() => FiniteChoiceQuestion(
  id: const DecisionQuestionId('next_operation'),
  version: const DecisionQuestionVersion('v1'),
  candidateSetId: const DecisionCandidateSetId('candidates-a'),
  instructions: 'Which grounded semantic operation should be proposed next?',
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
);

Map<String, Object?> _answer() => <String, Object?>{
  'type': 'choice',
  'choice': 'apply_edit',
  'confidence': 0.6,
  'probabilities': <String, double>{
    'apply_edit': 0.8,
    'insufficient_evidence': 0.2,
  },
};

http.Response _successResponse({
  final String? model,
  final Map<String, Object?> answerOverrides = const <String, Object?>{},
  final Map<String, Object?> extra = const <String, Object?>{},
}) => http.Response(
  jsonEncode(_successPayload(model: model, answerOverrides: answerOverrides)
    ..addAll(extra)),
  200,
);

Map<String, Object?> _successPayload({
  final String? model,
  final Map<String, Object?> answerOverrides = const <String, Object?>{},
}) => <String, Object?>{
  'id': 'generation-1',
  'model': model ?? 'laya-20260918',
  'provider': 'laya-serve',
  'answers': <String, Object?>{
    'next_operation': <String, Object?>{..._answer(), ...answerOverrides},
  },
  'usage': <String, Object?>{'input_tokens': 275, 'output_tokens': 20},
};
