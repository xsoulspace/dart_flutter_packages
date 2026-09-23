import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// API compatibility fixtures for D0.
///
/// Prove that the optional decision capability is a separate surface:
/// existing [InferenceClient] implementations compile and behave unchanged,
/// existing task enums gain no decision values, and a decision provider can
/// be implemented without touching the text/speech flows.
void main() {
  group('inference client API compatibility', () {
    test('existing client surface compiles without decision methods', () {
      final client = _TextOnlyClient();

      expect(client.id, 'fake_text_client');
      expect(client.isAvailable, isTrue);
      expect(client.supportedTasks, <InferenceTask>{InferenceTask.text});
    });

    test('existing text flow behavior is unchanged', () async {
      final client = _TextOnlyClient();
      final request = InferenceRequest(prompt: 'Summarize the state.');

      final validation = validateInferenceRequest(request);
      expect(validation.success, isTrue);

      final result = await client.infer(request);
      expect(result.success, isTrue);
      expect(result.data?.rawOutput, 'ok');
      expect(result.data?.task, InferenceTask.text);
    });

    test('existing task enum gains no decision values', () {
      expect(
        InferenceTask.values.map((final task) => task.name),
        containsAll(<String>[
          'text',
          'implicitlyStructuredText',
          'nativelyStructuredText',
          'speechToText',
          'textToSpeech',
        ]),
      );
      expect(
        InferenceTask.values
            .where((final task) => task.name.toLowerCase().contains('decision'))
            .length,
        0,
      );
    });

    test('decision provider is implemented without the client interface', () {
      final provider = _ChoiceOnlyProvider();

      expect(provider.id, 'fake_choice_provider');
      expect(
        provider.capabilities.supportedQuestionKinds,
        <DecisionQuestionKind>{DecisionQuestionKind.finiteChoice},
      );
      expect(provider.readiness.isReady, isTrue);

      // The two optional surfaces stay disjoint: a text client is not a
      // decision provider and vice versa.
      expect(_TextOnlyClient(), isNot(isA<DecisionProvider>()));
      expect(provider, isNot(isA<InferenceClient>()));
    });

    test('decision provider cancels only the scoped cancellation id', () async {
      final provider = _ChoiceOnlyProvider();
      const staleCancellation = DecisionCancellationId('cancel-stale');

      await provider.cancel(staleCancellation);
      expect(provider.cancelledIds, isEmpty);

      const activeCancellation = DecisionCancellationId('cancel-5');
      await provider.cancel(activeCancellation);
      expect(provider.cancelledIds, <DecisionCancellationId>[
        activeCancellation,
      ]);

      await provider.dispose();
      expect(provider.readiness.state, DecisionReadinessState.disposed);
    });
  });
}

final class _TextOnlyClient implements InferenceClient {
  @override
  String get id => 'fake_text_client';

  @override
  bool get isAvailable => true;

  @override
  Set<InferenceTask> get supportedTasks => const <InferenceTask>{
    InferenceTask.text,
  };

  @override
  Future<bool> refreshAvailability() async => true;

  @override
  Future<void> load() async {}

  @override
  void resetAvailabilityCache() {}

  @override
  Future<InferenceResult<InferenceResponse>> infer(
    final InferenceRequest request, {
    final ToolRegistry? toolRegistry,
  }) async => InferenceResult<InferenceResponse>.ok(
    const InferenceResponse(rawOutput: 'ok', task: InferenceTask.text),
  );
}

final class _ChoiceOnlyProvider implements DecisionProvider {
  final cancelledIds = <DecisionCancellationId>[];
  DecisionReadinessState _state = DecisionReadinessState.ready;

  @override
  String get id => 'fake_choice_provider';

  @override
  DecisionProviderCapabilities get capabilities => DecisionProviderCapabilities(
    supportedQuestionKinds: const <DecisionQuestionKind>{
      DecisionQuestionKind.finiteChoice,
    },
    bounds: const DecisionProviderBounds(
      maxStateUtf8Bytes: 64 * 1024,
      maxRequestUtf8Bytes: 256 * 1024,
      maxQuestionsPerRequest: 8,
      maxOptionsPerQuestion: 16,
    ),
    executionLocation: DecisionExecutionLocation.hosted,
    networkRequirement: DecisionNetworkRequirement.required,
    supportsCancellation: true,
  );

  @override
  DecisionProviderReadiness get readiness =>
      DecisionProviderReadiness(state: _state);

  @override
  Future<DecisionOutcome> decide(final DecisionRequest request) async =>
      DecisionUnavailable(
        correlation: request.correlation,
        failure: const DecisionFailure(
          code: DecisionFailureCode.unavailable,
          message: 'Fake provider performs no inference.',
        ),
      );

  @override
  Future<void> cancel(final DecisionCancellationId cancellationId) async {
    if (cancellationId.value == 'cancel-5') {
      cancelledIds.add(cancellationId);
    }
  }

  @override
  Future<void> dispose() async {
    _state = DecisionReadinessState.disposed;
  }
}
