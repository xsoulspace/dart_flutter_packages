// ignore_for_file: lines_longer_than_80_chars, avoid_print

/// T1 dogfooding driver — an OpenRouter model as the actor in the REAL
/// harness MEANING pipeline (the architecture-correct surface):
///
///   act_with_project (typed meaning moves, closed enum) +
///   intent_define (define w/ specs — always self-executing) +
///   intent_call (in-process verification)
///
/// The model NEVER writes code tokens and NEVER touches raw files — that was
/// the architectural violation of the first draft (fs_tools write-surface),
/// caught in dogfooding. Host materialization (meaning tree → program.dart)
/// and host-side chain validation are pure programs (Agent = G ∘ F).
///
/// ```sh
/// OPENROUTER_API_KEY=... dart run bin/dogfood_agent.dart \
///   [--model deepseek/deepseek-v4-flash-0731] [--runs 3]
/// ```
/// Model policy: poolside tiers or `OR_MODEL` env override — never a
/// non-partnering frontier model without explicit instruction.
library;

import 'dart:io';

import 'package:xsoulspace_agentic_harness/benchmark_api.dart'
    show defaultGoalFlow, wireIntentGradedGoal, IntentExpectation;
import 'package:xsoulspace_agentic_harness/src/handler.dart'
    show DefaultGenerationHandler;
import 'package:xsoulspace_agentic_harness/src/meaning/meaning_program.dart'
    show materializeMeaningProgram, validateMeaningProgram;
import 'package:xsoulspace_agentic_harness/src/meaning/intents.dart'
    show intentCallTool, intentDefineTool, listIntents;
import 'package:xsoulspace_agentic_harness/src/tooling/act_with_project.dart'
    show actWithProjectTool;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_inference_openrouter/xsoulspace_inference_openrouter.dart';

/// B6: teaching lives here + tool descriptions only (~160 tokens).
const _systemPrompt =
    'You build a bookmark manager by picking tiny typed moves. You never '
    'write code. Tools: act_with_project, intent_define, intent_call.\n'
    'Flow: 1) intent_define action define — REQUIRES specs (op rows), ONE '
    'move per intent; it wires the executor itself. Op vocabulary: load_arg, '
    'load_state, push_state, literal, list_len, starts_with, eq, not, '
    'jump_if_false, return. Spec rows: label + props a/b; jump targets use '
    '"#row"; each row continues to the next unless "next" says otherwise. '
    '2) act_with_project action materialize. 3) intent_call save_url then '
    'intent_call list_saved to verify. If a call fails, read the error: it '
    'names the op id or the missing executor — fix with define (specs) and '
    're-materialize.';

const _taskPrompt =
    'Build a bookmark manager: save_url saves a URL only if it starts with '
    'http; list_saved counts saved bookmarks. Define both intents (with '
    'specs), materialize, verify with intent_call.';

Future<void> main(List<String> args) async {
  var model =
      Platform.environment['OR_MODEL'] ?? 'deepseek/deepseek-v4-flash-0731';
  var runs = 1;
  var jailArg = '.dogfood_jail';
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--model':
        model = args[++i];
      case '--runs':
        runs = int.parse(args[++i]);
      case '--jail':
        jailArg = args[++i];
    }
  }
  final apiKey =
      Platform.environment['OPENROUTER_API_KEY'] ??
      Platform.environment['OR_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln('OPENROUTER_API_KEY not set.');
    exit(2);
  }

  final passed = <bool>[];
  for (var run = 1; run <= runs; run++) {
    final jail = Directory(run == 1 ? jailArg : '$jailArg$run')
      ..createSync(recursive: true);

    final world = World()..addPlugin(AgentPlugin());
    final recorder = FlightRecorder();
    world
      ..upsertResource(ToolRegistryResource())
      ..upsertResource(recorder)
      ..upsertResource(DecisionFlowResource(defaultGoalFlow()))
      ..upsertResource(AgencyPolicy(maxConcurrent: 1, maxToolRounds: 12))
      ..flush();

    // The MEANING surface — no fs write tool exists on the model surface.
    final registry = ToolRegistry();
    for (final t in [
      actWithProjectTool(
        world: world,
        materialize: () async {
          final src = materializeMeaningProgram(world);
          File('${jail.path}/program.dart').writeAsStringSync(src);
          return {
            'path': 'program.dart',
            'materialized': true,
            'intents': [for (final i in listIntents(world)) i['name']],
            'problems': validateMeaningProgram(world),
          };
        },
      ),
      intentDefineTool(world),
      intentCallTool(world),
    ]) {
      registry.register(t);
    }
    world.getResource<ToolRegistryResource>().register('default', registry);

    final router = ModelRouter(
      inferenceClientsBuilders: {
        OpenRouterModelNames.openRouter: () =>
            OpenRouterInferenceClient(apiKey: apiKey, defaultModel: model),
      },
    );
    final mid = ModelId('dogfood');
    router.models[mid] = Model(id: mid, name: OpenRouterModelNames.openRouter);
    world.upsertResource(ModelRouterResource(router));
    world.getResource<GenerationHandlerResource>().registerDefault(
      DefaultGenerationHandler(router: router),
    );

    final scene = world.spawnComponents([const Scene(), SceneFrame()]);
    final actor = world.spawnComponents([
      Actor(agentId: AgentId.create()),
      ActorModel(modelId: mid),
      ActorSystemPrompt(text: _systemPrompt),
      ActorThreads(threads: []),
      ActorTools(registryName: 'default'),
      PresentInScene(sceneEntity: scene),
      OpenDecision(prompt: _taskPrompt),
    ]);
    final thread = spawnThread(world, actor, scene);
    world.upsertComponent(actor, ActorThreads(threads: [thread]));
    world.flush();

    // Intent-graded verifier INSIDE the loop (bounded by J1.5 budgets).
    wireIntentGradedGoal(
      world,
      sequence: const [
        IntentExpectation('save_url', args: {'url': 'https://example.dev'}),
        IntentExpectation('list_saved'),
      ],
    );

    final sigint = ProcessSignal.sigint.watch().listen((_) {
      stderr.writeln('\nSIGINT — recorder dump:\n${recorder.dump()}');
      exit(130);
    });
    await HarnessLoop(world: world).runUntilIdle();
    world.flush();
    sigint.cancel();

    // Final gate (once): replay the expectations mechanically.
    var gateOk = true;
    final gateLog = <String>[];
    for (final check in const [
      {
        'intent': 'save_url',
        'args': {'url': 'https://gate.dev'},
      },
      {'intent': 'list_saved'},
    ]) {
      final out = await const _GateCaller().call(world, check);
      gateOk = gateOk && (out['ok'] == true);
      gateLog.add('${check['intent']} → $out');
    }
    passed.add(gateOk);
    print(
      '--- run $run/$runs — model: $model — verdict: '
      '${gateOk ? 'PASS' : 'FAIL'}',
    );
    print('gate: ${gateLog.join(' | ')}');
    print(sampleHarness(world).toText());
    print('recorder:\n${recorder.dump()}');
  }
  print(
    'summary — backend: open_router:$model n: $runs '
    'passed: ${passed.where((p) => p).length} pass@$runs: '
    '${passed.where((p) => p).length}/$runs',
  );
  exit(passed.every((p) => p) ? 0 : 1);
}

/// Minimal mechanical re-player for the final gate.
class _GateCaller {
  const _GateCaller();

  Future<Map<String, dynamic>> call(
    World world,
    Map<String, Object?> check,
  ) async {
    final call = registry(world).get(const ToolName('intent_call'))!;
    final args = <String>[
      'intent=${check['intent']}',
      for (final e
          in (check['args'] as Map?)?.entries ?? const Iterable.empty())
        '${e.key}=${e.value}',
    ];
    final raw = await call.execute({'intent': check['intent'], 'args': args});
    return raw is Map
        ? (raw as Map).cast<String, dynamic>()
        : (raw as String).contains('"ok": true')
        ? {'ok': true}
        : {'ok': false, 'raw': raw};
  }
}

ToolRegistry registry(World world) =>
    world.getResource<ToolRegistryResource>().get('default')!;
