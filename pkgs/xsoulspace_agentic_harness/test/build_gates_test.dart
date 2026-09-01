// ignore_for_file: lines_longer_than_80_chars

/// Gate B/C/Stage C/D seam tests (LLM-free, deterministic).
///
/// - Gate B: `defaultGoalFlow` + `RunGradedGoalPolicy` — a passed goal run
///   terminates (no new decision); a failed run continues.
/// - Gate C: `ask_user` tool pauses and resolves with an injected answer.
/// - Stage D: `planFromMatrix` renders AE-style matrix rows as Goal+Steps.
/// - Stage C: `spawnActorBranch` adds a team member actor.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:xsoulspace_agentic_harness/src/data_models/components.dart';
import 'package:xsoulspace_agentic_harness/src/tooling/build_gates.dart';
import 'package:xsoulspace_agentic_harness/src/tooling/world_builder.dart';
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'support/agent_harness_support.dart';

void main() {
  group('Gate C — a2h ask_user (deterministic provider)', () {
    test('returns the injected answer as a tool result', () async {
      final asked = <AskUserPrompt>[];
      final tool = askUserTool(
        (p) async {
          asked.add(p);
          return 'human chose option 2';
        },
      );
      final result = await tool.execute({
        'question': 'Which board size?',
        'options': ['3x3', '4x4'],
      });
      final map =
          result is String ? (jsonDecode(result) as Map) : (result as Map);
      expect(asked.single.text, 'Which board size?');
      expect(asked.single.options, ['3x3', '4x4']);
      expect(map, containsPair('answer', 'human chose option 2'));
      expect(map, containsPair('answered', true));
    });
  });

  group('Gate B — run-graded goal flow (default, not opt-in)', () {
    test('passed goal run terminates: no next decision', () async {
      final world = await buildTestWorld(decisionFlow: defaultGoalFlow());
      registerExperimentComponents(world);
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene);
      world.upsertComponent(actor, GoalVerified(passed: true, detail: 'exit=0'));
      world.flush();
      final ctx = DecisionContext(actor: actor, world: world, tick: 1);
      expect(const RunGradedGoalPolicy().evaluate(ctx), isNull);
    });

    test('failed goal run yields a continuation prompt', () async {
      final world = await buildTestWorld(decisionFlow: defaultGoalFlow());
      registerExperimentComponents(world);
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene);
      world.upsertComponent(actor, GoalVerified(passed: false, detail: 'exit=1: boom'));
      world.flush();
      final ctx = DecisionContext(actor: actor, world: world, tick: 1);
      final draft = const RunGradedGoalPolicy().evaluate(ctx);
      expect(draft, isNotNull);
      expect(draft!.prompt, contains('boom'));
      expect(draft.prompt, contains('Fix the code'));
    });
  });

  group('Stage D — planFromMatrix (AE-ETL as a host seam)', () {
    test('renders Goal + Steps from a matrix', () async {
      final world = await buildTestWorld(decisionFlow: defaultGoalFlow());
      registerExperimentComponents(world);
      planFromMatrix(
        world,
        goalText: 'Build a tic-tac-toe game',
        features: const [
          PlanFeature('feat_board', 'prints a 3x3 board'),
          PlanFeature('feat_turn', 'alternates X/O'),
        ],
      );
      world.flush();
      expect(world.query<Goal>().toList(), hasLength(1));
      expect(world.query<StepClaim>().toList(), hasLength(2));
      expect(world.query<StepStatus>().first.$2.value, 'open');
    });
  });

  group('Stage C — a2a team', () {
    test('spawnActorBranch adds a peer actor with its own decision', () async {
      final world = await buildTestWorld(decisionFlow: defaultGoalFlow());
      spawnActorBranch(
        world,
        systemPrompt: 'You are the planner.',
        prompt: 'Decompose the goal into steps.',
      );
      expect(world.query<Actor>().toList(), hasLength(1));
      expect(world.query<OpenDecision>().toList(), hasLength(1));
    });
  });

  group('Intent-graded verifier — oracle replay semantics', () {
    test("replay starts from initialState(): the actor's own intent_call "
        'state must not leak into the oracle (tier-2 parity)', () async {
      final world = await buildTestWorld();
      // A stateful counter intent: each call appends one entry.
      world.getResource<IntentRuntime>().register('save', (args, _) async {
        final state = world.getResource<IntentCallState>().state;
        final list = ((state['saved'] ?? const []) as List).toList()
          ..add(args['v']);
        world.getResource<IntentCallState>().state = {'saved': list};
        return {'saved': true};
      });
      world.getResource<IntentRuntime>().register('count', (args, _) async {
        final state = world.getResource<IntentCallState>().state;
        return {'value': ((state['saved'] ?? const []) as List).length};
      });

      final goal = world.spawnComponents([Goal(text: 'counts hold')]);
      final scene = world.spawnComponents([const Scene(), SceneFrame()]);
      final actor = world.spawnComponents([
        Actor(agentId: AgentId.create()),
        ActorModel(modelId: ModelId.create()),
        const ActorSystemPrompt(text: 'build'),
        ActorGoalRef(goal),
        PresentInScene(sceneEntity: scene),
      ]);
      world.flush();
      wireIntentGradedGoal(world, sequence: [
        const IntentExpectation('save', args: {'v': 'a'}),
        const IntentExpectation('save', args: {'v': 'b'}),
        const IntentExpectation('count', expect: {'value': 2}),
      ]);

      // The actor already called its own intents (state now holds 2) —
      // exactly the on-device shape the scripted driver caught.
      await callIntent(world, name: 'save', args: {'v': 'selfcheck-1'});
      await callIntent(world, name: 'save', args: {'v': 'selfcheck-2'});

      world.upsertComponent(actor, const ToolResultPendingMarker());
      world.flush();
      await intentGoalVerifier(world);

      final verified = world.query2<Actor, GoalVerified>().toList().single;
      expect(verified.$3.passed, isTrue,
          reason: "replay must start from initialState(), not the actor's "
              'accumulated state (got ${verified.$3.detail})');

      // The actor's own state is restored after the replay.
      expect(
        (world.getResource<IntentCallState>().state['saved'] as List).length,
        2,
      );
      expectIdle(world);
    });
  });

  group('Gate A (run tool) end-to-end in the jail', () {
    test('dart run main.dart executes a jail target', () async {
      final jail = await Directory.systemTemp.createTemp('build_gate_a_');
      addTearDown(() => jail.delete(recursive: true).catchError((_) {}));
      File('${jail.path}/main.dart')
          .writeAsStringSync('void main() { print("board ready"); }\n');
      final registry = ToolRegistry();
      registry.register(runTool(FsToolsRoot(jail.path)));
      final def = registry.get(const ToolName('run'));
      expect(def, isNotNull);
      final out = await def!.execute({'command': ['dart', 'run', 'main.dart']});
      final map = out is String ? (jsonDecode(out) as Map) : (out as Map);
      expect(map['ok'], isTrue);
      expect(map['exit_code'], 0);
      expect(map['stdout'] as String, contains('board ready'));
    });
  });
}