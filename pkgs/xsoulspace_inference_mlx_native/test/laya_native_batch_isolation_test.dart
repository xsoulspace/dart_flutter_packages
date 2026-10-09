import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart';

void main() {
  test(
    'native mixed question batch agrees with each independent request',
    () async {
      if (Platform.environment['LAYA_ASYNC_NATIVE_PROBE'] != '1') {
        return markTestSkipped('opt-in native independence regression');
      }
      final fixture =
          (jsonDecode(
                        File(
                          'test/fixtures/laya_golden_fp16.json',
                        ).readAsStringSync(),
                      )
                      as List)
                  .first
              as Map;
      final definitions = fixture['questions'] as Map;
      final questions = <String, LayaTypedQuestion>{};
      for (final entry in definitions.entries) {
        final definition = entry.value as Map;
        final instructions = definition['instructions'] as String;
        switch (definition['type']) {
          case 'choice':
            questions['${entry.key}'] = LayaTypedQuestion.choice(
              instructions,
              (definition['criteria'] as Map).cast<String, String>(),
            );
          case 'score':
            questions['${entry.key}'] = LayaTypedQuestion.score(
              instructions,
              (definition['criteria'] as List).cast<String>(),
            );
          case 'noul':
            questions['${entry.key}'] = LayaTypedQuestion.noul(instructions);
        }
      }
      final engine = await NativeLayaDecisionEngine.load();
      addTearDown(engine.dispose);
      final state = renderLayaJson(fixture['state']);
      final batch = engine.decideTyped(state: state, questions: questions);
      for (final entry in questions.entries) {
        final independent = engine.decideTyped(
          state: state,
          questions: {entry.key: entry.value},
        )[entry.key]!;
        for (final probability in independent.probabilities.entries) {
          expect(
            batch[entry.key]!.probabilities[probability.key],
            closeTo(probability.value, .005),
            reason:
                '${entry.key}/${probability.key}: another question must not change this actor evidence decision',
          );
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
