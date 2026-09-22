import 'dart:convert';

import '../inference_result.dart';
import 'decision_models.dart';

InferenceResult<void> validateDecisionRequest(
  final DecisionRequest request, {
  final DecisionProviderCapabilities? againstCapabilities,
}) {
  final ids = <DecisionOpaqueId>[
    request.correlation.requestId,
    request.correlation.cutId,
    request.correlation.stateRevision,
    request.correlation.cancellationId,
  ];
  final emptyId = ids.where((final id) => id.value.trim().isEmpty).firstOrNull;
  if (emptyId != null) {
    return _invalid(
      'empty_correlation_id',
      'Correlation IDs must be non-empty',
    );
  }
  if (request.state.trim().isEmpty) {
    return _invalid('empty_state', 'Decision state must be non-empty');
  }
  if (request.questions.isEmpty) {
    return _invalid('empty_questions', 'At least one question is required');
  }

  final questionIds = <DecisionQuestionId>{};
  for (final question in request.questions) {
    if (!questionIds.add(question.id)) {
      return _invalid(
        'duplicate_question_id',
        'Question IDs must be unique',
        details: question.id.value,
      );
    }
    final questionIdsToCheck = <DecisionOpaqueId>[
      question.id,
      question.version,
      question.candidateSetId,
      question.abstainOptionId,
    ];
    if (questionIdsToCheck.any((final id) => id.value.trim().isEmpty)) {
      return _invalid(
        'empty_question_id',
        'Question identifiers must be non-empty',
        details: question.id.value,
      );
    }
    if (question.instructions.trim().isEmpty) {
      return _invalid(
        'empty_question_instructions',
        'Question instructions must be non-empty',
        details: question.id.value,
      );
    }
    if (question.options.length < 2) {
      return _invalid(
        'insufficient_options',
        'Finite-choice questions require at least two options',
        details: question.id.value,
      );
    }
    final optionIds = <DecisionOptionId>{};
    for (final option in question.options) {
      if (option.id.value.trim().isEmpty || option.description.trim().isEmpty) {
        return _invalid(
          'invalid_option',
          'Option IDs and descriptions must be non-empty',
          details: question.id.value,
        );
      }
      if (!optionIds.add(option.id)) {
        return _invalid(
          'duplicate_option_id',
          'Option IDs must be unique within a question',
          details: option.id.value,
        );
      }
    }
    if (!optionIds.contains(question.abstainOptionId)) {
      return _invalid(
        'missing_abstain_option',
        'The abstention option must be part of the candidate set',
        details: question.id.value,
      );
    }
  }

  final capabilities = againstCapabilities;
  if (capabilities != null) {
    if (!capabilities.supportedQuestionKinds.contains(
      DecisionQuestionKind.finiteChoice,
    )) {
      return _unsupported(
        'unsupported_question_kind',
        'Provider does not support finite-choice questions',
      );
    }
    final bounds = capabilities.bounds;
    if (utf8.encode(request.state).length > bounds.maxStateUtf8Bytes) {
      return _unsupported(
        'state_too_large',
        'Decision state exceeds provider bounds',
      );
    }
    if (utf8.encode(jsonEncode(request.toJson())).length >
        bounds.maxRequestUtf8Bytes) {
      return _unsupported(
        'request_too_large',
        'Serialized decision request exceeds provider bounds',
      );
    }
    if (request.questions.length > bounds.maxQuestionsPerRequest) {
      return _unsupported(
        'too_many_questions',
        'Decision request exceeds provider question bounds',
      );
    }
    if (request.questions.any(
      (final question) =>
          question.options.length > bounds.maxOptionsPerQuestion,
    )) {
      return _unsupported(
        'too_many_options',
        'A question exceeds provider option bounds',
      );
    }
  }
  return InferenceResult<void>.ok(null);
}

InferenceResult<void> validateDecisionCompletion({
  required final DecisionRequest request,
  required final DecisionCompleted completion,
  final bool requireCompleteProbabilityDistribution = false,
  final double probabilitySumTolerance = 0.000001,
}) {
  if (!probabilitySumTolerance.isFinite || probabilitySumTolerance < 0) {
    return _invalid(
      'invalid_probability_tolerance',
      'Probability sum tolerance must be finite and non-negative',
    );
  }
  if (!_sameCorrelation(request.correlation, completion.correlation)) {
    return _invalid(
      'correlation_mismatch',
      'Decision completion does not match the originating request',
    );
  }
  final questions = <DecisionQuestionId, FiniteChoiceQuestion>{
    for (final question in request.questions) question.id: question,
  };
  final answerIds = <DecisionQuestionId>{};
  for (final answer in completion.answers) {
    if (!answerIds.add(answer.questionId)) {
      return _invalid(
        'duplicate_answer',
        'A question may be answered only once',
        details: answer.questionId.value,
      );
    }
    final question = questions[answer.questionId];
    if (question == null) {
      return _invalid(
        'unknown_question',
        'Completion contains an answer for an unknown question',
        details: answer.questionId.value,
      );
    }
    if (answer.questionVersion != question.version ||
        answer.candidateSetId != question.candidateSetId) {
      return _invalid(
        'question_identity_mismatch',
        'Answer version or candidate-set identity is stale',
        details: answer.questionId.value,
      );
    }
    final optionIds = question.options.map((final option) => option.id).toSet();
    if (!optionIds.contains(answer.selectedOptionId)) {
      return _invalid(
        'unknown_choice',
        'Answer selected an option absent from the original candidate set',
        details: answer.selectedOptionId.value,
      );
    }
    final selectedAbstention =
        answer.selectedOptionId == question.abstainOptionId;
    if (selectedAbstention !=
        (answer.disposition == DecisionAnswerDisposition.abstained)) {
      return _invalid(
        'abstention_mismatch',
        'Answer disposition must match the explicit abstention option',
        details: answer.questionId.value,
      );
    }
    final confidence = answer.confidence;
    if (confidence != null &&
        (!confidence.isFinite || confidence < 0 || confidence > 1)) {
      return _invalid(
        'invalid_confidence',
        'Confidence must be finite and between zero and one',
        details: answer.questionId.value,
      );
    }
    final probabilities = answer.probabilities;
    if (probabilities != null) {
      if (probabilities.keys.any((final id) => !optionIds.contains(id))) {
        return _invalid(
          'unknown_probability_option',
          'Probabilities contain an option absent from the request',
          details: answer.questionId.value,
        );
      }
      if (probabilities.values.any(
        (final value) => !value.isFinite || value < 0 || value > 1,
      )) {
        return _invalid(
          'invalid_probability',
          'Probabilities must be finite and between zero and one',
          details: answer.questionId.value,
        );
      }
      if (requireCompleteProbabilityDistribution) {
        if (probabilities.length != optionIds.length ||
            !probabilities.keys.toSet().containsAll(optionIds)) {
          return _invalid(
            'incomplete_probability_distribution',
            'Provider contract requires one probability per supplied option',
            details: answer.questionId.value,
          );
        }
        final sum = probabilities.values.fold<double>(
          0,
          (final total, final value) => total + value,
        );
        if ((sum - 1).abs() > probabilitySumTolerance) {
          return _invalid(
            'invalid_probability_distribution',
            'Provider probability distribution must sum to one',
            details: <String, Object?>{
              'question_id': answer.questionId.value,
              'sum': sum,
            },
          );
        }
      }
    } else if (requireCompleteProbabilityDistribution) {
      return _invalid(
        'missing_probability_distribution',
        'Provider contract requires a probability distribution',
        details: answer.questionId.value,
      );
    }
  }
  if (answerIds.length != questions.length ||
      !answerIds.containsAll(questions.keys)) {
    return _invalid(
      'missing_answers',
      'Completion must answer every requested question',
    );
  }
  final usage = completion.metadata.usage;
  if (usage != null) {
    if ((usage.inputTokens != null && usage.inputTokens! < 0) ||
        (usage.outputTokens != null && usage.outputTokens! < 0) ||
        (usage.cost != null && (!usage.cost!.isFinite || usage.cost! < 0))) {
      return _invalid(
        'invalid_usage_metadata',
        'Usage counts and cost must be finite and non-negative',
      );
    }
  }
  if (completion.metadata.timing case final timing?) {
    if (timing.elapsed.isNegative) {
      return _invalid(
        'invalid_timing_metadata',
        'Elapsed decision time must be non-negative',
      );
    }
  }
  return InferenceResult<void>.ok(null);
}

bool _sameCorrelation(
  final DecisionCorrelation left,
  final DecisionCorrelation right,
) =>
    left.requestId == right.requestId &&
    left.cutId == right.cutId &&
    left.stateRevision == right.stateRevision &&
    left.cancellationId == right.cancellationId;

InferenceResult<void> _invalid(
  final String code,
  final String message, {
  final Object? details,
}) =>
    InferenceResult<void>.fail(code: code, message: message, details: details);

InferenceResult<void> _unsupported(final String code, final String message) =>
    InferenceResult<void>.fail(code: code, message: message);
