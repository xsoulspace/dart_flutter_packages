// ignore_for_file: lines_longer_than_80_chars

/// THE DEFERRED-TASK LAW (item 3) — gate.
///
/// Pins:
/// 1. the class table is COMPLETE as data (test-run, pub-get, build,
///    app-run, dylib-build; every class carries a beatContract and
///    completionReopen: true);
/// 2. interactive/mechanical read-edit classes NEVER defer (asserted
///    NEGATIVELY: every interactive intent routes inline even with
///    deferral ENABLED, and no deferred matcher shadows one);
/// 3. classify(command) routes each deferred class; longest-prefix wins;
///    unknown → inline; DISABLED → always inline (the fallback law);
/// 4. pooling: a second actor's same-(package, convention) verify JOINS
///    the in-flight task — one task, both requesters; different packages
///    never join;
/// 5. completion lands the beat contract on EVERY requester's thread and
///    re-opens the requesting actor via the EXISTING machinery
///    (ToolResultEvent → processToolResultsSystem →
///    ToolResultPendingMarker → ReActContinuationPolicy) — no poll loop;
/// 6. accounting: deferral rate + verify-wall beats on outcomes; a
///    deferral that never produces its verification beat is a NAMED
///    defect.
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/src/systems/deferred_task_policy.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'support/agent_harness_support.dart';

World _wiredWorld() {
  final world = World()..addPlugin(AgentPlugin());
  world.upsertResource(ModelRouterResource(ModelRouter()));
  world
    ..upsertResource(ToolRegistryResource())
    ..upsertResource(DeferredTaskPolicy(enabled: true))
    ..upsertResource(DeferredVerifyPool())
    ..upsertResource(DeferredTaskAccounting())
    ..flush();
  return world;
}

/// Two actors, each with a thread — the join completion targets.
({Entity a, Entity b, Entity threadA, Entity threadB}) _twoActors(World world) {
  final scene = spawnScene(world);
  final a = spawnActor(world, scene);
  final b = spawnActor(world, scene);
  final threadA = spawnThread(world, a, scene);
  final threadB = spawnThread(world, b, scene);
  world
    ..upsertComponent(a, ActorThreads(threads: [threadA]))
    ..upsertComponent(b, ActorThreads(threads: [threadB]))
    ..flush();
  return (a: a, b: b, threadA: threadA, threadB: threadB);
}

void main() {
  test(
    'class-table completeness: exactly the five law classes, each with a '
    'beat contract and completionReopen',
    () {
      expect(kDeferredClasses.keys.toSet(), {
        'test-run',
        'pub-get',
        'build',
        'app-run',
        'dylib-build',
      });
      for (final cls in kDeferredClasses.values) {
        expect(cls.id, isIn(kDeferredClasses.keys));
        expect(cls.beatContract, isNotEmpty);
        expect(cls.completionReopen, isTrue);
      }
      // Every matcher row resolves to a table class — no orphan rows.
      for (final classId in kDeferredCommandMatchers.keys) {
        expect(kDeferredClasses[classId], isNotNull);
      }
    },
  );

  test('interactive/mechanical read-edit classes NEVER defer (negative)', () {
    for (final intent in kInteractiveIntents) {
      expect(
        classifyIntent(intent),
        DeferredRouting.inline,
        reason: 'interactive intent "$intent" must NEVER defer',
      );
    }
    // Read/edit-shaped commands have NO matcher row → inline.
    const interactiveCommands = [
      ['cat', 'lib/a.dart'],
      ['grep', '-n', 'foo', '.'],
      ['ls'],
    ];
    for (final c in interactiveCommands) {
      expect(classifyCommand(c), DeferredRouting.inline);
    }
    // No deferred verb prefix shadows an interactive intent, and the
    // interactive set never intersects the class table.
    for (final intent in kInteractiveIntents) {
      for (final prefix in kIntentVerbPrefixes) {
        expect(intent.startsWith(prefix), isFalse,
            reason: 'prefix "$prefix" would defer interactive "$intent"');
      }
    }
  });

  test('classify(command) routes every deferred class; specificity wins', () {
    expect(
      classifyCommand(['dart', 'test', 'test/a_test.dart']).toString(),
      DeferredRouting.deferred.toString(),
    );
    expect(
      matchDeferredClass(['dart', 'test'])!.id,
      'test-run',
    );
    expect(matchDeferredClass(['flutter', 'test'])!.id, 'test-run');
    expect(matchDeferredClass(['flutter', 'pub', 'get'])!.id, 'pub-get');
    expect(matchDeferredClass(['tsc', '--noEmit'])!.id, 'build');
    expect(matchDeferredClass(['flutter', 'run'])!.id, 'app-run');
    expect(matchDeferredClass(['dart', 'run'])!.id, 'app-run');
    // Longest matching prefix wins: ios-framework is a dylib build, not
    // the generic build class.
    expect(
      matchDeferredClass(['flutter', 'build', 'ios-framework'])!.id,
      'dylib-build',
    );
    expect(matchDeferredClass(['xcodebuild', '-project', 'x'])!.id,
        'dylib-build');
    expect(matchDeferredClass(['flutter', 'build', 'web'])!.id, 'build');
    // Unknown → inline.
    expect(matchDeferredClass(['node', 'script.js']), isNull);
    expect(classifyCommand(['node', 'script.js']), DeferredRouting.inline);
  });

  test('DISABLED deferral ALWAYS routes inline (the fallback law)', () {
    expect(DeferredTaskPolicy().enabled, isFalse);
    const deferred = [
      ['dart', 'test'],
      ['flutter', 'pub', 'get'],
      ['flutter', 'build'],
      ['flutter', 'run'],
      ['flutter', 'build', 'ios-framework'],
    ];
    for (final c in deferred) {
      expect(
        classifyCommand(c, deferralEnabled: false),
        DeferredRouting.inline,
        reason: 'disabled deferral must preserve the inline path for $c',
      );
    }
    expect(
      classifyIntent('run_oracle', deferralEnabled: false),
      DeferredRouting.inline,
    );
  });

  test(
    'two concurrent same-package verify requests JOIN: one task, both '
    'requesters; different packages never join',
    () {
      final world = _wiredWorld();
      final actors = _twoActors(world);
      const command = ['flutter', 'test'];
      final first = world.getResource<DeferredVerifyPool>().join(
            world: world,
            packageDir: 'pkgs/foo',
            conventionCommand: command,
            requester: actors.a,
          );
      final second = world.getResource<DeferredVerifyPool>().join(
            world: world,
            packageDir: 'pkgs/foo',
            conventionCommand: command,
            requester: actors.b,
          );
      // THE JOIN LAW: same (package, convention) → the SAME pooled task.
      expect(second.taskId, first.taskId);
      expect(identical(first, second), isTrue);
      expect(first.requesters, [actors.a, actors.b]);
      expect(
        world.getResource<TaskRegistryResource>().has(first.taskId),
        isTrue,
      );
      expect(
        world.getResource<DeferredVerifyPool>().inFlightCount,
        1,
      );
      // Different package (same convention) NEVER joins.
      final other = world.getResource<DeferredVerifyPool>().join(
            world: world,
            packageDir: 'pkgs/bar',
            conventionCommand: command,
            requester: actors.a,
          );
      expect(other.taskId == first.taskId, isFalse);
      expect(other.requesters, [actors.a]);
      expect(world.getResource<DeferredVerifyPool>().inFlightCount, 2);
      // Same package, DIFFERENT convention command never joins either.
      final third = world.getResource<DeferredVerifyPool>().join(
            world: world,
            packageDir: 'pkgs/foo',
            conventionCommand: ['dart', 'test'],
            requester: actors.a,
          );
      expect(third.taskId == first.taskId, isFalse);
      expect(world.getResource<DeferredVerifyPool>().inFlightCount, 3);
      // Drain honestly: complete every pooled entry so no verification
      // dangles, then let the mechanical schedule land the beats.
      for (final e in [
        first,
        other,
        third,
      ]) {
        completeDeferredVerify(
          world,
          taskId: e.taskId,
          passed: true,
          detail: 'run: exit=0',
          verifyWallMs: 30,
        );
      }
      world.runSchedule(Schedules.mechanical);
      world.flush();
      expect(world.getResource<DeferredTaskAccounting>().namedDefects(),
          isEmpty);
      expectIdle(world);
    },
  );

  test(
    'completion lands the beat contract on EVERY requester thread and '
    're-opens the requesting actor via the EXISTING machinery',
    () {
      final world = _wiredWorld();
      final actors = _twoActors(world);
      const command = ['flutter', 'test'];
      final entry = world.getResource<DeferredVerifyPool>().join(
            world: world,
            packageDir: 'pkgs/foo',
            conventionCommand: command,
            requester: actors.a,
          );
      world.getResource<DeferredVerifyPool>().join(
            world: world,
            packageDir: 'pkgs/foo',
            conventionCommand: command,
            requester: actors.b,
          );
      final accounting = world.getResource<DeferredTaskAccounting>();
      // Deferral-rate accounting on the task outcome (2 requests, both
      // routed through one deferred task).
      expect(accounting.totalRequests, 2);
      expect(accounting.deferralRate, 1.0);

      completeDeferredVerify(
        world,
        taskId: entry.taskId,
        passed: true,
        detail: 'run: exit=0',
        verifyWallMs: 1500,
        command: command,
      );
      // The registered task resolved; the completion events are in the
      // channel (one per requester) until the mechanical schedule lands
      // them as beats.
      expect(world.getResource<TaskRegistryResource>().isEmpty, isTrue);
      world.runSchedule(Schedules.mechanical);
      world.flush();
      for (final thread in [actors.threadA, actors.threadB]) {
        final beats = world
            .getResource<FacetIndex>()
            .beatsOfThread(thread)
            .toList();
        expect(beats, isNotEmpty);
        final beat = beats.last;
        final we = world.getEntity(beat).$1;
        final content = we.get<ToolResultContent>();
        expect(content, isNotNull);
        expect(content!.name, kDeferredClasses['test-run']!.beatContract);
        final output = jsonDecode(content.output! as String) as Map;
        expect(output['ok'], true);
        expect(output['verify_wall_ms'], 1500);
        expect(output['deferred'], true);
      }
      // The re-open: the pending-result marker drives the EXISTING
      // ReActContinuationPolicy — run the agency grant (decisionFlow runs
      // first) and both actors hold an open decision. No poll loop.
      expect(
        world.query2<Actor, ToolResultPendingMarker>().toList().length,
        2,
      );
      world.runSchedule(Schedules.agencyGrant);
      world.flush();
      for (final actor in [actors.a, actors.b]) {
        expect(world.getEntity(actor).$1.has<OpenDecision>(), isTrue);
      }
      // Accounting: two beats landed (one per requester), deferred time
      // landed AS A BEAT, no named defects.
      expect(accounting.completionBeats, 2);
      expect(accounting.verifyWallBeatMsTotal, 1500);
      expect(accounting.namedDefects(), isEmpty);
      // Drain the re-opened decisions honestly: consume the open
      // decisions + granted agency so the world ends idle.
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
    'a deferral that never produces its verification beat is a NAMED '
    'defect',
    () {
      final world = _wiredWorld();
      final actors = _twoActors(world);
      final entry = world.getResource<DeferredVerifyPool>().join(
            world: world,
            packageDir: 'pkgs/foo',
            conventionCommand: const ['dart', 'test'],
            requester: actors.a,
          );
      final accounting = world.getResource<DeferredTaskAccounting>();
      // NO completion arrives — the defect is named, never silent.
      final defects = accounting.namedDefects();
      expect(defects, hasLength(1));
      expect(defects.single, contains('deferred_task_defect'));
      expect(defects.single, contains('goal_verify'));
      expect(defects.single, contains(entry.classId));
      // Completion clears the defect ledger.
      completeDeferredVerify(
        world,
        taskId: entry.taskId,
        passed: true,
        detail: 'run: exit=0',
        verifyWallMs: 40,
      );
      world.runSchedule(Schedules.mechanical);
      world.flush();
      expect(accounting.namedDefects(), isEmpty);
      expectIdle(world);
    },
  );

  test(
    'pool key identity: (package, convention) — the join contract is data',
    () {
      expect(
        deferredVerifyPoolKey(
          packageDir: 'pkgs/foo',
          convention: const ['flutter', 'test'],
        ),
        deferredVerifyPoolKey(
          packageDir: 'pkgs/foo',
          convention: const ['flutter', 'test'],
        ),
      );
      expect(
        deferredVerifyPoolKey(
          packageDir: 'pkgs/foo',
          convention: const ['flutter', 'test'],
        ) !=
            deferredVerifyPoolKey(
              packageDir: 'pkgs/bar',
              convention: const ['flutter', 'test'],
            ),
        isTrue,
      );
      expect(
        deferredVerifyPoolKey(
          packageDir: 'pkgs/foo',
          convention: const ['flutter', 'test'],
        ) !=
            deferredVerifyPoolKey(
              packageDir: 'pkgs/foo',
              convention: const ['dart', 'test'],
            ),
        isTrue,
      );
      expect(
        deferredVerifyPoolKey(
          packageDir: 'pkgs/foo',
          convention: const ['flutter', 'test'],
        ),
        contains('pkg:pkgs/foo'),
      );
    },
  );
}
