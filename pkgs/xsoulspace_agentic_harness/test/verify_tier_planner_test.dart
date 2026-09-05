// ignore_for_file: lines_longer_than_80_chars

/// R7 follow-up GATE — tiered verification as a HARNESS capability (the
/// 20–23s fix). The stateless beat-derived planner must:
/// - SKIP the grade when no edit move landed since the last grade;
/// - NARROW the grade to the test files in the refs frontier of the
///   touched lib files (derived from the tree, never model-chosen);
/// - fall back to the full convention command when the tree knows nothing.
///
/// The full suite remains the TERMINAL proof at the driver's final gate.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/benchmark_api.dart'
    show VerifyTierPlanner, runGoalVerifier, wireRunGradedGoal;
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart'
    show FsToolsRoot, runTool;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'package:xsoulspace_agentic_workspace/xsoulspace_agentic_workspace.dart';

void main() {
  late Directory jail;
  late World world;
  late Entity actor;
  late Entity thread;

  setUp(() async {
    jail = await Directory.systemTemp.createTemp('verify_tiers_');
    File('${jail.path}/pubspec.yaml')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('name: tiers\nenvironment:\n  sdk: ^3.0.0\n');
    File('${jail.path}/lib/loop.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('bool inBounds(int i, int n) => i <= n;\n');
    File('${jail.path}/test/loop_test.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        "import 'package:test/test.dart';\n"
        "import 'package:tiers/loop.dart';\n"
        "void main() { test('inclusive', () { expect(inBounds(3, 3), isTrue); }); }\n",
      );
    world = World()..addPlugin(AgentPlugin());
    world.upsertResource(ToolRegistryResource());
    await repoEtlTool(world, jail).execute({'action': 'scan'});

    final scene = world.spawnComponents([Scene(), SceneFrame()]);
    actor = world.spawnComponents([
      Actor(agentId: AgentId.create()),
      ActorModel(modelId: ModelId.create()),
      ActorThreads(threads: []),
      ActorTools(registryName: 'default'),
      PresentInScene(sceneEntity: scene),
      Goal(text: 'tiered verification fixture'),
    ]);
    thread = spawnThread(world, actor, scene);
    world.upsertComponent(actor, ActorThreads(threads: [thread]));
    world.flush();
  });
  tearDown(() {
    try {
      jail.deleteSync(recursive: true);
    } on Object {
      // best effort
    }
  });

  /// Fabricates one edit_symbol beat with [files] touched (the shape the
  /// real span editor leaves on the thread).
  void addEditBeat(List<String> files) {
    final beat = world.reserveEmptyEntity().entity;
    final we = world.getEntity(beat).$1;
    we
      ..insert(BeatToolCall('edit_symbol', const {}))
      ..insert(
        ToolResultContent(
          name: 'edit_symbol',
          output: {'ok': true, 'files': files},
        ),
      )
      ..insert(Speaker(actor));
    // The planner reads the thread via the actor's ActorThreads — the
    // beat must be a member of it (same path the loop's indexer uses).
    indexBeat(world, beat, const <String>[], thread: thread);
  }

  test(
    'tiered verification: skip → narrow (frontier tests) → full fallback',
    () async {
      const planner = VerifyTierPlanner();

      // 1. No edits at all → SKIP: the in-loop verifier has nothing to
      //    re-grade (the driver's final gate remains the terminal proof).
      final first = await planner(world);
      expect(first?.skip, isTrue, reason: 'nothing pending → skip');

      // 2. One edit landed on lib/loop.dart → NARROW to the frontier
      //    test files (loop_test.dart references inBounds — the tree
      //    knows).
      addEditBeat(['lib/loop.dart']);
      final narrowed = await planner(world);
      expect(narrowed?.skip, isFalse);
      expect(narrowed?.command, [
        'dart',
        'test',
        'test/loop_test.dart',
      ], reason: 'the refs frontier of lib/loop.dart carries its test file');

      // 3. The REAL verifier grades (writes the goal_verify beat), then
      //    no new edit lands → SKIP (nothing to re-grade).
      wireRunGradedGoal(
        world,
        command: ['dart', 'test'],
        cwd: jail.path,
        planProvider: planner, // the planner itself: verify → skip tier
      );
      final registry = ToolRegistry();
      registry.register(
        runTool(
          FsToolsRoot(jail.path),
          allowlist: const [
            ['dart', 'analyze'],
            ['dart', 'test'],
          ],
        ),
      );
      world.getResource<ToolRegistryResource>().register('default', registry);
      final runDef = registry.get(const ToolName('run'))!;
      final runOut = await runDef.execute({
        'command': ['dart', 'test', 'test/loop_test.dart'],
      });
      expect(runOut, isNotNull);
      // The verifier grades PER pending actor — mark the actor pending so
      // the real grade path runs.
      world.upsertComponent(actor, ToolResultPendingMarker());
      await runGoalVerifier(world); // stamps GoalVerified + goal_verify beat
      final again = await planner(world);
      expect(
        again?.skip,
        isTrue,
        reason:
            'the grade consumed the pending changes — beats, not a '
            'side-channel counter',
      );

      // 4. A touched file with NO test in its frontier → full fallback:
      //    null IS the signal (the convention command runs untouched).
      addEditBeat(['pubspec.yaml']);
      final fallback = await planner(world);
      expect(
        fallback,
        isNull,
        reason: 'no frontier tests → the full convention command (null plan)',
      );
    },
  );
}
