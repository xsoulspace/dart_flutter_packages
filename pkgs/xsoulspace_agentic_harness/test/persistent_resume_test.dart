// ignore_for_file: lines_longer_than_80_chars

/// P5 — persistent sessions: restart survival. Run half a task (2 moves),
/// snapshot, "kill" (drop the world object entirely), restore via the store
/// (a fresh process does the same), send one more decision — the task
/// completes and the gate passes. The restored actor is idle-resumable:
/// budgets (AttemptCount, ToolRoundCount) persist, in-flight state does not.
/// Ends idle.
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/src/agent.dart';
import 'package:xsoulspace_agentic_harness/src/tooling/build_gates.dart';
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'support/agent_harness_support.dart';

/// Phase-aware scripted handler: [phase1] writes two partial files, then
/// goes text-only (the decision closes; the loop idles at the cut point).
/// After the restore, [phase2] writes the fix that makes the target pass.
class _RestartHandler implements GenerationHandler {
  _RestartHandler(this.jail);

  int generations = 0;
  final Directory jail;

  ActorGenerateResponse _respond(
    World world,
    ActorGenerateRequest request,
    List<ToolCall> calls, {
    bool finalText = false,
  }) {
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {'text': finalText ? 'done for now' : 'building'},
      rawOutput: finalText ? 'done for now' : 'building',
      toolCalls: calls,
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final n = ++generations;
    if (n == 1) {
      // Move 1: a helper module (half the work).
      return _respond(world, request, [
        const ToolCall(
          name: ToolName('write'),
          arguments: {
            'path': 'lib.dart',
            'content': 'String greet(String name) => "hi \$name";\n',
          },
        ),
      ]);
    }
    if (n == 2) {
      // Move 2: the runner that still throws — HALF the task, then idle.
      return _respond(world, request, [
        const ToolCall(
          name: ToolName('write'),
          arguments: {
            'path': 'main.dart',
            'content':
                "import 'lib.dart';\nvoid main() { throw StateError('half-built'); }\n",
          },
        ),
      ], finalText: true);
    }
    // Post-restore continuation: the fix that makes `dart run main.dart`
    // exit 0 (the gate).
    return _respond(world, request, [
      const ToolCall(
        name: ToolName('write'),
        arguments: {
          'path': 'main.dart',
          'content':
              "import 'lib.dart';\nvoid main() { print(greet('gate')); }\n",
        },
      ),
    ]);
  }
}

void main() {
  late Directory tempDir;
  late Directory jail;
  late SnapshotStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('resume-test');
    jail = Directory('${tempDir.path}/jail')..createSync(recursive: true);
    store = SnapshotStore();
    await store.open('${tempDir.path}/store');
  });

  tearDown(() => tempDir.delete(recursive: true));

  test('P5 restart survival: 2 moves → snapshot → kill → restore → one '
      'more decision → gate passes, world idle', () async {
    // ---- phase 1: half the task, in the ORIGINAL process/world ----
    final world = World()..addPlugin(AgentPlugin());
    world
      ..upsertResource(ToolRegistryResource())
      ..upsertResource(ModelRouterResource(ModelRouter()))
      ..upsertResource(DecisionFlowResource(defaultGoalFlow()))
      ..upsertResource(AgencyPolicy(maxConcurrent: 1, maxToolRounds: 12))
      ..flush();
    final root = FsToolsRoot(jail.path);
    final registry = ToolRegistry();
    for (final t in fsTools(root)) {
      registry.register(t);
    }
    world.getResource<ToolRegistryResource>().register('default', registry);

    final scene = world.spawnComponents([const Scene(), SceneFrame()]);
    final actor = world.spawnComponents([
      Actor(agentId: AgentId.create()),
      ActorModel(modelId: ModelId.create()),
      const ActorSystemPrompt(text: 'build the program'),
      ActorThreads(threads: []),
      const ActorTools(registryName: 'default'),
      PresentInScene(sceneEntity: scene),
      Goal(text: 'make main.dart run clean'),
      const OpenDecision(prompt: 'build the program'),
    ]);
    final thread = spawnThread(world, actor, scene);
    world.upsertComponent(actor, ActorThreads(threads: [thread]));
    world.flush();

    final handler = _RestartHandler(jail);
    world.getResource<GenerationHandlerResource>().registerDefault(handler);

    await HarnessLoop(world: world).runUntilIdle();
    // Half the task landed; no verifier is wired yet, so the loop idles at
    // the cut point (a decision closed with text — the actor is resumable).
    expect(File('${jail.path}/lib.dart').existsSync(), isTrue);
    expect(File('${jail.path}/main.dart').existsSync(), isTrue);
    // Simulate mid-task budget state + a stale verdict: budgets must
    // persist across the restart, the verdict must NOT.
    world
      ..upsertComponent(actor, AttemptCount(2))
      ..upsertComponent(actor, ToolRoundCount(5))
      ..upsertComponent(actor, GoalVerified(passed: false, detail: 'stale'))
      ..flush();

    // ---- snapshot + "kill" (the world object is dropped entirely) ----
    await store.save(world, meta: {'task': 'resume_01'});
    // ignore: unused_local_variable
    final killed = world; // the original handle is intentionally discarded

    // ---- phase 2: a NEW process rebuilds from the store ----
    final restored = await store.load('current');
    // The restored world is idle-resumable: no open decisions, no agency,
    // no in-flight tasks — but budgets and the thread memory persist.
    expectIdle(restored);
    final restoredActor = restored.query2<Actor, Goal>().toList().single.$1;
    final we = restored.getEntity(restoredActor.entity).$1;
    expect(
      we.get<AttemptCount>()?.value,
      2,
      reason: 'monotonic attempt budget survives the restart',
    );
    expect(
      we.get<ToolRoundCount>()?.value,
      5,
      reason: 'round ledger survives the restart',
    );
    expect(
      we.get<GoalVerified>(),
      isNull,
      reason: 'stale verdicts never cross a restart',
    );

    // Re-wire the host seams (closures never cross a process boundary):
    // tools on the same jail + the run-graded verifier = the gate.
    final restoredRegistry = ToolRegistry();
    for (final t in fsTools(root)) {
      restoredRegistry.register(t);
    }
    restored
      ..upsertResource(ModelRouterResource(ModelRouter()))
      ..upsertResource(GenerationHandlerResource())
      ..upsertResource(DecisionFlowResource(defaultGoalFlow()))
      ..upsertResource(AgencyPolicy(maxConcurrent: 1, maxToolRounds: 12))
      ..flush();
    restored
      ..getResource<ToolRegistryResource>().register('default', restoredRegistry)
      ..getResource<GenerationHandlerResource>().registerDefault(handler);
    wireRunGradedGoal(
      restored,
      command: ['dart', 'run', 'main.dart'],
      cwd: jail.path,
    );

    // ONE more decision continues the task.
    openFreshDecision(
      restored,
      restoredActor.entity,
      prompt: 'You were restored from a snapshot. Finish the task: make '
          'main.dart run clean.',
    );
    await HarnessLoop(world: restored).runUntilIdle();

    // The gate passes and the world is idle.
    final verified = we.get<GoalVerified>();
    expect(verified?.passed, isTrue, reason: verified?.detail);
    expect(
      File('${jail.path}/main.dart').readAsStringSync(),
      contains("print(greet('gate'))"),
    );
    expectIdle(restored);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
