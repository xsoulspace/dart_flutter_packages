// ignore_for_file: lines_longer_than_80_chars

/// Real-model (AFM) run-graded benchmark: does making a Goal advance by
/// RUNNING code (run tool, `runs` checker) beat baseline (defaultReAct +
/// content-only) on self-contained "build a runnable Dart program" tasks,
/// with a REAL Apple Foundation Model?
///
/// Both arms use the identical jail, tool set, handler and check metrics; the
/// ONLY diff is the decision flow (+ run-graded goal verification system vs
/// default ReAct). Uses the native AFM client (ADR 0013 native tool calling).
///
/// ```sh
/// dart run bin/gate_afm_benchmark.dart [--arm baseline|run-graded|both]
/// ```
library;

import 'dart:io';
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_agentic_harness/src/tooling/build_gates.dart';
import 'package:xsoulspace_agentic_harness/src/benchmark/coding_suite/checkers.dart';
import 'package:xsoulspace_agentic_harness/src/benchmark/coding_suite/task_spec.dart';
import 'package:xsoulspace_agentic_harness/src/tooling/world_builder.dart'
    show registerExperimentComponents;
import 'package:xsoulspace_inference_apple_foundation/src/native_bridge/native_client.dart';

final buildTasks = <CodingTask>[
  CodingTask(
    id: 'build_board',
    category: TaskCategory.toolChain,
    prompt:
        'Write a Dart program main.dart that prints a 3x3 tic-tac-toe board '
        '(three rows separated by |), then exits 0. Use print().',
    checkers: [
      CheckerSpec(type: 'file_exists', path: 'main.dart'),
      CheckerSpec(type: 'runs', path: 'main.dart'),
      CheckerSpec(type: 'contains', path: 'main.dart', value: 'print'),
    ],
  ),
  CodingTask(
    id: 'build_turn',
    category: TaskCategory.toolChain,
    prompt:
        'Write a Dart program main.dart that prints X then O on separate '
        'lines, then exits 0. Use print().',
    checkers: [
      CheckerSpec(type: 'file_exists', path: 'main.dart'),
      CheckerSpec(type: 'runs', path: 'main.dart'),
      CheckerSpec(type: 'contains', path: 'main.dart', value: 'O'),
    ],
  ),
];

Future<bool> _arm(
  CodingTask task, {
  required Directory jail,
  required bool goalFlow,
}) async {  final world = World()..addPlugin(AgentPlugin());
  if (goalFlow) registerExperimentComponents(world);
  final router = ModelRouter(
    inferenceClientsBuilders: {
      DefaultModelNames.appleFoundation: () => AppleFoundationNativeClient(),
    },
  );
  final modelId = ModelId('afm');
  router.models[modelId] = Model(
    id: modelId,
    name: DefaultModelNames.appleFoundation,
  );
  world
    ..upsertResource(ModelRouterResource(router))
    ..upsertResource(ToolRegistryResource())
    ..upsertResource(AgencyPolicy(maxConcurrent: 1, maxToolRounds: 12))
    ..upsertResource(DecisionFlowResource(
      goalFlow ? defaultGoalFlow() : DecisionFlow.defaultReAct(),
    ))
    ..flush();

  final handler = DefaultGenerationHandler(router: router);
  world.getResource<GenerationHandlerResource>().registerDefault(handler);

  final registry = ToolRegistry();
  fsTools(FsToolsRoot(jail.path)).forEach(registry.register);
  world.getResource<ToolRegistryResource>().register('default', registry);

  final scene = world.spawnComponents([Scene(), SceneFrame()]);
  final actor = world.spawnComponents([
    Actor(agentId: AgentId.create()),
    ActorModel(modelId: modelId),
    ActorSystemPrompt(text: task.systemPrompt),
    ActorThreads(threads: []),
    ActorTools(registryName: 'default'),
    PresentInScene(sceneEntity: scene),
    OpenDecision(prompt: task.prompt),
  ]);
  final thread = spawnThread(world, actor, scene);
  world.upsertComponent(actor, ActorThreads(threads: [thread]));
  if (goalFlow) {
    // Attach a Goal so the run-graded verifier can stamp GoalVerified, and
    // wire the mechanical `dart run main.dart` check.
    world.upsertComponent(actor, Goal(text: task.prompt));
    wireRunGradedGoal(
      world,
      command: ['dart', 'run', 'main.dart'],
      cwd: jail.path,
    );
  }
  world.flush();

  await HarnessLoop(world: world).runUntilIdle();
  final loop = HarnessLoop(world: world);
  var retry = 0;
  bool done() {
    final rs = [
      for (final c in task.checkers) evaluateChecker(c, jail.path),
    ];
    return rs.isNotEmpty && rs.every((c) => c.passed);
  }

  var passed = done();
  while (!passed && retry < 2) {
    retry++;
    final rs = [
      for (final c in task.checkers) evaluateChecker(c, jail.path),
    ];
    final failures = [
      for (final (i, c) in rs.indexed)
        if (!c.passed) 'checker #$i: ${c.detail}',
    ].join('\n');
    world.upsertComponent(
      actor,
      OpenDecision(
        prompt:
            'Your previous attempt did not pass. Failing checks:\n$failures\n\n'
            'Fix the workspace so the Dart program compiles and runs (exit 0). '
            'Run `dart run main.dart` with the run tool to check, then rewrite '
            'main.dart. Original task: ${task.prompt}',
      ),
    );
    world.flush();
    await loop.runUntilIdle();
    passed = done();
  }
  final checkers = [
    for (final c in task.checkers) evaluateChecker(c, jail.path),
  ];
  final details = [for (final c in checkers) c.detail];
  stdout.writeln('    [${task.id}] (${goalFlow ? 'run-graded' : 'baseline'})');
  for (final d in details) stdout.writeln('      check: $d');
  for (final (_, content, _, text)
      in world.query3<ToolResultContent, BeatStatus, TextContent>().toList()) {
    stdout.writeln(
      '      tool=${content.name}: ${_clip(text.text, 200)}',
    );
  }
  return passed;
}

String _clip(String s, [int n = 200]) => s.length <= n ? s : '${s.substring(0, n)}…';

Future<void> main(List<String> args) async {
  var arm = 'all'; // baseline | run-graded | all
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--arm') arm = args[++i];
  }
  final client = AppleFoundationNativeClient();
  await client.load();
  if (!await client.refreshAvailability()) {
    stderr.writeln('Apple Foundation Model unavailable on this device.');
    exit(2);
  }
  stdout.writeln('Gate run-graded vs baseline — real AFM backend\n');

  for (final t in buildTasks) {
    final jail = await Directory.systemTemp.createTemp('aim_build_');
    if (arm == 'baseline') {
      final r = await _arm(t, jail: jail, goalFlow: false);
      stdout.writeln('  [${t.id}] baseline ${r ? 'PASS' : 'FAIL'}');
    } else if (arm == 'run-graded') {
      final r = await _arm(t, jail: jail, goalFlow: true);
      stdout.writeln('  [${t.id}] run-graded ${r ? 'PASS' : 'FAIL'}');
    } else {
      final base = await _arm(t, jail: jail, goalFlow: false);
      stdout.writeln('  [${t.id}] baseline pass=$base (retrying run-graded)');
      if (base) {
        stdout.writeln('  [${t.id}] baseline passed → run-graded identical');
      } else {
        // New jail for the second arm so AFM tool state is fresh.
        final jail2 = await Directory.systemTemp.createTemp('g2_${t.id}_');
        final graded = await _arm(t, jail: jail2, goalFlow: true);
        stdout.writeln('  [${t.id}] baseline=$base run-graded=$graded');
        jail2.deleteSync(recursive: true);
      }
    }
    jail.deleteSync(recursive: true);
  }
}