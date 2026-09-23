import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_openrouter/openrouter_system_one.dart';

void main() {
  group('OpenRouterSystemOneDecisionProvider', () {
    test('construction and local getters perform zero network requests', () {
      var requests = 0;
      final provider = _provider(
        MockClient((_) async {
          requests++;
          return _successResponse();
        }),
      );

      expect(provider.id, 'openrouter_system_one');
      expect(provider.readiness.isReady, isTrue);
      expect(
        provider.capabilities.executionLocation,
        DecisionExecutionLocation.hosted,
      );
      expect(
        provider.capabilities.networkRequirement,
        DecisionNetworkRequirement.required,
      );
      expect(requests, 0);
    });

    test(
      'uses the System One endpoint and documented choice wire shape',
      () async {
        late http.Request captured;
        final provider = _provider(
          MockClient((final request) async {
            captured = request;
            return _successResponse(
              extra: const <String, Object?>{'trace': 'ok'},
            );
          }),
        );

        final outcome = await provider.decide(_request());

        expect(captured.url.path, '/api/v1/systemone');
        expect(captured.headers['authorization'], 'Bearer test-key');
        final body = jsonDecode(captured.body) as Map<String, dynamic>;
        expect(body['model'], 'jev-1.13');
        expect(body['state'], 'Verification failed after the semantic edit.');
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
        expect(
          completed.correlation.requestId,
          const DecisionRequestId('req-a'),
        );
        expect(
          completed.answers.single.questionId,
          const DecisionQuestionId('next_operation'),
        );
        expect(
          completed.answers.single.selectedOptionId,
          const DecisionOptionId('apply_edit'),
        );
        expect(completed.answers.single.confidence, 0.6);
        expect(completed.metadata.requestedModel, 'jev-1.13');
        expect(completed.metadata.resolvedModel, 'typesafe/jev-1.13-20260917');
        expect(completed.metadata.providerRequestId, 'generation-1');
        expect(completed.metadata.usage?.cost, 0.00003);
        expect(completed.metadata.usage?.currency, 'USD');
        expect(completed.metadata.additional['trace'], 'ok');
      },
    );

    test(
      'constructs host correlation locally instead of response echoes',
      () async {
        final response = _successPayload()
          ..['request_id'] = 'untrusted-provider-request'
          ..['cut_id'] = 'untrusted-cut'
          ..['state_revision'] = 'untrusted-revision';
        final provider = _provider(
          MockClient((_) async => http.Response(jsonEncode(response), 200)),
        );

        final outcome = await provider.decide(_request());

        expect(outcome, isA<DecisionCompleted>());
        expect(outcome.correlation.requestId, const DecisionRequestId('req-a'));
        expect(outcome.correlation.cutId, const DecisionCutId('cut-a'));
        expect(
          outcome.correlation.stateRevision,
          const DecisionStateRevision('revision-a'),
        );
      },
    );

    test(
      'missing key is unavailable and causes zero network requests',
      () async {
        var requests = 0;
        final provider = _provider(
          MockClient((_) async {
            requests++;
            return _successResponse();
          }),
          apiKey: '',
        );

        final outcome = await provider.decide(_request());

        expect(provider.readiness.isReady, isFalse);
        expect(outcome, isA<DecisionUnavailable>());
        expect(requests, 0);
      },
    );

    test('rejects invalid requests before serialization or dispatch', () async {
      var requests = 0;
      final provider = _provider(
        MockClient((_) async {
          requests++;
          return _successResponse();
        }),
      );
      final request = _request(
        questions: <FiniteChoiceQuestion>[_question(), _question()],
      );

      final outcome = await provider.decide(request);

      expect(outcome, isA<DecisionFailed>());
      expect(
        (outcome as DecisionFailed).failure.code,
        DecisionFailureCode.invalidRequest,
      );
      expect(requests, 0);
    });

    test(
      'rejects out-of-bounds requests as unsupported before any network call',
      () async {
        var requests = 0;
        final provider = _provider(
          MockClient((_) async {
            requests++;
            return _successResponse();
          }),
        );
        final tooManyQuestions = _request(
          questions: List<FiniteChoiceQuestion>.generate(
            65,
            (final index) => FiniteChoiceQuestion(
              id: DecisionQuestionId('q$index'),
              version: const DecisionQuestionVersion('v1'),
              candidateSetId: const DecisionCandidateSetId('candidates-a'),
              instructions: 'Choose the next grounded operation.',
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
          ),
        );
        final oversizedState = _request(
          state: 'x' * ((1 << 20) + 1),
          cancellationId: const DecisionCancellationId('cancel-c'),
        );

        final tooMany = await provider.decide(tooManyQuestions);
        final oversized = await provider.decide(oversizedState);

        expect(tooMany, isA<DecisionUnsupported>());
        expect(oversized, isA<DecisionUnsupported>());
        expect(requests, 0);
      },
    );

    for (final malformedCase in <String, String>{
      'non-JSON response': 'not json',
      'non-object response': '[]',
      'missing answers': '{"model":"typesafe/jev-1.13-snapshot"}',
      'wrong answer type': jsonEncode(
        _successPayload(
          answerOverrides: const <String, Object?>{'type': 'score'},
        ),
      ),
      'unknown choice': jsonEncode(
        _successPayload(
          answerOverrides: const <String, Object?>{'choice': 'invented'},
        ),
      ),
      'incomplete probabilities': jsonEncode(
        _successPayload(
          answerOverrides: const <String, Object?>{
            'probabilities': <String, double>{'apply_edit': 1},
          },
        ),
      ),
      'out-of-range probability': jsonEncode(
        _successPayload(
          answerOverrides: const <String, Object?>{
            'probabilities': <String, double>{
              'apply_edit': 1.1,
              'insufficient_evidence': -0.1,
            },
          },
        ),
      ),
      'invalid distribution sum': jsonEncode(
        _successPayload(
          answerOverrides: const <String, Object?>{
            'probabilities': <String, double>{
              'apply_edit': 0.4,
              'insufficient_evidence': 0.4,
            },
          },
        ),
      ),
      'unknown probability option': jsonEncode(
        _successPayload(
          answerOverrides: const <String, Object?>{
            'probabilities': <String, double>{
              'apply_edit': 0.8,
              'insufficient_evidence': 0.1,
              'invented': 0.1,
            },
          },
        ),
      ),
      'negative usage': jsonEncode(
        _successPayload()..['usage'] = <String, Object?>{'input_tokens': -1},
      ),
      'fractional token usage': jsonEncode(
        _successPayload()..['usage'] = <String, Object?>{'input_tokens': 1.5},
      ),
    }.entries) {
      test('maps ${malformedCase.key} to malformed response', () async {
        final provider = _provider(
          MockClient((_) async => http.Response(malformedCase.value, 200)),
        );

        final outcome = await provider.decide(_request());

        expect(outcome, isA<DecisionFailed>());
        expect(
          (outcome as DecisionFailed).failure.code,
          DecisionFailureCode.malformedResponse,
        );
      });
    }

    test('rejects extra and missing answer IDs', () async {
      final payload = _successPayload();
      final answers = payload['answers'] as Map<String, Object?>;
      answers['unexpected'] = Map<String, Object?>.from(
        answers['next_operation']! as Map<String, Object?>,
      );
      final provider = _provider(
        MockClient((_) async => http.Response(jsonEncode(payload), 200)),
      );

      final outcome = await provider.decide(_request());

      expect(outcome, isA<DecisionFailed>());
      expect(
        (outcome as DecisionFailed).failure.code,
        DecisionFailureCode.malformedResponse,
      );
    });

    test(
      'maps auth, quota, and rate limits to typed unavailable failures',
      () async {
        for (final entry in <int, DecisionFailureCode>{
          401: DecisionFailureCode.authentication,
          402: DecisionFailureCode.quotaExceeded,
          429: DecisionFailureCode.rateLimited,
        }.entries) {
          final provider = _provider(
            MockClient(
              (_) async => http.Response(
                '{"error":{"message":"provider error"}}',
                entry.key,
              ),
            ),
          );

          final outcome = await provider.decide(_request());

          expect(outcome, isA<DecisionUnavailable>());
          expect((outcome as DecisionUnavailable).failure.code, entry.value);
        }
      },
    );

    test('does not echo provider error bodies into failures', () async {
      const privateText = 'private-state-and-key';
      final provider = _provider(
        MockClient(
          (_) async =>
              http.Response('{"error":{"message":"$privateText"}}', 401),
        ),
      );

      final outcome = await provider.decide(_request());

      final failure = (outcome as DecisionUnavailable).failure;
      expect(failure.message, isNot(contains(privateText)));
      expect(failure.details, isNull);
    });

    test('bounds transient retries and reports exhaustion', () async {
      var requests = 0;
      final provider = _provider(
        MockClient((_) async {
          requests++;
          return http.Response('temporarily unavailable', 503);
        }),
        maxTransientRetries: 1,
      );

      final outcome = await provider.decide(_request());

      expect(requests, 2);
      expect(outcome, isA<DecisionUnavailable>());
      expect((outcome as DecisionUnavailable).failure.retryable, isTrue);
    });

    test('maps request timeout to typed failure', () async {
      final response = Completer<http.Response>();
      final provider = _provider(
        MockClient((_) => response.future),
        timeout: const Duration(milliseconds: 10),
      );

      final outcome = await provider.decide(_request());

      expect(outcome, isA<DecisionFailed>());
      expect(
        (outcome as DecisionFailed).failure.code,
        DecisionFailureCode.timeout,
      );
    });

    test('cancellation before dispatch causes zero requests', () async {
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

    test('late response after scoped cancellation is discarded', () async {
      final started = Completer<void>();
      final response = Completer<http.Response>();
      final provider = _provider(
        MockClient((_) {
          started.complete();
          return response.future;
        }),
      );
      final pending = provider.decide(_request());
      await started.future;
      await provider.cancel(const DecisionCancellationId('cancel-a'));
      final outcome = await pending.timeout(const Duration(milliseconds: 100));
      response.complete(_successResponse());

      expect(outcome, isA<DecisionCancelled>());
    });

    test(
      'duplicate cancellation IDs are rejected without affecting the first',
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
        final first = provider.decide(_request());
        await started.future;

        final duplicate = await provider.decide(_request(suffix: 'duplicate'));

        expect(duplicate, isA<DecisionFailed>());
        expect(
          (duplicate as DecisionFailed).failure.code,
          DecisionFailureCode.invalidRequest,
        );
        expect(requests, 1);
        await provider.cancel(const DecisionCancellationId('cancel-a'));
        expect(await first, isA<DecisionCancelled>());
        response.complete(_successResponse());
      },
    );

    test(
      'cancelling one request does not cancel a shared provider peer',
      () async {
        final responses = <String, Completer<http.Response>>{
          'first': Completer<http.Response>(),
          'second': Completer<http.Response>(),
        };
        final started = Completer<void>();
        var requestCount = 0;
        final provider = _provider(
          MockClient((final request) {
            requestCount++;
            if (requestCount == 2 && !started.isCompleted) started.complete();
            final state =
                (jsonDecode(request.body) as Map<String, dynamic>)['state']
                    as String;
            return responses[state]!.future;
          }),
        );
        final first = provider.decide(_request(state: 'first'));
        final second = provider.decide(
          _request(
            suffix: 'b',
            state: 'second',
            cancellationId: const DecisionCancellationId('cancel-b'),
          ),
        );
        await started.future;
        await provider.cancel(const DecisionCancellationId('cancel-a'));
        responses['first']!.complete(_successResponse());
        responses['second']!.complete(_successResponse());

        expect(await first, isA<DecisionCancelled>());
        expect(await second, isA<DecisionCompleted>());
      },
    );

    test(
      'dispose blocks later dispatch and discards an in-flight response',
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
      },
    );
  });
}

OpenRouterSystemOneDecisionProvider _provider(
  final http.Client client, {
  final String apiKey = 'test-key',
  final int maxTransientRetries = 0,
  final Duration timeout = const Duration(seconds: 1),
}) => OpenRouterSystemOneDecisionProvider(
  apiKey: apiKey,
  model: 'jev-1.13',
  httpClient: client,
  timeout: timeout,
  maxTransientRetries: maxTransientRetries,
  retryDelay: Duration.zero,
);

DecisionRequest _request({
  final String suffix = 'a',
  final String state = 'Verification failed after the semantic edit.',
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

http.Response _successResponse({final Map<String, Object?> extra = const {}}) =>
    http.Response(jsonEncode(_successPayload()..addAll(extra)), 200);

Map<String, Object?> _successPayload({
  final Map<String, Object?> answerOverrides = const <String, Object?>{},
}) => <String, Object?>{
  'id': 'generation-1',
  'model': 'typesafe/jev-1.13-20260917',
  'provider': 'TypeSafe',
  'answers': <String, Object?>{
    'next_operation': <String, Object?>{
      'type': 'choice',
      'choice': 'apply_edit',
      'confidence': 0.6,
      'probabilities': <String, double>{
        'apply_edit': 0.8,
        'insufficient_evidence': 0.2,
      },
      ...answerOverrides,
    },
  },
  'usage': <String, Object?>{
    'input_tokens': 275,
    'output_tokens': 20,
    'cost': 0.00003,
  },
};
