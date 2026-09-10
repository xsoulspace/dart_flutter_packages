// ignore_for_file: lines_longer_than_80_chars

/// PRODUCTION DEFERRAL WIRING (follow-up 2) — the end-to-end gate.
///
/// The deferred-task law + DeferredVerifyPool were landed but NO
/// production path called them (the daemon's run-graded verify wall ran
/// inline). This gate proves the WIRED path end-to-end on the daemon's
/// verify seam (the same `wireRunGradedGoal`/`runGoalVerifier` machinery
/// `runCodingAgentOnce` wires for the daemon):
///
/// 1. the production path: a `test-run`-class per-package verify step
///    becomes a POOLED deferred task — nothing runs inline, the grade
///    decision is ms-scale, the executor spawns the package's convention
///    AS the registered task's work, the `goal_verify` completion beat
///    carries `verify_wall_ms`, and the requester is re-opened;
/// 2. the JOIN law on the wired path: two pending requesters → ONE task,
///    ONE execution, TWO completion beats;
/// 3. the mixed-plan law: ANY inline-class step → the WHOLE plan inline
///    verbatim (conjunction verdicts never fork across completion paths);
/// 4. the unwired fallback: no policy → the legacy inline verify verbatim;
/// 5. the daemon flag parse (`--defer-verify` / `--no-defer-verify`).
///
/// The runner is INJECTED (no real subprocess): the gate is about the
/// WIRING — which path runs, what defers, what re-opens — and the
/// RE-METER: the grade-decision wall (the edit-apply path no longer
/// carries the verify wall) vs the deferred verify wall (beat-carried).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/benchmark_api.dart'
    show
        RunGoalCommand,
        RunGoalPlan,
        VerifyTierPlanner,
        dartVerifyConvention,
        runGoalVerifier,
        wireRunGradedGoal;
import 'package:xsoulspace_agentic_harness/src/systems/deferred_task_policy.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_agentic_host/src/coding_agent_runner.dart'
    show
        DeferredVerifyPlanner,
        deferVerifyHostDefault,
        runDeferredVerifyTask,
        wireDeferredVerify;
import 'package:xsoulspace_agentic_host/xsoulspace_agentic_host.dart'
    show resolveDeferVerifyFlag;

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

/// One recorded INLINE run (the run tool the verifier executes steps
/// through — the legacy path's observable).
class RecordedRun {
  RecordedRun({required this.command, required this.cwd});
  final List<String> command;
  final String cwd;
}

/// One recorded DEFERRED execution (the executor's injected runner).
class RecordedDeferred {
  RecordedDeferred({required this.command, required this.cwd});
  final List<String> command;
  final String cwd;
}

/// A fixture world with ONE goal actor (the daemon shape) wired for the
/// run-graded verify over a fixture MONOREPO.
class Fixture {
  Fixture({
    required this.world,
    required this.root,
    required this.actor,
    required this.thread,
    required this.deferredCalls,
    required this.inlineRuns,
    required this.release,
    required this.deferredWallMs,
  });

  final World world;
  final Directory root;
  final Entity actor;
  final Entity thread;

  /// Every DEFERRED execution the executor spawned (recorded runner).
  final List<RecordedDeferred> deferredCalls;

  /// Every INLINE run the verifier executed through the run tool.
  final List<RecordedRun> inlineRuns;

  /// Gates the recorded deferred runner: the test decides when the
  /// "convention" finishes.
  final Completer<void> release;

  /// The wall the recorded deferred runner reports (the simulated
  /// convention run — the data `verify_wall_ms` carries).
  final int deferredWallMs;
}

Future<Fixture> _fixture({
  bool wired = true,
  bool enabled = true,
  Future<RunGoalPlan?> Function(World world)? innerPlanner,
}) async {
  final root = await Directory.systemTemp.createTemp('deferred_prod_');
  File('${root.path}/pubspec.yaml')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      'name: fixture_workspace\nenvironment:\n  sdk: ^3.0.0\nworkspace:\n  packages:\n',
    );
  File('${root.path}/pkgs/alpha/pubspec.yaml')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('name: alpha\nenvironment:\n  sdk: ^3.0.0\n');
  File('${root.path}/pkgs/alpha/lib/alpha.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('bool flagAlpha() => true;\n');
  File('${root.path}/pkgs/alpha/test/alpha_test.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      "import 'package:test/test.dart';\n"
      "import 'package:alpha/alpha.dart';\n"
      "void main() { test('flag', () { expect(flagAlpha(), isTrue); }); }\n",
    );

  final world = World()..addPlugin(AgentPlugin());
  world
    ..upsertResource(ToolRegistryResource())
    ..upsertResource(ModelRouterResource(ModelRouter()))
    ..upsertResource(MeaningIndex());
  if (wired) {
    wireDeferredVerify(world);
    if (!enabled) world.upsertResource(DeferredTaskPolicy(enabled: false));
  }
  final scene = world.spawnComponents([const Scene(), SceneFrame()]);
  final actor = world.spawnComponents([
    Actor(agentId: AgentId.create()),
    ActorModel(modelId: ModelId.create()),
    ActorThreads(threads: []),
    ActorTools(registryName: 'default'),
    PresentInScene(sceneEntity: scene),
    Goal(text: 'deferred-verify production fixture'),
  ]);
  final thread = spawnThread(world, actor, scene);
  world.upsertComponent(actor, ActorThreads(threads: [thread]));
  world.flush();

  final deferredCalls = <RecordedDeferred>[];
  final inlineRuns = <RecordedRun>[];
  const deferredWallMs = 20;
  final release = Completer<void>();

  // The recorded RUN TOOL (the legacy inline path's observable).
  final registry = ToolRegistry();
  registry.register(
    ToolDef.encode(
      name: const ToolName('run'),
      description: 'recorded runner (LLM-free gate)',
      execute: (args) async {
        final map = args is Map ? args : const <String, Object?>{};
        inlineRuns.add(
          RecordedRun(
            command: [
              for (final c in (map['command'] as List).cast<String>()) c,
            ],
            cwd: '${map['cwd']}',
          ),
        );
        return {'ok': true, 'exit_code': 0, 'stdout': '', 'stderr': ''};
      },
    ),
  );
  world.getResource<ToolRegistryResource>().register('default', registry);

  // The run-graded verify over the ROOT convention (the daemon wires the
  // workspace convention; the tier planner derives the per-package step).
  wireRunGradedGoal(
    world,
    command: const ['flutter', 'test'],
    cwd: root.path,
    planProvider: DeferredVerifyPlanner(
      inner:
          innerPlanner ??
          const VerifyTierPlanner(convention: dartVerifyConvention).call,
      runner: (command, cwd, timeoutMs) async {
        deferredCalls.add(RecordedDeferred(command: command, cwd: cwd));
        await release.future;
        await Future<void>.delayed(
          const Duration(milliseconds: deferredWallMs),
        );
        return (ok: true, detail: 'run: exit=0');
      },
    ),
  );
  return Fixture(
    world: world,
    root: root,
    actor: actor,
    thread: thread,
    deferredCalls: deferredCalls,
    inlineRuns: inlineRuns,
    release: release,
    deferredWallMs: deferredWallMs,
  );
}

/// Fabricates one edit_symbol beat with [files] touched (the shape the
/// real span editor leaves on the thread) and marks the actor pending.
void _touchAndPending(Fixture f, List<String> files) {
  final beat = f.world.reserveEmptyEntity().entity;
  final we = f.world.getEntity(beat).$1;
  we
    ..insert(BeatToolCall('edit_symbol', const {}))
    ..insert(
      ToolResultContent(
        name: 'edit_symbol',
        output: {'ok': true, 'files': files},
      ),
    )
    ..insert(Speaker(f.actor));
  indexBeat(f.world, beat, const <String>[], thread: f.thread);
  f.world.upsertComponent(f.actor, ToolResultPendingMarker());
  f.world.flush();
}

/// Waits until every in-flight task completed (bounded — a deferral that
/// never completes is the named-defect class, never an infinite gate).
Future<void> _waitForTasksDone(World world) async {
  for (var i = 0; i < 500; i++) {
    if (world.getResource<TaskRegistryResource>().isEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('the deferred verify task never completed (named-defect class)');
}

/// The `goal_verify` completion beats on [thread] (decoded outputs).
List<Map<String, Object?>> _completionBeats(World world, Entity thread) => [
  for (final beat
      in world.getResource<FacetIndex>().beatsOfThread(thread).toList())
    if (world.getEntity(beat).$1.get<ToolResultContent>()
        case final content?)
      if (content.name == kDeferredClasses['test-run']!.beatContract)
        if (content.output != null)
          jsonDecode(content.output! as String) as Map<String, Object?>,
];

void main() {
  // ignore: unnecessary_async
  tearDown(() async {
    // The global composition flag is the CLI's surface — restore the
    // shipped default so the suite stays order-independent.
    deferVerifyHostDefault = false;
  });

  test(
    'PRODUCTION PATH: a test-run verify step defers as a pooled task — '
    'ms-scale grade decision, beat-carried verify wall, re-opened requester',
    () async {
      final f = await _fixture();
      addTearDown(() => f.root.deleteSync(recursive: true));
      _touchAndPending(f, ['pkgs/alpha/lib/alpha.dart']);

      // THE GRADE DECISION: the verifier pass returns WITHOUT running the
      // convention inline — the verify wall no longer rides the edit path.
      final gradeSw = Stopwatch()..start();
      await runGoalVerifier(f.world);
      gradeSw.stop();
      final gradeDecisionWallMs = gradeSw.elapsedMilliseconds;

      expect(f.inlineRuns, isEmpty, reason: 'NOTHING ran inline');
      expect(f.deferredCalls, hasLength(1), reason: 'the executor spawned');
      expect(
        f.deferredCalls.single.command,
        ['dart', 'test'],
        reason: 'the PACKAGE convention (the per-package derivation)',
      );
      expect(f.deferredCalls.single.cwd, endsWith('pkgs/alpha'));
      final pool = f.world.getResource<DeferredVerifyPool>();
      expect(pool.inFlightCount, 1, reason: 'ONE pooled task in flight');
      final accounting = f.world.getResource<DeferredTaskAccounting>();
      expect(accounting.deferredStarted, 1);
      expect(accounting.completionBeats, 0);
      // The pool key is the (package, convention) join identity.
      final entry = pool.entryByTaskId(
        // The only entry — resolve via a fresh join to read its key shape.
        pool.entryOf('pkg:pkgs/alpha|conv:dart test')!.taskId,
      );
      expect(entry, isNotNull);

      // THE COMPLETION BEAT: the executor finishes the registered task's
      // work; the verdict lands as a beat, never a side-channel.
      f.release.complete();
      await _waitForTasksDone(f.world);
      f.world.runSchedule(Schedules.mechanical);
      f.world.flush();
      final beats = _completionBeats(f.world, f.thread);
      expect(beats, hasLength(1));
      final beatWall = beats.single['verify_wall_ms'] as int;
      expect(
        beatWall,
        greaterThanOrEqualTo(f.deferredWallMs - 2),
        reason: 'the beat carries the DEFERRED verify wall',
      );
      expect(beats.single['ok'], isTrue);
      expect(beats.single['deferred'], isTrue);
      expect(beats.single['class'], 'test-run');
      expect(beats.single['command'], ['dart', 'test']);

      // RE-OPENED on completion (the ToolResultPendingMarker continuation —
      // never a poll loop).
      f.world.runSchedule(Schedules.agencyGrant);
      f.world.flush();
      expect(
        f.world.getEntity(f.actor).$1.has<OpenDecision>(),
        isTrue,
        reason: 'the requester is re-opened by the completion beat',
      );

      // ACCOUNTING: deferred time landed AS BEATS; no named defects.
      expect(accounting.completionBeats, 1);
      expect(accounting.verifyWallBeatMsTotal, beatWall);
      expect(accounting.deferralRate, greaterThan(0));
      expect(accounting.namedDefects(), isEmpty);

      // THE CONSUMPTION LAW: the completion beat is named `goal_verify`, so
      // the next grade pass sees NO pending edits — no re-registration
      // loop, no second execution.
      f.world.getEntity(f.actor).$1
        ..remove<OpenDecision>()
        ..remove<Agency>();
      f.world.upsertComponent(f.actor, ToolResultPendingMarker());
      f.world.flush();
      await runGoalVerifier(f.world);
      if (!f.release.isCompleted) {
        f.release.complete(); // would unblock a SECOND executor — none exists
      }
      f.world.runSchedule(Schedules.mechanical);
      f.world.flush();
      expect(f.deferredCalls, hasLength(1));
      expect(f.inlineRuns, isEmpty);
      expect(_completionBeats(f.world, f.thread), hasLength(1));
      expectIdle(f.world);

      // THE RE-METER (published in results_seam_speed.md § deferred
      // verify): the grade decision (the wall the edit path pays) vs the
      // deferred verify wall (beat-carried). n=1, LLM-free (0 tokens).
      // ignore: avoid_print
      print(
        'RE-METER deferred-verify: grade_decision_wall_ms='
        '$gradeDecisionWallMs (inline verify wall: 0 — deferred) '
        'verify_wall_ms(beat)=$beatWall n=1 backend=scripted(LLM-free) '
        'decision_path=run-graded-verify/planProvider-seam tokens=0',
      );
      expect(
        gradeDecisionWallMs,
        lessThan(1000),
        reason: 'the grade decision is ms-scale; the verify wall is '
            'deferred, never inline',
      );
    },
  );

  test(
    'JOIN on the wired path: two pending requesters → ONE task, ONE '
    'execution, TWO completion beats',
    () async {
      final f = await _fixture();
      addTearDown(() => f.root.deleteSync(recursive: true));
      // A SECOND pending actor (a squad peer grading the same package).
      final scene = f.world.spawnComponents([const Scene(), SceneFrame()]);
      final peer = f.world.spawnComponents([
        Actor(agentId: AgentId.create()),
        ActorModel(modelId: ModelId.create()),
        ActorTools(registryName: 'default'),
        PresentInScene(sceneEntity: scene),
      ]);
      final peerThread = spawnThread(f.world, peer, scene);
      f.world.upsertComponent(peer, ActorThreads(threads: [peerThread]));
      f.world.flush();

      _touchAndPending(f, ['pkgs/alpha/lib/alpha.dart']);
      final peerBeat = f.world.reserveEmptyEntity().entity;
      f.world.getEntity(peerBeat).$1
        ..insert(BeatToolCall('edit_symbol', const {}))
        ..insert(
          ToolResultContent(
            name: 'edit_symbol',
            output: {'ok': true, 'files': ['pkgs/alpha/lib/alpha.dart']},
          ),
        )
        ..insert(Speaker(peer));
      indexBeat(f.world, peerBeat, const <String>[], thread: peerThread);
      f.world.upsertComponent(peer, ToolResultPendingMarker());
      f.world.flush();

      await runGoalVerifier(f.world);
      expect(f.deferredCalls, hasLength(1), reason: 'ONE task runs');
      expect(f.inlineRuns, isEmpty);
      final accounting = f.world.getResource<DeferredTaskAccounting>();
      // A's grade registered + joined the peer; the peer's grade joined
      // both requesters again (idempotent appends, honest join records).
      expect(accounting.joinedRequests, 3);
      f.release.complete();
      await _waitForTasksDone(f.world);
      f.world.runSchedule(Schedules.mechanical);
      f.world.flush();
      expect(_completionBeats(f.world, f.thread), hasLength(1));
      expect(_completionBeats(f.world, peerThread), hasLength(1));
      expect(accounting.deferredStarted, 1);
      expect(accounting.completionBeats, 2);
      expect(accounting.namedDefects(), isEmpty);
      for (final a in [f.actor, peer]) {
        f.world.getEntity(a).$1
          ..remove<OpenDecision>()
          ..remove<Agency>();
      }
      f.world.flush();
      expectIdle(f.world);
    },
  );

  test(
    'MIXED PLAN: any inline-class step → the WHOLE plan runs inline '
    'verbatim (conjunction verdicts never fork across completion paths)',
    () async {
      final f = await _fixture(
        innerPlanner: (world) async => RunGoalPlan(
          skip: false,
          commands: const [
            RunGoalCommand(command: ['dart', 'test'], cwd: 'pkgs/alpha'),
            RunGoalCommand(command: ['dart', 'analyze'], cwd: 'pkgs/alpha'),
          ],
        ),
      );
      addTearDown(() => f.root.deleteSync(recursive: true));
      _touchAndPending(f, ['pkgs/alpha/lib/alpha.dart']);
      await runGoalVerifier(f.world);
      expect(
        f.inlineRuns.map((r) => r.command),
        [
          ['dart', 'test'],
          ['dart', 'analyze'],
        ],
        reason: 'the legacy inline conjunction, fail fast, unchanged',
      );
      expect(f.deferredCalls, isEmpty, reason: 'nothing deferred');
      expect(f.world.getResource<DeferredVerifyPool>().inFlightCount, 0);
      expect(f.world.getResource<DeferredTaskAccounting>().totalRequests, 0);
      expectIdle(f.world);
    },
  );

  test(
    'UNWIRED/DISABLED fallback: the legacy inline verify verbatim (pool '
    'never engaged, zero accounting)',
    () async {
      for (final (wired, enabled) in [(false, true), (true, false)]) {
        final f = await _fixture(wired: wired, enabled: enabled);
        addTearDown(() => f.root.deleteSync(recursive: true));
        _touchAndPending(f, ['pkgs/alpha/lib/alpha.dart']);
        await runGoalVerifier(f.world);
        expect(
          f.inlineRuns,
          hasLength(1),
          reason: 'the inline path runs the derived step via the run tool',
        );
        expect(f.inlineRuns.single.command, ['dart', 'test']);
        expect(f.deferredCalls, isEmpty);
        // Zero accounting: the disabled fallback registers NO deferred
        // task (and an unwired world never built the ledger).
        if (wired) {
          final accounting = f.world.getResource<DeferredTaskAccounting>();
          expect(accounting.totalRequests, 0);
          expect(accounting.namedDefects(), isEmpty);
        }
        expectIdle(f.world);
      }
    },
  );

  test('the executor fails the task honestly when no root resolves', () async {
    final f = await _fixture();
    addTearDown(() => f.root.deleteSync(recursive: true));
    f.release.complete();
    // Drive the executor DIRECTLY (it is the requester-side half): no
    // workspace root → the registered task completes FAILED with a named
    // detail — never a dangling task (the named-defect law).
    const step = RunGoalCommand(command: ['dart', 'test'], cwd: 'pkgs/alpha');
    final entry = f.world.getResource<DeferredVerifyPool>().join(
          world: f.world,
          packageDir: 'pkgs/alpha',
          conventionCommand: step.command,
          requester: f.actor,
        );
    await runDeferredVerifyTask(
      f.world,
      step: step,
      entry: entry,
      workspaceRoot: '',
      runner: (command, cwd, timeoutMs) async => (ok: true, detail: 'unused'),
    );
    f.world.runSchedule(Schedules.mechanical);
    f.world.flush();
    final beats = _completionBeats(f.world, f.thread);
    expect(beats, hasLength(1));
    expect(beats.single['ok'], isFalse);
    expect(
      '${beats.single['detail']}',
      contains('no workspace root resolvable'),
    );
    expect(f.world.getResource<DeferredTaskAccounting>().namedDefects(),
        isEmpty);
  });

  test('the daemon flag parse: ON by default, --no-defer-verify restores '
      'the inline fallback, last flag wins', () {
    expect(resolveDeferVerifyFlag([]), isTrue);
    expect(resolveDeferVerifyFlag(['--scripted']), isTrue);
    expect(resolveDeferVerifyFlag(['--no-defer-verify']), isFalse);
    expect(
      resolveDeferVerifyFlag(['--no-defer-verify', '--defer-verify']),
      isTrue,
      reason: 'last flag wins (standard CLI precedence)',
    );
    expect(
      resolveDeferVerifyFlag(['--defer-verify', '--no-defer-verify']),
      isFalse,
    );
    // The shipped default is OFF at the library level — only the daemon
    // composition root flips it (suite semantics stay honest).
    expect(deferVerifyHostDefault, isFalse);
  });
}
