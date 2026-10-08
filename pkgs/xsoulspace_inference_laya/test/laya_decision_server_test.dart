import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_laya/xsoulspace_inference_laya.dart';
import 'package:xsoulspace_inference_openrouter/laya_server.dart';

void main() {
  group('LayaDecisionServer', () {
    test('answers a real loopback System One request end to end', () async {
      final engine = ScriptedLayaDecisionEngine(<LayaDecisionPin>[
        const LayaDecisionPin('next_operation', 'Apply the grounded'),
      ]);
      final server = LayaDecisionServer(engine: engine);
      await server.start();
      final provider = LayaServerDecisionProvider(
        endpoint: server.url.replace(path: '/v1/systemone'),
      );

      final outcome = await provider.decide(_request());

      expect(outcome, isA<DecisionCompleted>());
      final completed = outcome as DecisionCompleted;
      expect(
        completed.answers.single.selectedOptionId,
        const DecisionOptionId('apply_edit'),
      );
      expect(
        completed.answers.single.disposition,
        DecisionAnswerDisposition.selected,
      );
      expect(completed.metadata.resolvedModel, 'laya');
      expect(completed.metadata.usage?.inputTokens, greaterThan(0));
      expect(engine.requests, hasLength(1));
      expect(engine.requests.single.state, _state);
      await provider.dispose();
      await server.stop();
    });

    test(
      'health endpoint answers open, systemone honors bearer auth',
      () async {
        final server = LayaDecisionServer(
          engine: ScriptedLayaDecisionEngine(const <LayaDecisionPin>[]),
          apiKey: 'secret',
        );
        await server.start();
        final client = http.Client();

        final health = await client.get(server.url.replace(path: '/health'));
        expect(health.statusCode, 200);
        expect(jsonDecode(health.body)['status'], 'ok');

        final denied = await client.post(
          server.url.replace(path: '/v1/systemone'),
          body: jsonEncode(_requestBody()),
          headers: {'content-type': 'application/json'},
        );
        expect(denied.statusCode, 401);

        final authorized = await client.post(
          server.url.replace(path: '/v1/systemone'),
          body: jsonEncode(_requestBody()),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer secret',
          },
        );
        expect(authorized.statusCode, 200);
        expect(jsonDecode(authorized.body)['answers'], isNotEmpty);
        client.close();
        await server.stop();
      },
    );

    test('unpinned questions fall back to the first criterion; abstention '
        'survives the wire', () async {
      final engine = ScriptedLayaDecisionEngine(<LayaDecisionPin>[
        const LayaDecisionPin(
          'next_operation',
          'Gather more evidence before proposing',
        ),
      ]);
      final server = LayaDecisionServer(engine: engine);
      await server.start();
      final provider = LayaServerDecisionProvider(
        endpoint: server.url.replace(path: '/v1/systemone'),
      );

      final outcome = await provider.decide(_request());

      expect(outcome, isA<DecisionCompleted>());
      expect(
        (outcome as DecisionCompleted).answers.single.disposition,
        DecisionAnswerDisposition.abstained,
        reason: 'the fallback pin selects the abstain option by description',
      );
      await provider.dispose();
      await server.stop();
    });

    test(
      'calibrated engine probabilities and both confidences survive wire',
      () async {
        final server = LayaDecisionServer(engine: const _CalibratedEngine());
        await server.start();
        addTearDown(server.stop);
        final response = await http.post(
          server.url.replace(path: '/v1/systemone'),
          body: jsonEncode(_requestBody()),
          headers: {'content-type': 'application/json'},
        );
        final answer = jsonDecode(response.body)['answers']['next_operation'];
        expect(answer['probabilities'], {
          'apply_edit': .63,
          'insufficient_evidence': .37,
        });
        expect(answer['confidence'], .049);
        expect(answer['answer_confidence'], .63);
        expect(answer['act_probability'], .42);
        final provider = LayaServerDecisionProvider(
          endpoint: server.url.replace(path: '/v1/systemone'),
        );
        addTearDown(provider.dispose);
        final outcome = await provider.decide(_request()) as DecisionCompleted;
        expect(outcome.answers.single.confidence, .049);
      },
    );

    test(
      'invalid calibrated distribution refuses with named failure',
      () async {
        final server = LayaDecisionServer(
          engine: const _CalibratedEngine(invalid: true),
        );
        await server.start();
        addTearDown(server.stop);
        final response = await http.post(
          server.url.replace(path: '/v1/systemone'),
          body: jsonEncode(_requestBody()),
          headers: {'content-type': 'application/json'},
        );
        expect(response.statusCode, 422);
        expect(
          jsonDecode(response.body)['error']['code'],
          'laya_invalid_distribution',
        );
      },
    );

    test(
      'malformed bodies map to typed client failures, not crashes',
      () async {
        final server = LayaDecisionServer(
          engine: ScriptedLayaDecisionEngine(const <LayaDecisionPin>[]),
        );
        await server.start();
        final provider = LayaServerDecisionProvider(
          endpoint: server.url.replace(path: '/v1/systemone'),
        );
        final client = http.Client();

        final outcome = await provider.decide(_request());
        expect(outcome, isA<DecisionCompleted>());

        final badJson = await client.post(
          server.url.replace(path: '/v1/systemone'),
          body: 'not-json{',
          headers: {'content-type': 'application/json'},
        );
        expect(badJson.statusCode, 400);

        final missingState = await client.post(
          server.url.replace(path: '/v1/systemone'),
          body: jsonEncode(<String, Object?>{'model': 'laya'}),
          headers: {'content-type': 'application/json'},
        );
        expect(missingState.statusCode, 422);

        final unknown = await client.get(server.url.replace(path: '/nope'));
        expect(unknown.statusCode, 404);
        client.close();
        await provider.dispose();
        await server.stop();
      },
    );
  });
}

const String _state = 'Verification failed after the semantic edit.';

DecisionRequest _request() => DecisionRequest(
  correlation: DecisionCorrelation(
    requestId: const DecisionRequestId('req-a'),
    cutId: const DecisionCutId('cut-a'),
    stateRevision: const DecisionStateRevision('rev-a'),
    cancellationId: const DecisionCancellationId('cancel-a'),
  ),
  state: _state,
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

Map<String, Object?> _requestBody() => <String, Object?>{
  'model': 'laya',
  'state': _state,
  'questions': <String, Object?>{
    'next_operation': <String, Object?>{
      'type': 'choice',
      'instructions': 'Which grounded semantic operation?',
      'criteria': <String, String>{
        'apply_edit': 'Apply the grounded semantic edit',
        'insufficient_evidence': 'Gather more evidence before proposing',
      },
    },
  },
};

final class _CalibratedEngine implements CalibratedLayaDecisionEngine {
  const _CalibratedEngine({this.invalid = false});
  final bool invalid;
  @override
  Map<String, String> answer(LayaDecisionQuery query) => {
    'next_operation': 'apply_edit',
  };
  @override
  Map<String, LayaDecisionResult> answerDecisions(LayaDecisionQuery query) => {
    'next_operation': LayaDecisionResult(
      optionId: 'apply_edit',
      probabilities: {
        'apply_edit': invalid ? double.nan : .63,
        'insufficient_evidence': .37,
      },
      confidence: .049,
      answerConfidence: .63,
      actProbability: .42,
    ),
  };
}
