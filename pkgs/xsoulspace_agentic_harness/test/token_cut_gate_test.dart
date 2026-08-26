// ignore_for_file: lines_longer_than_80_chars

/// M2 gate: on the refactor class, anchor-patch ops must cost ≥30% fewer
/// generated characters than whole-file writes — measured through the real
/// attribution plumbing, LLM-free.
import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

const _fileBody = '''
class PriceCalculator {
  double total(List<double> items, {double tax = 0.19}) {
    var sum = 0.0;
    for (final i in items) {
      sum += i;
    }
    return sum * (1 + tax);
  }

  double discounted(double value, double pct) {
    if (pct < 0 || pct > 1) throw ArgumentError.value(pct);
    return value * (1 - pct);
  }
}
''';

void main() {
  late Directory jail;

  setUp(() async {
    jail = await Directory.systemTemp.createTemp('token-cut-test');
    final pf = File('${jail.path}/lib/price.dart')
      ..createSync(recursive: true);
    pf.writeAsStringSync(_fileBody);
  });

  tearDown(() => jail.delete(recursive: true));

  test('anchor patch beats whole-file write by >=30% generated chars',
      () async {
    const replacement = 'return (sum + fee) * (1 + tax);';

    final baselineLedger = AttributionLedger();
    await _record(baselineLedger, genChars: _fileBody.length);

    final opLedger = AttributionLedger();
    const anchor = '    return sum * (1 + tax);';
    final stage = AnchorStage('lib/price.dart', anchor)
      ..fileMissing('file_missing')
      ..notUnique('anchor_not_unique')
      ..thenReplace(replacement);
    final results =
        TransformFlow([stage]).evaluate(TransformContext(jail.path));
    final report = applyOps(jail.path, results);
    expect(report.applied, 1);
    await _record(opLedger, genChars: replacement.length);

    final base = baselineLedger.summarize()['generatedChars'] as int;
    final ops = opLedger.summarize()['generatedChars'] as int;
    expect(ops, replacement.length);
    final cut = 1 - ops / base;
    expect(cut, greaterThanOrEqualTo(0.30),
        reason: 'patch($ops) vs whole-file($base)');
    expect(File('${jail.path}/lib/price.dart').readAsStringSync(),
        contains(replacement));
  });
}

Future<void> _record(
  AttributionLedger ledger, {
  required int genChars,
}) async {
  final world = World()..addPlugin(AgentPlugin());
  world.upsertResource(ModelRouterResource(ModelRouter()));
  final actor = world.spawnComponents([
    Actor(agentId: AgentId.create()),
    ActorModel(modelId: ModelId.create()),
  ]);
  world.flush();
  final attributed = AttributedHandler(
    ScriptedGenerationHandler([ScriptedTurn(text: 'x' * genChars)]),
    ledger,
  );
  await attributed.generate(
    world,
    ActorGenerateRequest(
      actorEntity: actor,
      agentId: AgentId('a'),
      modelId: ModelId('m'),
      prompt: 'p',
      systemPrompt: 's',
      contextFragments: const ['tool:read ok', 'absence:no tests'],
      schema: SchemaBundle.empty,
      toolRegistry: null,
      task: InferenceTask.text,
      taskId: TaskId('t1'),
    ),
  );
}
