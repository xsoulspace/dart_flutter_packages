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
  DecisionOptionId selectedOptionId = const DecisionOptionId('apply_edit'),
  DecisionAnswerDisposition disposition = DecisionAnswerDisposition.selected,
  Map<DecisionOptionId, double>? probabilities,
}) => DecisionAnswer(
  questionId: const DecisionQuestionId('next_operation'),
  questionVersion: const DecisionQuestionVersion('v1'),
  candidateSetId: const DecisionCandidateSetId('candidate-set-2'),
  selectedOptionId: selectedOptionId,
  disposition: disposition,
  probabilities: probabilities,
  confidence: 0.6,
);
