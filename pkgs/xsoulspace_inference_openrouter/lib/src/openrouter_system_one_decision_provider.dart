import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// Optional OpenRouter System One adapter for bounded finite choices.
///
/// Construction is explicit and performs no I/O. This adapter calls
/// `/api/v1/systemone`; it is independent from [OpenRouterInferenceClient] and
/// never uses the chat-completions endpoint.
///
/// Cancellation is enforced by the adapter, not by the server: a cancelled
/// request is blocked before dispatch or its late response is discarded, even
/// though the remote model cannot abort computation. [capabilities]
/// therefore reports `supportsCancellation: true` in the adapter-enforced
/// sense; hosts must not assume server-side compute abort.
final class OpenRouterSystemOneDecisionProvider implements DecisionProvider {
  OpenRouterSystemOneDecisionProvider({
    required final String apiKey,
    required this.model,
    final Uri? endpoint,
    final http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
    this.maxTransientRetries = 0,
    this.retryDelay = const Duration(milliseconds: 100),
    final int maxStateUtf8Bytes = 1 << 20,
    final int maxRequestUtf8Bytes = 2 << 20,
    final int maxQuestionsPerRequest = 64,
    // The public parameter cannot use the private field name as an initializing
    // formal without making construction inaccessible outside this library.
    // ignore: prefer_initializing_formals
  }) : _apiKey = apiKey,
       endpoint =
           endpoint ?? Uri.parse('https://openrouter.ai/api/v1/systemone'),
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null,
       _capabilities = DecisionProviderCapabilities(
         supportedQuestionKinds: const <DecisionQuestionKind>{
           DecisionQuestionKind.finiteChoice,
         },
         bounds: DecisionProviderBounds(
           maxStateUtf8Bytes: maxStateUtf8Bytes,
           maxRequestUtf8Bytes: maxRequestUtf8Bytes,
           maxQuestionsPerRequest: maxQuestionsPerRequest,
           maxOptionsPerQuestion: 255,
         ),
         executionLocation: DecisionExecutionLocation.hosted,
         networkRequirement: DecisionNetworkRequirement.required,
         supportsCancellation: true,
       ) {
    if (model.trim().isEmpty) {
      throw ArgumentError.value(model, 'model', 'must be non-empty');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
    if (maxTransientRetries < 0) {
      throw ArgumentError.value(
        maxTransientRetries,
        'maxTransientRetries',
        'must be non-negative',
      );
    }
    if (retryDelay.isNegative) {
      throw ArgumentError.value(
        retryDelay,
        'retryDelay',
        'must be non-negative',
      );
    }
  }

  final String _apiKey;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final DecisionProviderCapabilities _capabilities;
  final Set<DecisionCancellationId> _seenCancellationIds =
      <DecisionCancellationId>{};
  final Set<DecisionCancellationId> _preCancelledIds =
      <DecisionCancellationId>{};
  final Map<DecisionCancellationId, _CancellationSignal> _activeSignals =
      <DecisionCancellationId, _CancellationSignal>{};
  bool _disposed = false;

  final String model;
  final Uri endpoint;
  final Duration timeout;
  final int maxTransientRetries;
  final Duration retryDelay;

  @override
  String get id => 'openrouter_system_one';

  @override
  DecisionProviderCapabilities get capabilities => _capabilities;

  @override
  DecisionProviderReadiness get readiness {
    if (_disposed) {
      return const DecisionProviderReadiness(
        state: DecisionReadinessState.disposed,
        reasonCode: 'disposed',
        message: 'The decision provider has been disposed',
      );
    }
    if (_apiKey.isEmpty) {
      return const DecisionProviderReadiness(
        state: DecisionReadinessState.unavailable,
        reasonCode: 'missing_api_key',
        message: 'An OpenRouter API key is required for hosted decisions',
      );
    }
    return const DecisionProviderReadiness(state: DecisionReadinessState.ready);
  }

  @override
  Future<DecisionOutcome> decide(final DecisionRequest request) async {
    final correlation = request.correlation;
    if (_disposed) {
      return _failed(
        correlation,
        DecisionFailureCode.disposed,
        'The decision provider has been disposed',
      );
    }
    if (!_seenCancellationIds.add(correlation.cancellationId)) {
      return _failed(
        correlation,
        DecisionFailureCode.invalidRequest,
        'Cancellation IDs are single-use within a provider instance',
      );
    }
    if (_preCancelledIds.remove(correlation.cancellationId)) {
      return _cancelled(correlation, 'Decision cancelled before dispatch');
    }
    final requestValidation = validateDecisionRequest(
      request,
      againstCapabilities: capabilities,
    );
    if (!requestValidation.success) {
      final code = requestValidation.error?.code ?? 'invalid_request';
      final unsupported = <String>{
        'unsupported_question_kind',
        'state_too_large',
        'request_too_large',
        'too_many_questions',
        'too_many_options',
      }.contains(code);
      final failure = DecisionFailure(
        code: unsupported
            ? DecisionFailureCode.unsupported
            : DecisionFailureCode.invalidRequest,
        message: requestValidation.error?.message ?? 'Invalid decision request',
        details: requestValidation.error?.details,
      );
      return unsupported
          ? DecisionUnsupported(correlation: correlation, failure: failure)
          : DecisionFailed(correlation: correlation, failure: failure);
    }
    if (!readiness.isReady) {
      return DecisionUnavailable(
        correlation: correlation,
        failure: const DecisionFailure(
          code: DecisionFailureCode.authentication,
          message: 'An OpenRouter API key is required for hosted decisions',
        ),
      );
    }

    final cancellationSignal = _CancellationSignal();
    _activeSignals[correlation.cancellationId] = cancellationSignal;
    final stopwatch = Stopwatch()..start();
    try {
      final body = jsonEncode(_buildRequestBody(request));
      for (var attempt = 0; attempt <= maxTransientRetries; attempt++) {
        if (_disposed || cancellationSignal.isCancelled) {
          return _cancelled(correlation, 'Decision cancelled before dispatch');
        }
        final remaining = timeout - stopwatch.elapsed;
        if (remaining <= Duration.zero) {
          return _failed(
            correlation,
            DecisionFailureCode.timeout,
            'OpenRouter System One request timed out',
            retryable: true,
          );
        }
        final transportResult =
            await Future.any<_TransportResult>(<Future<_TransportResult>>[
              _send(body, remaining),
              cancellationSignal.whenCancelled.then(
                (_) => const _TransportCancelled(),
              ),
            ]);
        if (transportResult is _TransportCancelled) {
          return _cancelled(correlation, 'Decision cancelled during dispatch');
        }
        if (transportResult case _TransportResponse(:final response)) {
          if (response.statusCode >= 200 && response.statusCode < 300) {
            return _parseSuccess(request, response.body, stopwatch.elapsed);
          }
          final failure = _httpFailure(response);
          if (failure.retryable && attempt < maxTransientRetries) {
            final cancelled = await _waitBeforeRetry(
              correlation,
              stopwatch,
              cancellationSignal,
            );
            if (cancelled != null) return cancelled;
            continue;
          }
          return _outcomeForFailure(correlation, failure);
        }
        if (transportResult is _TransportTimeout) {
          if (attempt < maxTransientRetries) {
            final cancelled = await _waitBeforeRetry(
              correlation,
              stopwatch,
              cancellationSignal,
            );
            if (cancelled != null) return cancelled;
            continue;
          }
          return _failed(
            correlation,
            DecisionFailureCode.timeout,
            'OpenRouter System One request timed out',
            retryable: true,
          );
        }
        if (transportResult is _TransportFailure) {
          if (attempt < maxTransientRetries) {
            final cancelled = await _waitBeforeRetry(
              correlation,
              stopwatch,
              cancellationSignal,
            );
            if (cancelled != null) return cancelled;
            continue;
          }
          return _failed(
            correlation,
            DecisionFailureCode.network,
            'OpenRouter System One network request failed',
            retryable: true,
          );
        }
      }
      return _failed(
        correlation,
        DecisionFailureCode.internal,
        'OpenRouter System One retry loop ended unexpectedly',
      );
    } on Object {
      return _failed(
        correlation,
        DecisionFailureCode.internal,
        'OpenRouter System One request failed unexpectedly',
      );
    } finally {
      stopwatch.stop();
      _activeSignals.remove(correlation.cancellationId);
    }
  }

  Future<_TransportResult> _send(
    final String body,
    final Duration remaining,
  ) async {
    try {
      final response = await _httpClient
          .post(
            endpoint,
            headers: <String, String>{
              'authorization': 'Bearer $_apiKey',
              'content-type': 'application/json',
              'accept': 'application/json',
            },
            body: body,
          )
          .timeout(remaining);
      return _TransportResponse(response);
    } on TimeoutException {
      return const _TransportTimeout();
    } on Object {
      return const _TransportFailure();
    }
  }

  Map<String, Object?> _buildRequestBody(final DecisionRequest request) =>
      <String, Object?>{
        'model': model,
        'state': request.state,
        'questions': <String, Object?>{
          for (final question in request.questions)
            question.id.value: <String, Object?>{
              'type': 'choice',
              'instructions': question.instructions,
              'criteria': <String, String>{
                for (final option in question.options)
                  option.id.value: option.description,
              },
            },
        },
      };

  DecisionOutcome _parseSuccess(
    final DecisionRequest request,
    final String body,
    final Duration elapsed,
  ) {
    final Map<String, dynamic> decoded;
    try {
      final value = jsonDecode(body);
      if (value is! Map) {
        return _malformed(request, 'System One returned a non-object response');
      }
      decoded = value.cast<String, dynamic>();
    } on FormatException {
      return _malformed(request, 'System One returned malformed JSON');
    }

    try {
      final resolvedModel = decoded['model'];
      final rawAnswers = decoded['answers'];
      if (resolvedModel is! String || resolvedModel.trim().isEmpty) {
        return _malformed(request, 'System One response omitted its model');
      }
      if (rawAnswers is! Map) {
        return _malformed(request, 'System One response omitted answers');
      }
      final answersMap = rawAnswers.cast<String, dynamic>();
      final expectedIds = request.questions
          .map((final question) => question.id.value)
          .toSet();
      if (answersMap.keys.toSet().difference(expectedIds).isNotEmpty) {
        return _malformed(
          request,
          'System One response contained an unknown question answer',
        );
      }
      final answers = <DecisionAnswer>[];
      for (final question in request.questions) {
        final rawAnswer = answersMap[question.id.value];
        if (rawAnswer is! Map) {
          return _malformed(
            request,
            'System One response omitted an expected answer',
          );
        }
        final answer = rawAnswer.cast<String, dynamic>();
        if (answer['type'] != 'choice') {
          return _malformed(
            request,
            'System One returned an unsupported answer type',
          );
        }
        final selected = answer['choice'];
        final rawProbabilities = answer['probabilities'];
        final rawConfidence = answer['confidence'];
        if (selected is! String ||
            rawProbabilities is! Map ||
            rawConfidence is! num) {
          return _malformed(
            request,
            'System One returned an incomplete choice answer',
          );
        }
        final probabilities = <DecisionOptionId, double>{};
        for (final entry in rawProbabilities.entries) {
          if (entry.key is! String || entry.value is! num) {
            return _malformed(
              request,
              'System One returned malformed choice probabilities',
            );
          }
          probabilities[DecisionOptionId(entry.key as String)] =
              (entry.value as num).toDouble();
        }
        final selectedId = DecisionOptionId(selected);
        answers.add(
          DecisionAnswer(
            questionId: question.id,
            questionVersion: question.version,
            candidateSetId: question.candidateSetId,
            selectedOptionId: selectedId,
            disposition: selectedId == question.abstainOptionId
                ? DecisionAnswerDisposition.abstained
                : DecisionAnswerDisposition.selected,
            probabilities: probabilities,
            confidence: rawConfidence.toDouble(),
          ),
        );
      }

      final metadata = DecisionResponseMetadata(
        provider: decoded['provider'] as String?,
        providerRequestId: decoded['id'] as String?,
        requestedModel: model,
        resolvedModel: resolvedModel,
        usage: _parseUsage(decoded['usage']),
        timing: DecisionTiming(elapsed: elapsed),
        additional: <String, Object?>{
          for (final entry in decoded.entries)
            if (!const <String>{
              'id',
              'model',
              'provider',
              'answers',
              'usage',
            }.contains(entry.key))
              entry.key: entry.value,
        },
      );
      final completion = DecisionCompleted(
        correlation: request.correlation,
        answers: answers,
        metadata: metadata,
      );
      final validation = validateDecisionCompletion(
        request: request,
        completion: completion,
        requireCompleteProbabilityDistribution: true,
      );
      if (!validation.success) {
        return _malformed(
          request,
          validation.error?.message ?? 'System One response was invalid',
          details: validation.error?.code,
        );
      }
      return completion;
    } on Object {
      return _malformed(
        request,
        'System One response fields had invalid types',
      );
    }
  }

  DecisionUsage? _parseUsage(final Object? rawUsage) {
    if (rawUsage == null) return null;
    if (rawUsage is! Map) {
      throw const FormatException('usage must be an object');
    }
    final usage = rawUsage.cast<String, dynamic>();
    final inputTokens = usage['input_tokens'];
    final outputTokens = usage['output_tokens'];
    final cost = usage['cost'];
    if (inputTokens != null && (inputTokens is! int || inputTokens < 0) ||
        outputTokens != null && (outputTokens is! int || outputTokens < 0)) {
      throw const FormatException(
        'token usage must contain non-negative integers',
      );
    }
    if (cost != null && cost is! num) {
      throw const FormatException('cost must be finite and non-negative');
    }
    final normalizedCost = (cost as num?)?.toDouble();
    if (normalizedCost != null &&
        (!normalizedCost.isFinite || normalizedCost < 0)) {
      throw const FormatException('cost must be finite and non-negative');
    }
    return DecisionUsage(
      provenance: DecisionUsageProvenance.providerReported,
      inputTokens: inputTokens as int?,
      outputTokens: outputTokens as int?,
      cost: normalizedCost,
      currency: normalizedCost == null ? null : 'USD',
    );
  }

  DecisionFailure _httpFailure(final http.Response response) {
    final status = response.statusCode;
    final message = 'OpenRouter System One request failed with HTTP $status';
    if (status == 401 || status == 403) {
      return DecisionFailure(
        code: DecisionFailureCode.authentication,
        message: message,
      );
    }
    if (status == 402) {
      return DecisionFailure(
        code: DecisionFailureCode.quotaExceeded,
        message: message,
      );
    }
    if (status == 429) {
      return DecisionFailure(
        code: DecisionFailureCode.rateLimited,
        message: message,
        retryable: true,
      );
    }
    if (status == 408 || status >= 500) {
      return DecisionFailure(
        code: status == 408
            ? DecisionFailureCode.timeout
            : DecisionFailureCode.unavailable,
        message: message,
        retryable: true,
      );
    }
    return DecisionFailure(
      code: DecisionFailureCode.providerRejected,
      message: message,
    );
  }

  Future<DecisionCancelled?> _waitBeforeRetry(
    final DecisionCorrelation correlation,
    final Stopwatch stopwatch,
    final _CancellationSignal cancellationSignal,
  ) async {
    if (retryDelay > Duration.zero) {
      final remaining = timeout - stopwatch.elapsed;
      if (remaining > Duration.zero) {
        final cancelled = await Future.any<bool>(<Future<bool>>[
          Future<bool>.delayed(
            retryDelay < remaining ? retryDelay : remaining,
            () => false,
          ),
          cancellationSignal.whenCancelled.then((_) => true),
        ]);
        if (cancelled) {
          return _cancelled(correlation, 'Decision cancelled before retry');
        }
      }
    }
    return cancellationSignal.isCancelled || _disposed
        ? _cancelled(correlation, 'Decision cancelled before retry')
        : null;
  }

  DecisionOutcome _outcomeForFailure(
    final DecisionCorrelation correlation,
    final DecisionFailure failure,
  ) => switch (failure.code) {
    DecisionFailureCode.authentication ||
    DecisionFailureCode.quotaExceeded ||
    DecisionFailureCode.rateLimited ||
    DecisionFailureCode.unavailable => DecisionUnavailable(
      correlation: correlation,
      failure: failure,
    ),
    DecisionFailureCode.unsupported => DecisionUnsupported(
      correlation: correlation,
      failure: failure,
    ),
    DecisionFailureCode.cancelled => DecisionCancelled(
      correlation: correlation,
      failure: failure,
    ),
    _ => DecisionFailed(correlation: correlation, failure: failure),
  };

  DecisionFailed _failed(
    final DecisionCorrelation correlation,
    final DecisionFailureCode code,
    final String message, {
    final bool retryable = false,
    final Object? details,
  }) => DecisionFailed(
    correlation: correlation,
    failure: DecisionFailure(
      code: code,
      message: message,
      retryable: retryable,
      details: details,
    ),
  );

  DecisionFailed _malformed(
    final DecisionRequest request,
    final String message, {
    final Object? details,
  }) => _failed(
    request.correlation,
    DecisionFailureCode.malformedResponse,
    message,
    details: details,
  );

  DecisionCancelled _cancelled(
    final DecisionCorrelation correlation,
    final String message,
  ) => DecisionCancelled(
    correlation: correlation,
    failure: DecisionFailure(
      code: DecisionFailureCode.cancelled,
      message: message,
    ),
  );

  @override
  Future<void> cancel(final DecisionCancellationId cancellationId) async {
    final signal = _activeSignals[cancellationId];
    if (signal != null) {
      signal.cancel();
      return;
    }
    if (!_seenCancellationIds.contains(cancellationId)) {
      _preCancelledIds.add(cancellationId);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final signal in _activeSignals.values.toList(growable: false)) {
      signal.cancel();
    }
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }
}

final class _CancellationSignal {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

sealed class _TransportResult {
  const _TransportResult();
}

final class _TransportResponse extends _TransportResult {
  const _TransportResponse(this.response);

  final http.Response response;
}

final class _TransportTimeout extends _TransportResult {
  const _TransportTimeout();
}

final class _TransportFailure extends _TransportResult {
  const _TransportFailure();
}

final class _TransportCancelled extends _TransportResult {
  const _TransportCancelled();
}
