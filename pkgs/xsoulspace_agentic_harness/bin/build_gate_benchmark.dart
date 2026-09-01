// ignore_for_file: lines_longer_than_80_chars

/// Gate-B benchmark: does making a Goal advance by running code (the `run`
/// tool as a behavioral oracle + `runs` checker) move pass rate / token spend
/// vs the baseline (content-only checkers, `defaultReAct`) on self-contained
/// "build a Dart program" tasks?
///
/// LLM-free: a scripted builder converges to a valid Dart target; each arm is
/// run in an identical jail. Output: markdown pass/calls/tokens table.
library;

import 'dart:io';

import 'package:xsoulspace_agentic_harness/src/benchmark/coding_suite/checkers.dart';
import 'package:xsoulspace_agentic_harness/src/benchmark/coding_suite/task_spec.dart'
    show CheckerSpec;
import 'package:xsoulspace_agentic_harness/src/tooling/build_gates.dart';
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

class BuildTask {
  const BuildTask({
    required this.id,
    required this.prompt,
    required this.write, required this.checkers, this.fixture,
  });
  final String id;
  final String prompt;
  final String? fixture;
  final Map<String, String> write;
  final List<CheckerSpec> checkers;
}

final _tasks = <BuildTask>[
  BuildTask(
    id: 'build_board',
    prompt:
        'Write a Dart program main.dart that prints a 3x3 tic-tac-toe board '
        'then exits 0.',
    write: {
      'main.dart':
          'void main() { for (var r = 0; r < 3; r++) print("x|x|x"); }\n',
    },
    checkers: <CheckerSpec>[
      CheckerSpec(type: 'runs', path: 'main.dart'),
      CheckerSpec(type: 'contains', path: 'main.dart', value: 'print'),
    ],
  ),
  BuildTask(
    id: 'build_turn',
    prompt: 'Write a Dart program main.dart that prints X then O, exit 0.',
    write: {'main.dart': 'void main() { print("X"); print("O"); }\n'},
    checkers: <CheckerSpec>[
      CheckerSpec(type: 'runs', path: 'main.dart'),
      CheckerSpec(type: 'contains', path: 'main.dart', value: 'O'),
    ],
  ),
];

/// Scripted builder: writes each expected file once, then stops.
class _Builder implements GenerationHandler {
  _Builder(this.task);
  final BuildTask task;
  final done = <String>{};

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    String? next;
    for (final p in task.write.keys) {
      if (!done.contains(p)) {
        next = p;
        break;
      }
    }
    if (next == null) {
      return ActorGenerateResponse(
        actorEntity: request.actorEntity,
        structuredOutput: const {'text': 'done'},
        rawOutput: 'done',
        taskId: request.taskId,
      );
    }
    done.add(next);
    return ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: const {'text': 'writing'},
      rawOutput: 'writing',
      toolCalls: [
        ToolCall(
          name: const ToolName('write'),
          arguments: {'path': next, 'content': task.write[next]},
        ),
      ],
      taskId: request.taskId,
    );
  }
}

class _Row {
  const _Row(this.id, this.arm, this.passed, this.calls, this.tokens,
      this.wallMs);
  final String id;
  final String arm;
  final bool passed;
  final int calls;
  final int tokens;
  final int wallMs;
}

Future<_Row> _run(
  BuildTask task, {
  required Directory jail,
  required bool goalFlow,
}) async {
  final world = World()..addPlugin(AgentPlugin());
  if (goalFlow) registerExperimentComponents(world);
  final router = ModelRouter(inferenceClientsBuilders: {});
  const modelId = ModelId('suite');
  router.models[modelId] = const Model(
    id: modelId,
  );
  world
    ..upsertResource(ModelRouterResource(router))
    ..upsertResource(ToolRegistryResource())
    ..upsertResource(AgencyPolicy(maxConcurrent: 1))
    ..flush();

  final tokenTotal = <int>[0];
  world.getResource<GenerationHandlerResource>().registerDefault(
        CumulativeTokenMeter(_Builder(task), tokenTotal),
      );

  final registry = ToolRegistry();
  fsTools(FsToolsRoot(jail.path)).forEach(registry.register);
  world.getResource<ToolRegistryResource>().register('default', registry);

  world.upsertResource(
    DecisionFlowResource(
      goalFlow ? defaultGoalFlow() : DecisionFlow.defaultReAct(),
    ),
  );

  final scene = world.spawnComponents([const Scene(), SceneFrame()]);
  final actor = world.spawnComponents([
    Actor(agentId: AgentId.create()),
    const ActorModel(modelId: modelId),
    const ActorSystemPrompt(text: 'Build it.'),
    ActorThreads(threads: []),
    const ActorTools(registryName: 'default'),
    PresentInScene(sceneEntity: scene),
    OpenDecision(prompt: task.prompt),
  ]);
  final thread = spawnThread(world, actor, scene);
  world.upsertComponent(actor, ActorThreads(threads: [thread]));
  world.flush();

  final sw = Stopwatch()..start();
  await HarnessLoop(world: world).runUntilIdle();
  sw.stop();

  final checkers = [
    for (final c in task.checkers) evaluateChecker(c, jail.path),
  ];
  final passed = checkers.isNotEmpty && checkers.every((c) => c.passed);
  final responses = world.events.hasRegistered<ActorGenerateResponse>()
      ? world.events.stats<ActorGenerateResponse>().sent
      : 0;

  return _Row(
    task.id,
    goalFlow ? 'run-graded' : 'baseline',
    passed,
    responses,
    tokenTotal[0],
    sw.elapsedMilliseconds,
  );
}

Future<void> main() async {
  final rows = <_Row>[];
  for (final task in _tasks) {
    final jail = await Directory.systemTemp.createTemp('g_${task.id}_');
    if (task.fixture != null) {
      File('${jail.path}/main.dart').writeAsStringSync(task.fixture!);
    }
    rows.add(await _run(task, jail: jail, goalFlow: false));
    rows.add(await _run(task, jail: jail, goalFlow: true));
    jail.deleteSync(recursive: true);
  }

  stdout.writeln('| task | arm | pass | calls | tokens | wall(ms) |');
  stdout.writeln('|---|---|---|---|---|---|');
  var baseTok = 0;
  var gradedTok = 0;
  for (final r in rows) {
    stdout.writeln(
      '| ${r.id} | ${r.arm} | ${r.passed ? '✅' : '❌'} '
      '| ${r.calls} | ${r.tokens} | ${r.wallMs} |',
    );
    if (r.arm == 'baseline') {
      baseTok += r.tokens;
    } else {
      gradedTok += r.tokens;
    }
  }
  stdout.writeln('baseline tokens: $baseTok, run-graded tokens: $gradedTok');
}