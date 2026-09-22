import 'dart:collection';

import 'package:meta/meta.dart';

/// Stable provider-neutral question shapes supported by a decision provider.
enum DecisionQuestionKind { finiteChoice }

/// Where inference executes from the consumer's point of view.
enum DecisionExecutionLocation { local, hosted }

/// Whether dispatch requires network access.
enum DecisionNetworkRequirement { none, required }

/// Local, non-probing provider readiness.
enum DecisionReadinessState { ready, unavailable, disposed }

/// How a finite-choice answer resolved.
enum DecisionAnswerDisposition { selected, abstained }

/// Stable provider-neutral failure categories.
enum DecisionFailureCode {
  invalidRequest,
  unsupported,
  unavailable,
  authentication,
  quotaExceeded,
  rateLimited,
  timeout,
  network,
  malformedResponse,
  providerRejected,
  cancelled,
  disposed,
  internal,
}

/// Identifies where usage values came from.
enum DecisionUsageProvenance { providerReported, hostMeasured, estimated }

/// Base value type for opaque host-owned correlation identifiers.
@immutable
sealed class DecisionOpaqueId {
  const DecisionOpaqueId(this.value);

  final String value;

  @override
  bool operator ==(final Object other) =>
      other.runtimeType == runtimeType &&
      other is DecisionOpaqueId &&
      other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => value;
}

final class DecisionRequestId extends DecisionOpaqueId {
  const DecisionRequestId(super.value);
}

final class DecisionCutId extends DecisionOpaqueId {
  const DecisionCutId(super.value);
}

final class DecisionStateRevision extends DecisionOpaqueId {
  const DecisionStateRevision(super.value);
}

final class DecisionCancellationId extends DecisionOpaqueId {
  const DecisionCancellationId(super.value);
}

final class DecisionQuestionId extends DecisionOpaqueId {
  const DecisionQuestionId(super.value);
}

final class DecisionQuestionVersion extends DecisionOpaqueId {
  const DecisionQuestionVersion(super.value);
}

final class DecisionCandidateSetId extends DecisionOpaqueId {
  const DecisionCandidateSetId(super.value);
}

final class DecisionOptionId extends DecisionOpaqueId {
  const DecisionOptionId(super.value);
}

/// Host-owned identifiers copied to outcomes without trusting provider echoes.
final class DecisionCorrelation {
  const DecisionCorrelation({
    required this.requestId,
    required this.cutId,
    required this.stateRevision,
    required this.cancellationId,
  });

  factory DecisionCorrelation.fromJson(final Map<String, dynamic> json) =>
      DecisionCorrelation(
        requestId: DecisionRequestId(json['request_id'] as String),
        cutId: DecisionCutId(json['cut_id'] as String),
        stateRevision: DecisionStateRevision(json['state_revision'] as String),
        cancellationId: DecisionCancellationId(
          json['cancellation_id'] as String,
        ),
      );

  final DecisionRequestId requestId;
  final DecisionCutId cutId;
  final DecisionStateRevision stateRevision;
  final DecisionCancellationId cancellationId;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'request_id': requestId.value,
    'cut_id': cutId.value,
    'state_revision': stateRevision.value,
    'cancellation_id': cancellationId.value,
  };
}

/// Static bounds advertised without network I/O.
final class DecisionProviderBounds {
  const DecisionProviderBounds({
    required this.maxStateUtf8Bytes,
    required this.maxRequestUtf8Bytes,
    required this.maxQuestionsPerRequest,
    required this.maxOptionsPerQuestion,
  });

  final int maxStateUtf8Bytes;
  final int maxRequestUtf8Bytes;
  final int maxQuestionsPerRequest;
  final int maxOptionsPerQuestion;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'max_state_utf8_bytes': maxStateUtf8Bytes,
    'max_request_utf8_bytes': maxRequestUtf8Bytes,
    'max_questions_per_request': maxQuestionsPerRequest,
    'max_options_per_question': maxOptionsPerQuestion,
  };
}

/// Static capability facts. Reading this value must never perform I/O.
final class DecisionProviderCapabilities {
  DecisionProviderCapabilities({
    required final Set<DecisionQuestionKind> supportedQuestionKinds,
    required this.bounds,
    required this.executionLocation,
    required this.networkRequirement,
    required this.supportsCancellation,
  }) : supportedQuestionKinds = Set<DecisionQuestionKind>.unmodifiable(
         supportedQuestionKinds,
       );

  final Set<DecisionQuestionKind> supportedQuestionKinds;
  final DecisionProviderBounds bounds;
  final DecisionExecutionLocation executionLocation;
  final DecisionNetworkRequirement networkRequirement;
  final bool supportsCancellation;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'supported_question_kinds': supportedQuestionKinds
        .map((final value) => value.name)
        .toList(growable: false),
    'bounds': bounds.toJson(),
    'execution_location': executionLocation.name,
    'network_requirement': networkRequirement.name,
    'supports_cancellation': supportsCancellation,
  };
}

/// Cached/local readiness. Reading this value must never perform I/O.
final class DecisionProviderReadiness {
  const DecisionProviderReadiness({
    required this.state,
    this.reasonCode,
    this.message = '',
  });

  final DecisionReadinessState state;
  final String? reasonCode;
  final String message;

  bool get isReady => state == DecisionReadinessState.ready;
}

final class DecisionOption {
  const DecisionOption({required this.id, required this.description});

  factory DecisionOption.fromJson(final Map<String, dynamic> json) =>
      DecisionOption(
        id: DecisionOptionId(json['id'] as String),
        description: json['description'] as String,
      );

  final DecisionOptionId id;
  final String description;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id.value,
    'description': description,
  };
}

/// A finite choice with an explicit host-supplied abstention option.
///
/// Even exhaustive candidate sets retain an abstention option so a provider can
/// report insufficient evidence without inventing or forcing a domain choice.
final class FiniteChoiceQuestion {
  FiniteChoiceQuestion({
    required this.id,
    required this.version,
    required this.candidateSetId,
    required this.instructions,
    required final List<DecisionOption> options,
    required this.abstainOptionId,
    this.isExhaustive = false,
  }) : options = List<DecisionOption>.unmodifiable(options);

  factory FiniteChoiceQuestion.fromJson(
    final Map<String, dynamic> json,
  ) => FiniteChoiceQuestion(
    id: DecisionQuestionId(json['id'] as String),
    version: DecisionQuestionVersion(json['version'] as String),
    candidateSetId: DecisionCandidateSetId(json['candidate_set_id'] as String),
    instructions: json['instructions'] as String,
    options: (json['options'] as List<dynamic>)
        .map(
          (final value) =>
              DecisionOption.fromJson((value as Map).cast<String, dynamic>()),
        )
        .toList(growable: false),
    abstainOptionId: DecisionOptionId(json['abstain_option_id'] as String),
    isExhaustive: json['is_exhaustive'] as bool? ?? false,
  );

  final DecisionQuestionId id;
  final DecisionQuestionVersion version;
  final DecisionCandidateSetId candidateSetId;
  final String instructions;
  final List<DecisionOption> options;
  final DecisionOptionId abstainOptionId;
  final bool isExhaustive;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id.value,
    'version': version.value,
    'candidate_set_id': candidateSetId.value,
    'instructions': instructions,
    'options': options.map((final option) => option.toJson()).toList(),
    'abstain_option_id': abstainOptionId.value,
    'is_exhaustive': isExhaustive,
  };
}

/// A decision request whose correlation and candidates are immutable snapshots.
final class DecisionRequest {
  DecisionRequest({
    required this.correlation,
    required this.state,
    required final List<FiniteChoiceQuestion> questions,
  }) : questions = List<FiniteChoiceQuestion>.unmodifiable(questions);

  factory DecisionRequest.fromJson(final Map<String, dynamic> json) =>
      DecisionRequest(
        correlation: DecisionCorrelation.fromJson(
          (json['correlation'] as Map).cast<String, dynamic>(),
        ),
        state: json['state'] as String,
        questions: (json['questions'] as List<dynamic>)
            .map(
              (final value) => FiniteChoiceQuestion.fromJson(
                (value as Map).cast<String, dynamic>(),
              ),
            )
            .toList(growable: false),
      );

  final DecisionCorrelation correlation;
  final String state;
  final List<FiniteChoiceQuestion> questions;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'correlation': correlation.toJson(),
    'state': state,
    'questions': questions.map((final question) => question.toJson()).toList(),
  };
}

final class DecisionAnswer {
  DecisionAnswer({
    required this.questionId,
    required this.questionVersion,
    required this.candidateSetId,
    required this.selectedOptionId,
    required this.disposition,
    final Map<DecisionOptionId, double>? probabilities,
    this.confidence,
  }) : probabilities = probabilities == null
           ? null
           : UnmodifiableMapView<DecisionOptionId, double>(
               Map<DecisionOptionId, double>.of(probabilities),
             );

  factory DecisionAnswer.fromJson(final Map<String, dynamic> json) {
    final rawProbabilities = json['probabilities'] as Map?;
    return DecisionAnswer(
      questionId: DecisionQuestionId(json['question_id'] as String),
      questionVersion: DecisionQuestionVersion(
        json['question_version'] as String,
      ),
      candidateSetId: DecisionCandidateSetId(
        json['candidate_set_id'] as String,
      ),
      selectedOptionId: DecisionOptionId(json['selected_option_id'] as String),
      disposition: DecisionAnswerDisposition.values.byName(
        json['disposition'] as String,
      ),
      probabilities: rawProbabilities?.map(
        (final key, final value) => MapEntry(
          DecisionOptionId(key as String),
          (value as num).toDouble(),
        ),
      ),
      confidence: (json['confidence'] as num?)?.toDouble(),
    );
  }

  final DecisionQuestionId questionId;
  final DecisionQuestionVersion questionVersion;
  final DecisionCandidateSetId candidateSetId;
  final DecisionOptionId selectedOptionId;
  final DecisionAnswerDisposition disposition;
  final Map<DecisionOptionId, double>? probabilities;
  final double? confidence;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'question_id': questionId.value,
    'question_version': questionVersion.value,
    'candidate_set_id': candidateSetId.value,
    'selected_option_id': selectedOptionId.value,
    'disposition': disposition.name,
    if (probabilities != null)
      'probabilities': probabilities!.map(
        (final key, final value) => MapEntry(key.value, value),
      ),
    if (confidence != null) 'confidence': confidence,
  };
}

final class DecisionUsage {
  const DecisionUsage({
    required this.provenance,
    this.inputTokens,
    this.outputTokens,
    this.cost,
    this.currency,
  });

  final DecisionUsageProvenance provenance;
  final int? inputTokens;
  final int? outputTokens;
  final double? cost;
  final String? currency;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'provenance': provenance.name,
    if (inputTokens != null) 'input_tokens': inputTokens,
    if (outputTokens != null) 'output_tokens': outputTokens,
    if (cost != null) 'cost': cost,
    if (currency != null) 'currency': currency,
  };
}

final class DecisionTiming {
  const DecisionTiming({required this.elapsed});

  final Duration elapsed;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'elapsed_microseconds': elapsed.inMicroseconds,
  };
}

final class DecisionResponseMetadata {
  DecisionResponseMetadata({
    this.provider,
    this.providerRequestId,
    this.requestedModel,
    this.resolvedModel,
    this.usage,
    this.timing,
    final Map<String, Object?> additional = const <String, Object?>{},
  }) : additional = UnmodifiableMapView<String, Object?>(
         Map<String, Object?>.of(additional),
       );

  final String? provider;
  final String? providerRequestId;
  final String? requestedModel;
  final String? resolvedModel;
  final DecisionUsage? usage;
  final DecisionTiming? timing;
  final Map<String, Object?> additional;
}

final class DecisionFailure {
  const DecisionFailure({
    required this.code,
    required this.message,
    this.retryable = false,
    this.details,
  });

  final DecisionFailureCode code;
  final String message;
  final bool retryable;
  final Object? details;
}

sealed class DecisionOutcome {
  const DecisionOutcome({required this.correlation});

  final DecisionCorrelation correlation;
}

final class DecisionCompleted extends DecisionOutcome {
  DecisionCompleted({
    required super.correlation,
    required final List<DecisionAnswer> answers,
    final DecisionResponseMetadata? metadata,
  }) : answers = List<DecisionAnswer>.unmodifiable(answers),
       metadata = metadata ?? DecisionResponseMetadata();

  final List<DecisionAnswer> answers;
  final DecisionResponseMetadata metadata;
}

final class DecisionUnavailable extends DecisionOutcome {
  const DecisionUnavailable({
    required super.correlation,
    required this.failure,
  });

  final DecisionFailure failure;
}

final class DecisionUnsupported extends DecisionOutcome {
  const DecisionUnsupported({
    required super.correlation,
    required this.failure,
  });

  final DecisionFailure failure;
}

final class DecisionCancelled extends DecisionOutcome {
  const DecisionCancelled({required super.correlation, required this.failure});

  final DecisionFailure failure;
}

final class DecisionFailed extends DecisionOutcome {
  const DecisionFailed({required super.correlation, required this.failure});

  final DecisionFailure failure;
}
