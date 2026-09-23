import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

void main() {
  group('decision contract', () {
    test('request round-trips opaque correlation and finite choices', () {
      final request = _request();
      final roundTrip = DecisionRequest.fromJson(request.toJson());

      expect(roundTrip.correlation.requestId, request.correlation.requestId);
      expect(roundTrip.correlation.cutId, request.correlation.cutId);
      expect(
        roundTrip.correlation.stateRevision,
        request.correlation.stateRevision,
      );
      expect(roundTrip.questions.single.id, request.questions.single.id);
      expect(
        roundTrip.questions.single.candidateSetId,
        request.questions.single.candidateSetId,
      );
      expect(
        roundTrip.questions.single.abstainOptionId,
        const DecisionOptionId('insufficient_evidence'),
      );
      expect(validateDecisionRequest(roundTrip).success, isTrue);
    });

    test('request and answer collections are defensive immutable copies', () {
      final options = <DecisionOption>[
        const DecisionOption(
          id: DecisionOptionId('apply_edit'),
          description: 'Apply the typed semantic edit',
        ),
        const DecisionOption(
          id: DecisionOptionId('insufficient_evidence'),
          description: 'More evidence is needed',
        ),
      ];
      final question = _question(options: options);
      final questions = <FiniteChoiceQuestion>[question];
      final request = _request(questions: questions);
      final probabilities = <DecisionOptionId, double>{
        const DecisionOptionId('apply_edit'): 0.8,
        const DecisionOptionId('insufficient_evidence'): 0.2,
      };
      final answer = _answer(probabilities: probabilities);

      options.clear();
      questions.clear();
      probabilities.clear();

      expect(question.options, hasLength(2));
      expect(request.questions, hasLength(1));
      expect(answer.probabilities, hasLength(2));
      expect(request.questions.clear, throwsUnsupportedError);
      expect(() => answer.probabilities!.clear(), throwsUnsupportedError);
    });

    test('explicit abstention is validated per answer', () {
      final request = _request();
      final completion = DecisionCompleted(
        correlation: request.correlation,
        answers: <DecisionAnswer>[
          _answer(
            selectedOptionId: const DecisionOptionId('insufficient_evidence'),
            disposition: DecisionAnswerDisposition.abstained,
          ),
        ],
      );

      expect(
        validateDecisionCompletion(
          request: request,
          completion: completion,
        ).success,
        isTrue,
      );
    });

    test('rejects a choice invented outside the original candidate set', () {
      final request = _request();
      final completion = DecisionCompleted(
        correlation: request.correlation,
        answers: <DecisionAnswer>[
          _answer(selectedOptionId: const DecisionOptionId('delete_repo')),
        ],
      );

      final validation = validateDecisionCompletion(
        request: request,
        completion: completion,
      );

      expect(validation.success, isFalse);
      expect(validation.error?.code, 'unknown_choice');
    });

    test(
      'validates complete distributions only when provider requires them',
      () {
        final request = _request();
        final partial = DecisionCompleted(
          correlation: request.correlation,
          answers: <DecisionAnswer>[
            _answer(
              probabilities: <DecisionOptionId, double>{
                const DecisionOptionId('apply_edit'): 0.8,
              },
            ),
          ],
        );

        expect(
          validateDecisionCompletion(
            request: request,
            completion: partial,
          ).success,
          isTrue,
        );
        final strict = validateDecisionCompletion(
          request: request,
          completion: partial,
          requireCompleteProbabilityDistribution: true,
        );
        expect(strict.success, isFalse);
        expect(strict.error?.code, 'incomplete_probability_distribution');
      },
    );

    group('stale identity rejection', () {
      test('rejects a completion whose correlation does not match', () {
        for (final (name, mutated) in <(String, DecisionCorrelation)>[
          (
            'request_id',
            const DecisionCorrelation(
              requestId: DecisionRequestId('request-OTHER'),
              cutId: DecisionCutId('cut-3'),
              stateRevision: DecisionStateRevision('revision-8'),
              cancellationId: DecisionCancellationId('cancel-5'),
            ),
          ),
          (
            'cut_id',
            const DecisionCorrelation(
              requestId: DecisionRequestId('request-1'),
              cutId: DecisionCutId('cut-OTHER'),
              stateRevision: DecisionStateRevision('revision-8'),
              cancellationId: DecisionCancellationId('cancel-5'),
            ),
          ),
          (
            'state_revision',
            const DecisionCorrelation(
              requestId: DecisionRequestId('request-1'),
              cutId: DecisionCutId('cut-3'),
              stateRevision: DecisionStateRevision('revision-OTHER'),
              cancellationId: DecisionCancellationId('cancel-5'),
            ),
          ),
          (
            'cancellation_id',
            const DecisionCorrelation(
              requestId: DecisionRequestId('request-1'),
              cutId: DecisionCutId('cut-3'),
              stateRevision: DecisionStateRevision('revision-8'),
              cancellationId: DecisionCancellationId('cancel-OTHER'),
            ),
          ),
        ]) {
          final validation = validateDecisionCompletion(
            request: _request(),
            completion: DecisionCompleted(
              correlation: mutated,
              answers: <DecisionAnswer>[_answer()],
            ),
          );
          expect(validation.success, isFalse, reason: name);
          expect(validation.error?.code, 'correlation_mismatch', reason: name);
        }
      });

      test('rejects answers with stale question version or candidate set', () {
        final staleVersion = DecisionCompleted(
          correlation: _request().correlation,
          answers: <DecisionAnswer>[
            _answer(questionVersion: const DecisionQuestionVersion('v0')),
          ],
        );
        final staleCandidateSet = DecisionCompleted(
          correlation: _request().correlation,
          answers: <DecisionAnswer>[
            _answer(
              candidateSetId: const DecisionCandidateSetId('candidate-set-0'),
            ),
          ],
        );

        for (final completion in <DecisionCompleted>[
          staleVersion,
          staleCandidateSet,
        ]) {
          final validation = validateDecisionCompletion(
            request: _request(),
            completion: completion,
          );
          expect(validation.success, isFalse);
          expect(validation.error?.code, 'question_identity_mismatch');
        }
      });
    });

    group('answer set validation', () {
      test('rejects missing answers', () {
        final request = _request(
          questions: <FiniteChoiceQuestion>[_question(), _secondQuestion()],
        );
        final validation = validateDecisionCompletion(
          request: request,
          completion: DecisionCompleted(
            correlation: request.correlation,
            answers: <DecisionAnswer>[_answer()],
          ),
        );

        expect(validation.success, isFalse);
        expect(validation.error?.code, 'missing_answers');
      });

      test('rejects duplicate answers for the same question', () {
        final validation = validateDecisionCompletion(
          request: _request(),
          completion: DecisionCompleted(
            correlation: _request().correlation,
            answers: <DecisionAnswer>[_answer(), _answer()],
          ),
        );

        expect(validation.success, isFalse);
        expect(validation.error?.code, 'duplicate_answer');
      });

      test('rejects answers for unknown questions', () {
        final validation = validateDecisionCompletion(
          request: _request(),
          completion: DecisionCompleted(
            correlation: _request().correlation,
            answers: <DecisionAnswer>[
              _answer(questionId: const DecisionQuestionId('unknown')),
            ],
          ),
        );

        expect(validation.success, isFalse);
        expect(validation.error?.code, 'unknown_question');
      });
    });

    group('value validation', () {
      test('rejects out-of-range and non-finite confidence', () {
        for (final confidence in <double>[1.5, -0.1, double.nan]) {
          final validation = validateDecisionCompletion(
            request: _request(),
            completion: DecisionCompleted(
              correlation: _request().correlation,
              answers: <DecisionAnswer>[_answer(confidence: confidence)],
            ),
          );
          expect(validation.success, isFalse, reason: '$confidence');
          expect(validation.error?.code, 'invalid_confidence');
        }
      });

      test('rejects out-of-range and non-finite probabilities', () {
        for (final value in <double>[-0.2, 1.2, double.nan]) {
          final validation = validateDecisionCompletion(
            request: _request(),
            completion: DecisionCompleted(
              correlation: _request().correlation,
              answers: <DecisionAnswer>[
                _answer(
                  probabilities: <DecisionOptionId, double>{
                    const DecisionOptionId('apply_edit'): value,
                  },
                ),
              ],
            ),
          );
          expect(validation.success, isFalse, reason: '$value');
          expect(validation.error?.code, 'invalid_probability');
        }
      });

      test('rejects probabilities for options outside the candidate set', () {
        final validation = validateDecisionCompletion(
          request: _request(),
          completion: DecisionCompleted(
            correlation: _request().correlation,
            answers: <DecisionAnswer>[
              _answer(
                probabilities: <DecisionOptionId, double>{
                  const DecisionOptionId('delete_repo'): 0.5,
                },
              ),
            ],
          ),
        );

        expect(validation.success, isFalse);
        expect(validation.error?.code, 'unknown_probability_option');
      });

      test('disposition must match the explicit abstention option', () {
        final selectedButAbstained = validateDecisionCompletion(
          request: _request(),
          completion: DecisionCompleted(
            correlation: _request().correlation,
            answers: <DecisionAnswer>[
              _answer(disposition: DecisionAnswerDisposition.abstained),
            ],
          ),
        );
        final normalSelection = validateDecisionCompletion(
          request: _request(),
          completion: DecisionCompleted(
            correlation: _request().correlation,
            answers: <DecisionAnswer>[_answer()],
          ),
        );

        expect(selectedButAbstained.error?.code, 'abstention_mismatch');
        expect(normalSelection.success, isTrue);
      });

      test('rejects invalid usage and timing metadata', () {
        final negativeUsage = DecisionCompleted(
          correlation: _request().correlation,
          answers: <DecisionAnswer>[_answer()],
          metadata: DecisionResponseMetadata(
            usage: const DecisionUsage(
              provenance: DecisionUsageProvenance.providerReported,
              inputTokens: -1,
            ),
          ),
        );
        final negativeTiming = DecisionCompleted(
          correlation: _request().correlation,
          answers: <DecisionAnswer>[_answer()],
          metadata: DecisionResponseMetadata(
            timing: const DecisionTiming(elapsed: Duration(microseconds: -1)),
          ),
        );

        expect(
          validateDecisionCompletion(
            request: _request(),
            completion: negativeUsage,
          ).error?.code,
          'invalid_usage_metadata',
        );
        expect(
          validateDecisionCompletion(
            request: _request(),
            completion: negativeTiming,
          ).error?.code,
          'invalid_timing_metadata',
        );
      });
    });

    group('round-trip and explicit absence', () {
      test('answer round-trips probabilities, confidence and disposition', () {
        final answer = _answer(
          disposition: DecisionAnswerDisposition.abstained,
          selectedOptionId: const DecisionOptionId('insufficient_evidence'),
          probabilities: <DecisionOptionId, double>{
            const DecisionOptionId('apply_edit'): 0.3,
            const DecisionOptionId('insufficient_evidence'): 0.7,
          },
          confidence: 0.4,
        );
        final roundTrip = DecisionAnswer.fromJson(answer.toJson());

        expect(roundTrip.questionId, answer.questionId);
        expect(roundTrip.questionVersion, answer.questionVersion);
        expect(roundTrip.candidateSetId, answer.candidateSetId);
        expect(roundTrip.selectedOptionId, answer.selectedOptionId);
        expect(roundTrip.disposition, answer.disposition);
        expect(roundTrip.probabilities, answer.probabilities);
        expect(roundTrip.confidence, answer.confidence);
      });

      test('absent metadata stays absent after round-trip', () {
        final answer = _answer(confidence: null);
        final roundTrip = DecisionAnswer.fromJson(answer.toJson());

        expect(roundTrip.probabilities, isNull);
        expect(roundTrip.confidence, isNull);
      });

      test('completion without metadata invents no values', () {
        final request = _request();
        final completion = DecisionCompleted(
          correlation: request.correlation,
          answers: <DecisionAnswer>[_answer()],
        );

        expect(completion.metadata.provider, isNull);
        expect(completion.metadata.resolvedModel, isNull);
        expect(completion.metadata.requestedModel, isNull);
        expect(completion.metadata.usage, isNull);
        expect(completion.metadata.timing, isNull);
        expect(completion.metadata.additional, isEmpty);
      });
    });

    group('capability facts', () {
      test('unsupported question kind is a typed unsupported outcome', () {
        final capabilities = _capabilities(
          supportedQuestionKinds: const <DecisionQuestionKind>{},
        );

        final validation = validateDecisionRequest(
          _request(),
          againstCapabilities: capabilities,
        );

        expect(validation.success, isFalse);
        expect(validation.error?.code, 'unsupported_question_kind');
      });

      test('bounds reject oversized questions and options', () {
        final tooManyQuestions = validateDecisionRequest(
          _request(
            questions: <FiniteChoiceQuestion>[_question(), _secondQuestion()],
          ),
          againstCapabilities: _capabilities(),
        );
        final tooManyOptions = validateDecisionRequest(
          _request(
            questions: <FiniteChoiceQuestion>[
              _question(
                options: <DecisionOption>[
                  const DecisionOption(
                    id: DecisionOptionId('a'),
                    description: 'a',
                  ),
                  const DecisionOption(
                    id: DecisionOptionId('b'),
                    description: 'b',
                  ),
                  const DecisionOption(
                    id: DecisionOptionId('c'),
                    description: 'c',
                  ),
                  const DecisionOption(
                    id: DecisionOptionId('insufficient_evidence'),
                    description: 'More evidence is needed',
                  ),
                ],
              ),
            ],
          ),
          againstCapabilities: _capabilities(),
        );

        expect(tooManyQuestions.error?.code, 'too_many_questions');
        expect(tooManyOptions.error?.code, 'too_many_options');
      });

      test('capabilities stay separate from readiness', () {
        final capabilities = _capabilities();
        const unavailable = DecisionProviderReadiness(
          state: DecisionReadinessState.unavailable,
          reasonCode: 'provider_offline',
        );

        expect(unavailable.isReady, isFalse);
        expect(capabilities.supportedQuestionKinds, <DecisionQuestionKind>{
          DecisionQuestionKind.finiteChoice,
        });
        expect(
          capabilities.executionLocation,
          DecisionExecutionLocation.hosted,
        );
        expect(
          capabilities.networkRequirement,
          DecisionNetworkRequirement.required,
        );
        expect(capabilities.supportsCancellation, isTrue);
      });
    });

    group('outcome shapes', () {
      test(
        'unavailable, unsupported, cancelled and failed carry correlation',
        () {
          const correlation = DecisionCorrelation(
            requestId: DecisionRequestId('request-1'),
            cutId: DecisionCutId('cut-3'),
            stateRevision: DecisionStateRevision('revision-8'),
            cancellationId: DecisionCancellationId('cancel-5'),
          );
          const unavailable = DecisionUnavailable(
            correlation: correlation,
            failure: DecisionFailure(
              code: DecisionFailureCode.unavailable,
              message: 'provider offline',
            ),
          );
          const unsupported = DecisionUnsupported(
            correlation: correlation,
            failure: DecisionFailure(
              code: DecisionFailureCode.unsupported,
              message: 'kind not supported',
            ),
          );
          const cancelled = DecisionCancelled(
            correlation: correlation,
            failure: DecisionFailure(
              code: DecisionFailureCode.cancelled,
              message: 'cancelled by host',
            ),
          );
          const failed = DecisionFailed(
            correlation: correlation,
            failure: DecisionFailure(
              code: DecisionFailureCode.malformedResponse,
              message: 'unparseable answer',
            ),
          );

          for (final outcome in <DecisionOutcome>[
            unavailable,
            unsupported,
            cancelled,
            failed,
          ]) {
            expect(outcome.correlation, correlation);
          }
          expect(unavailable.failure.code, DecisionFailureCode.unavailable);
          expect(unsupported.failure.code, DecisionFailureCode.unsupported);
          expect(cancelled.failure.code, DecisionFailureCode.cancelled);
          expect(failed.failure.code, DecisionFailureCode.malformedResponse);
        },
      );
    });

    test('capability bounds are checked without readiness or network work', () {
      final capabilities = DecisionProviderCapabilities(
        supportedQuestionKinds: const <DecisionQuestionKind>{
          DecisionQuestionKind.finiteChoice,
        },
        bounds: const DecisionProviderBounds(
          maxStateUtf8Bytes: 2,
          maxRequestUtf8Bytes: 1024,
          maxQuestionsPerRequest: 1,
          maxOptionsPerQuestion: 2,
        ),
        executionLocation: DecisionExecutionLocation.hosted,
        networkRequirement: DecisionNetworkRequirement.required,
        supportsCancellation: true,
      );

      final validation = validateDecisionRequest(
        _request(),
        againstCapabilities: capabilities,
      );

      expect(validation.success, isFalse);
      expect(validation.error?.code, 'state_too_large');
    });
  });
}

DecisionRequest _request({List<FiniteChoiceQuestion>? questions}) =>
    DecisionRequest(
      correlation: const DecisionCorrelation(
        requestId: DecisionRequestId('request-1'),
        cutId: DecisionCutId('cut-3'),
        stateRevision: DecisionStateRevision('revision-8'),
        cancellationId: DecisionCancellationId('cancel-5'),
      ),
      state: 'The verification failed after an edit.',
      questions: questions ?? <FiniteChoiceQuestion>[_question()],
    );

FiniteChoiceQuestion _question({List<DecisionOption>? options}) =>
    FiniteChoiceQuestion(
      id: const DecisionQuestionId('next_operation'),
      version: const DecisionQuestionVersion('v1'),
      candidateSetId: const DecisionCandidateSetId('candidate-set-2'),
      instructions: 'Which semantic operation should be proposed next?',
      options:
          options ??
          const <DecisionOption>[
            DecisionOption(
              id: DecisionOptionId('apply_edit'),
              description: 'Apply the typed semantic edit',
            ),
            DecisionOption(
              id: DecisionOptionId('insufficient_evidence'),
              description: 'More evidence is needed',
            ),
          ],
      abstainOptionId: const DecisionOptionId('insufficient_evidence'),
    );

DecisionAnswer _answer({
  DecisionQuestionId questionId = const DecisionQuestionId('next_operation'),
  DecisionQuestionVersion questionVersion = const DecisionQuestionVersion('v1'),
  DecisionCandidateSetId candidateSetId = const DecisionCandidateSetId(
    'candidate-set-2',
  ),
  DecisionOptionId selectedOptionId = const DecisionOptionId('apply_edit'),
  DecisionAnswerDisposition disposition = DecisionAnswerDisposition.selected,
  Map<DecisionOptionId, double>? probabilities,
  double? confidence = 0.6,
}) => DecisionAnswer(
  questionId: questionId,
  questionVersion: questionVersion,
  candidateSetId: candidateSetId,
  selectedOptionId: selectedOptionId,
  disposition: disposition,
  probabilities: probabilities,
  confidence: confidence,
);

FiniteChoiceQuestion _secondQuestion() => FiniteChoiceQuestion(
  id: const DecisionQuestionId('which_evidence'),
  version: const DecisionQuestionVersion('v1'),
  candidateSetId: const DecisionCandidateSetId('candidate-set-9'),
  instructions: 'Which evidence fragment should be attached next?',
  options: const <DecisionOption>[
    DecisionOption(
      id: DecisionOptionId('fragment_a'),
      description: 'Compiler diagnostics',
    ),
    DecisionOption(
      id: DecisionOptionId('fragment_b'),
      description: 'Runtime trace',
    ),
    DecisionOption(
      id: DecisionOptionId('insufficient_evidence'),
      description: 'More evidence is needed',
    ),
  ],
  abstainOptionId: const DecisionOptionId('insufficient_evidence'),
);

DecisionProviderCapabilities _capabilities({
  Set<DecisionQuestionKind> supportedQuestionKinds =
      const <DecisionQuestionKind>{DecisionQuestionKind.finiteChoice},
}) => DecisionProviderCapabilities(
  supportedQuestionKinds: supportedQuestionKinds,
  bounds: const DecisionProviderBounds(
    maxStateUtf8Bytes: 64 * 1024,
    maxRequestUtf8Bytes: 256 * 1024,
    maxQuestionsPerRequest: 1,
    maxOptionsPerQuestion: 2,
  ),
  executionLocation: DecisionExecutionLocation.hosted,
  networkRequirement: DecisionNetworkRequirement.required,
  supportsCancellation: true,
);
