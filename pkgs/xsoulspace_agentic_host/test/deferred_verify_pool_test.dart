// ignore_for_file: lines_longer_than_80_chars

/// THE DEFERRED-VERIFY POOL (host wiring) — gate.
///
/// Pins the coding-runner wiring of the deferred-task law (item 3):
/// 1. two concurrent same-package verify requests → ONE pooled task and
///    TWO completion beats (each requesting actor gets the beat contract
///    on its thread and is re-opened via the EXISTING machinery);
/// 2. different packages never join;
/// 3. the DISABLED fallback preserves the old inline behavior verbatim
///    (unwired or `enabled: false` → maybeJoinDeferredVerify returns null
///    and the caller runs the legacy inline verify step);
/// 4. the per-package pool keys ([verifyPoolKeyForStep]) are the
///    (package, convention) join identity over [derivePerPackageVerify]
///    steps.
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/benchmark_api.dart'
    show
        RunGoalCommand,
        classifyVerifyCommand,
        verifyPoolKeyForStep,
        verifyPoolKeysForSteps;
import 'package:xsoulspace_agentic_harness/src/systems/deferred_task_policy.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_agentic_host/src/coding_agent_runner.dart'
    show
        completeDeferredVerifyTask,
        maybeJoinDeferredVerify,
        wireDeferredVerify;

/// The host-side copy of the harness's end-of-test idle gate (the support
/// helper lives in the harness package's own test tree).
void expectIdle(World world) {
  final problems = <String>[];
  if (world.query2<Actor, OpenDecision>().toList().isNotEmpty) {
    problems.add('OpenDecision still pending');
  }
  if (world.query2<Actor, Agency>().toList().isNotEmpty) {
    problems.add('Agency still granted');
  }
  if (world.query2<Actor, AwaitingResponse>().toList().isNotEmpty) {
    problems.add('AwaitingResponse still set');
  }
  if (!world.getResource<TaskRegistryResource>().isEmpty) {
    problems.add(
      '${world.getResource<TaskRegistryResource>().length} task(s) in flight',
    );
  }
  expect(problems, isEmpty, reason: 'harness not idle: ${problems.join('; ')}');
}

World _world({bool wired = false}) {
  final world = World()..addPlugin(AgentPlugin());
  world.upsertResource(ModelRouterResource(ModelRouter()));
  // The plugin registers the executor resource, not the registry resource
  // itself — hosts register the named registries.
  world.upsertResource(ToolRegistryResource());
  if (wired) wireDeferredVerify(world);
  return world;
}

({Entity a, Entity b, Entity threadA, Entity threadB}) _twoActors(World world) {
  final scene = world.spawnComponents([const Scene(), SceneFrame()]);
  Entity actor({
    required String systemPrompt,
  }) => world.spawnComponents([
    Actor(agentId: AgentId.create()),
    ActorModel(modelId: ModelId.create()),
    ActorSystemPrompt(text: systemPrompt),
    PresentInScene(sceneEntity: scene),
  ]);
  final a = actor(systemPrompt: 'a');
  final b = actor(systemPrompt: 'b');
  Entity threadFor(Entity owner) => spawnThread(world, owner, scene);
  final threadA = threadFor(a);
  final threadB = threadFor(b);
  world
    ..upsertComponent(a, ActorThreads(threads: [threadA]))
    ..upsertComponent(b, ActorThreads(threads: [threadB]))
    ..flush();
  return (a: a, b: b, threadA: threadA, threadB: threadB);
}

void main() {
  test(
    'two concurrent same-package verify requests → ONE task + TWO '
    'completion beats; different packages never join',
    () async {
      final world = _world(wired: true);
      final actors = _twoActors(world);
      const step = RunGoalCommand(
        command: ['flutter', 'test'],
        cwd: 'pkgs/foo',
      );
      // Two actors request the SAME package's verify CONCURRENTLY.
      final entryA = maybeJoinDeferredVerify(
        world,
        step: step,
        requester: actors.a,
      );
      final entryB = maybeJoinDeferredVerify(
        world,
        step: step,
        requester: actors.b,
      );
      expect(entryA, isNotNull);
      expect(entryB, isNotNull);
      // THE JOIN LAW: one task runs, both actors await it.
      expect(entryB!.taskId, entryA!.taskId);
      expect(entryB.requesters, [actors.a, actors.b]);
      expect(world.getResource<TaskRegistryResource>().has(entryA.taskId),
          isTrue);
      // A DIFFERENT package never joins — its own pooled task.
      final otherPackage = maybeJoinDeferredVerify(
        world,
        step: const RunGoalCommand(
          command: ['flutter', 'test'],
          cwd: 'pkgs/bar',
        ),
        requester: actors.a,
      );
      expect(otherPackage!.taskId == entryA.taskId, isFalse);
      expect(world.getResource<DeferredVerifyPool>().inFlightCount, 2);

      // COMPLETION — the existing in-flight machinery resolves the ONE
      // task and fans the beat out to EVERY requester.
      completeDeferredVerifyTask(
        world,
        taskId: entryA.taskId,
        passed: true,
        detail: 'per-package verify: 1/1 exit=0',
        verifyWallMs: 2100,
        command: step.command,
      );
      expect(!world.getResource<TaskRegistryResource>().has(entryA.taskId),
          isTrue);
      // The other package's task is independent — complete it too so no
      // verification dangles.
      completeDeferredVerifyTask(
        world,
        taskId: otherPackage.taskId,
        passed: true,
        detail: 'run: exit=0',
        verifyWallMs: 30,
      );
      world.runSchedule(Schedules.mechanical);
      world.flush();
      // TWO completion beats — one per requesting actor's thread (each
      // thread also carries the other package's independent completion;
      // both requests' 2100 ms wall beat is what we pin here).
      for (final thread in [actors.threadA, actors.threadB]) {
        final walls = [
          for (final beat in world
              .getResource<FacetIndex>()
              .beatsOfThread(thread)
              .toList())
            if (world.getEntity(beat).$1.get<ToolResultContent>()
                case final content?)
              if (content.name ==
                  kDeferredClasses['test-run']!.beatContract)
                if (content.output != null)
                  (jsonDecode(content.output! as String) as Map)['verify_wall_ms'],
        ];
        expect(walls, contains(2100));
      }
      // The requesting actors are RE-OPENED on completion (the
      // ToolResultPendingMarker continuation — never a poll loop).
      world.runSchedule(Schedules.agencyGrant);
      world.flush();
      for (final actor in [actors.a, actors.b]) {
        expect(world.getEntity(actor).$1.has<OpenDecision>(), isTrue);
      }
      // Accounting on the task outcome: 3 requests (2 joined + 1 new),
      // both beats landed, deferred time landed as beats, no defects.
      final accounting = world.getResource<DeferredTaskAccounting>();
      expect(accounting.totalRequests, 3);
      expect(accounting.completionBeats, 3);
      expect(
        accounting.verifyWallBeatMsTotal,
        2130,
        reason: 'deferred time lands as beats: 2100 (the joined verify) '
            '+ 30 (the independent package)',
      );
      expect(accounting.deferralRate, greaterThan(0));
      expect(accounting.namedDefects(), isEmpty);
      for (final actor in [actors.a, actors.b]) {
        world.getEntity(actor).$1
          ..remove<OpenDecision>()
          ..remove<Agency>();
      }
      world.flush();
      expectIdle(world);
    },
  );

  test(
    'DISABLED fallback: unwired or disabled policy → the legacy INLINE '
    'verify path runs unchanged',
    () {
      // Unwired world: no policy → null (caller runs the inline step).
      final unwired = _world(wired: false);
      final actors = _twoActors(unwired);
      expect(
        maybeJoinDeferredVerify(
          unwired,
          step: const RunGoalCommand(
            command: ['flutter', 'test'],
            cwd: 'pkgs/foo',
          ),
          requester: actors.a,
        ),
        isNull,
      );
      expect(
        unwired.getResource<TaskRegistryResource>().isEmpty,
        isTrue,
        reason: 'the inline fallback registers NO deferred task',
      );
      // Wired-but-disabled world: same null contract.
      final disabled = _world(wired: false);
      disabled.upsertResource(DeferredTaskPolicy(enabled: false));
      final disabledActors = _twoActors(disabled);
      expect(
        maybeJoinDeferredVerify(
          disabled,
          step: const RunGoalCommand(
            command: ['flutter', 'test'],
            cwd: 'pkgs/foo',
          ),
          requester: disabledActors.a,
        ),
        isNull,
      );
      // The classifier honors the same fallback law.
      expect(
        classifyVerifyCommand(
          const ['flutter', 'test'],
          deferralEnabled: false,
        ),
        DeferredRouting.inline,
      );
      expect(
        classifyVerifyCommand(const ['flutter', 'test']),
        DeferredRouting.deferred,
      );
      expect(disabled.getResource<TaskRegistryResource>().isEmpty, isTrue);
    },
  );

  test(
    'per-package pool keys: the (package, convention) join identity over '
    'derived steps',
    () {
      const step = RunGoalCommand(
        command: ['flutter', 'test'],
        cwd: 'pkgs/foo',
      );
      expect(verifyPoolKeyForStep(step), verifyPoolKeyForStep(step));
      expect(
        verifyPoolKeyForStep(step) !=
            verifyPoolKeyForStep(
              const RunGoalCommand(
                command: ['flutter', 'test'],
                cwd: 'pkgs/bar',
              ),
            ),
        isTrue,
      );
      expect(
        verifyPoolKeyForStep(step) !=
            verifyPoolKeyForStep(
              const RunGoalCommand(
                command: ['dart', 'test'],
                cwd: 'pkgs/foo',
              ),
            ),
        isTrue,
      );
      // A whole derived plan carries ONE key per ACTIVE package.
      final keys = verifyPoolKeysForSteps([
        step,
        const RunGoalCommand(
          command: ['dart', 'test'],
          cwd: 'pkgs/bar',
        ),
      ]);
      expect(keys, hasLength(2));
      expect(keys.toSet().length, 2);
      expect(keys.first, contains('pkg:pkgs/foo'));
      expect(keys.last, contains('pkg:pkgs/bar'));
    },
  );
}
