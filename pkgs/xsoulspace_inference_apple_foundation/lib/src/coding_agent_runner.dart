// ignore_for_file: lines_longer_than_80_chars

/// B3 — ONE entry point for AFM Dart coding: the runner core.
///
/// `bin/coding_agent.dart` owns only process plumbing (CLI parsing, native
/// client load, log files). Everything measurable lives here:
///
/// - task specs as data (prompt, fixtures, final-gate checkers, and which
///   mechanical verifier is wired INSIDE the loop);
/// - **verifier inside the loop (B7)**: the intent-graded or run-graded
///   verifier stamps `GoalVerified`; `RunGradedGoalPolicy` re-prompts at
///   most `AgencyPolicy.maxGoalAttempts` (3) times, consuming `AttemptCount`
///   uniformly — retries are NOT a driver-level `while(true)` oracle loop.
///   The outer oracle runs ONCE at the end, as the final gate only.
/// - pass@k protocol (B8): fresh jail per run, honest per-run log + summary
///   row (backend, n, tokens source, moves/task). No single-run claims.
///
/// `Agent = G ∘ F`: the model picks typed moves; decomposition, jails,
/// materialization, verification and repair budgets are all host programs.
library;

import 'dart:convert';
import 'dart:io';

import 'package:xsoulspace_agentic_harness/benchmark_api.dart'
    show CheckerResult, CheckerSpec, FixtureFile, defaultGoalFlow,
        openFreshDecision, wireIntentGradedGoal, wireRunGradedGoal,
        wireOverseer, maybeSpawnOverseer, OverseerLedger, IntentExpectation,
        evaluateChecker;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart'
    show fsTools, FsToolsRoot, CapturedWrite, JailWriteGateway, WriteGateMode;

import 'intent_closure_runner.dart'
    show DecisionMeter, afmSystemPrompt, registerIntentClosureTools;

/// ~110 tokens — the run-graded (fs_tools) teaching prompt. B6: teaching
/// lives in tool descriptions + the system prompt ONLY.
const codingSystemPrompt =
    'You build or fix Dart code inside the workspace. You never leave it. '
    'Tools: read, write, list_dir, glob, grep, run.\n'
    'Flow: 1) read the files you need (read/list_dir/glob/grep). 2) make '
    'the change with write. 3) run the target program with the run tool — '
    'it must exit 0. A mechanical verifier runs the goal check after your '
    'tool results; when it reports a failure, fix the code and try again. '
    'Keep going until the check passes. Finish by stating what you changed.';

/// One coding task as data: prompt + fixtures + final-gate checkers + which
/// mechanical verifier is wired inside the loop.
class CodingAgentTask {
  CodingAgentTask({
    required this.id,
    required this.prompt,
    this.fixtures = const [],
    this.checkers = const [],
    this.intents,
    this.runCommand,
    this.repairHint =
        'Fix the workspace so the check passes, verify with the tools, '
        'then finish.',
    this.systemPrompt = codingSystemPrompt,
  }) : assert(
          (intents == null) != (runCommand == null),
          'exactly one in-loop verifier per task: intent-graded OR run-graded',
        );

  final String id;
  final String prompt;

  /// Host-seeded files (also oracle artifacts — the host authors them).
  final List<FixtureFile> fixtures;

  /// Final gate (outer oracle, run ONCE after the loop idles).
  final List<CheckerSpec> checkers;

  /// Non-null → intent-graded verifier inside the loop + the intent tool
  /// surface (act_with_project + intent_define/call).
  final List<IntentExpectation>? intents;

  /// Non-null → run-graded verifier inside the loop + the fs_tools surface.
  final List<String>? runCommand;

  /// Repair teaching for the bounded retry prompts (host-authored; NOT new
  /// teaching in the model's context — it only appears on a failing gate).
  final String repairHint;

  final String systemPrompt;

  bool get usesIntentSurface => intents != null;
}

/// The intent-graded oracle sequence (same calls as the suite's `intents`
/// checker — the materialized-Dart final gate replays the identical table).
const _bookmarkIntentCalls = [
  IntentExpectation(
    'save_url',
    args: {'url': 'https://example.dev'},
    expect: {'saved': true},
  ),
  IntentExpectation('save_url', args: {'url': 'https://second.dev'}),
  IntentExpectation('list_saved', expect: {'value': 2}),
  IntentExpectation(
    'save_url',
    args: {'url': 'not-a-url'},
    expect: {'saved': false},
  ),
];

/// The host-authored check program for bugfix_01 — the RUN tool is the
/// in-loop terminal proof; the yaml checkers (`<= n` present, `< n` gone)
/// are the final gate. Host-written: the model never writes test code.
const _bugfix01CheckDart = '''
// Host-authored oracle (not written by the model): runs the target and
// asserts the fixed behavior. exit 0 == goal verified.
import 'loop.dart';

void main() {
  final r = sumTo(3);
  if (r != 6) {
    stderr.writeln('sumTo(3) = \$r, want 6');
    exit(1);
  }
  if (sumTo(1) != 1) {
    stderr.writeln('sumTo(1) != 1');
    exit(1);
  }
}
''';

/// The built-in task set (the J1.4 gate tasks + the free-form shape).
final Map<String, CodingAgentTask> codingAgentTasks = {
  'intent_03_bookmark_macros': CodingAgentTask(
    id: 'intent_03_bookmark_macros',
    prompt:
        'Build a bookmark manager using the macro moves: intent_define '
        '(action define, WITH specs — one move defines an intent AND wires '
        'its whole op chain), act_with_project materialize, then verify by '
        'calling the intents. You never write program code.',
    checkers: [
      CheckerSpec(
        type: 'intents',
        value:
            '{"calls": [{"intent": "save_url", "args": {"url": '
            '"https://example.dev"}, "expect": {"saved": true}}, '
            '{"intent": "save_url", "args": {"url": "https://second.dev"}}, '
            '{"intent": "list_saved", "expect": {"value": 2}}, '
            '{"intent": "save_url", "args": {"url": "not-a-url"}, '
            '"expect": {"saved": false}}]}',
      ),
    ],
    intents: _bookmarkIntentCalls,
    systemPrompt: afmSystemPrompt,
    repairHint:
        'Fix the meaning tree: every intent needs an impl edge to its FIRST '
        'op and a then-chain ending at a return op (action list shows your '
        'ops and ids). If the checker reports a wrong VALUE, the chain runs '
        'but the logic is wrong — re-define that ONE intent with intent_define '
        '(action define, corrected specs; replacing an existing chain is '
        'atomic). If an op is missing props a or b, fix it with set_prop '
        'using the op id. Then materialize and call the intents to verify.',
  ),
  'bugfix_01_off_by_one': CodingAgentTask(
    id: 'bugfix_01_off_by_one',
    prompt:
        'loop.dart contains a function `int sumTo(int n)` that should '
        'return 1+2+...+n but has an off-by-one bug (it returns the wrong '
        'result for n=3). Fix the function so sumTo(3) == 6. Do not change '
        'its signature. Verify with the run tool (dart run check.dart).',
    fixtures: [
      FixtureFile(
        path: 'loop.dart',
        content:
            'int sumTo(int n) {\n  var total = 0;\n'
            '  for (var i = 1; i < n; i++) {\n    total += i;\n  }\n'
            '  return total;\n}\n',
      ),
      FixtureFile(path: 'check.dart', content: _bugfix01CheckDart),
    ],
    checkers: [
      CheckerSpec(type: 'contains', path: 'loop.dart', value: '<= n'),
      CheckerSpec(type: 'not_contains', path: 'loop.dart', value: '< n'),
    ],
    runCommand: ['dart', 'run', 'check.dart'],
    repairHint:
        'Read loop.dart, fix the loop bound with the write tool (the sum '
        'must include n itself), then run `dart run check.dart` with the '
        'run tool — it must exit 0.',
  ),
};

/// A free-form task sentence → run-graded task whose check comes from the
/// **workspace convention** (D8/M0: the criterion lives in the workspace,
/// not in per-task code) — the same implicit oracle pi uses. Resolution:
/// explicit [check] (CLI `--check`) > workspace convention in [workspace] >
/// `dart run main.dart` (the PROVEN bare-file fallback). Throws when nothing
/// resolves — the host must fail honestly, never invent a criterion the
/// workspace does not declare.
CodingAgentTask taskFromSentence(
  String sentence, {
  List<String>? check,
  Directory? workspace,
}) {
  final resolved =
      check ?? (workspace == null ? null : resolveWorkspaceCheck(workspace));
  final command = resolved ?? (workspace == null ? const ['dart', 'run', 'main.dart'] : null);
  if (command == null) {
    throw StateError(
      'no verification criterion resolvable for the workspace at '
      '"${workspace?.path}": no pubspec.yaml, no main.dart, no --check. '
      'Pass --check <command> to declare what "done" means.',
    );
  }
  return CodingAgentTask(
    id: 'free_form',
    prompt: '$sentence Verify with the run tool — the check must exit 0.',
    checkers: [CheckerSpec(type: 'runs', path: command.last)],
    runCommand: command,
  );
}

/// One run's measured result — every published column is carried here.
class CodingAgentRunResult {
  CodingAgentRunResult({
    required this.taskId,
    required this.backend,
    required this.passed,
    required this.finalGate,
    required this.decisions,
    required this.projectionTokens,
    required this.toolRounds,
    required this.moves,
    required this.overheadTokens,
    required this.wallClock,
    required this.nodes,
    required this.edges,
    required this.pulseText,
    required this.recorderDump,
    this.writeGateAudit = '',
  });

  final String taskId;
  final String backend;
  final bool passed;

  /// Final-gate checker results (the outer oracle, run ONCE — final gate
  /// only; in-loop retries consumed AttemptCount instead).
  final List<CheckerResult> finalGate;
  final int decisions;

  /// Honest spend: sum of Situation.tokensUsed per decision (NOT an
  /// estimate of generated text).
  final int projectionTokens;
  final int toolRounds;
  final Map<String, int> moves;
  final int overheadTokens;
  final Duration wallClock;
  final int nodes;
  final int edges;

  /// J1.5.3 observability — shipped on EVERY run, pass or fail.
  final String pulseText;
  final String recorderDump;

  /// P3 (revised): unified diffs of every gated write (review/apply audit).
  /// Empty when no host write gateway was attached.
  final String writeGateAudit;

  String get failureClass {
    if (passed) return '';
    final dump = recorderDump;
    if (dump.contains('identical') && dump.contains('repeated')) {
      return 'loop: repeated identical prompts (see recorder dump)';
    }
    final failed = [
      for (final c in finalGate)
        if (!c.passed) c.detail,
    ];
    return 'final gate: ${failed.join(' | ')}';
  }
}

/// Runs ONE task attempt through the harness: jail + tool surface + goal +
/// verifier INSIDE the loop + ONE `runUntilIdle` (bounded by the J1.5
/// budgets) + final oracle gate. Deterministic for a scripted handler.
Future<CodingAgentRunResult> runCodingAgentOnce({
  required CodingAgentTask task,
  required Directory jail,
  required GenerationHandler handler,
  required String backend,

  /// Called once the run's [FlightRecorder] exists — the driver wires the
  /// SIGINT dump handler here (J1.5.5: even an interrupt leaves a dump).
  void Function(FlightRecorder recorder)? onRecorder,

  /// P3 (revised): HOST write policy. Null (default) = writes apply
  /// immediately — zero behavior change. [WriteGateMode.review] renders a
  /// unified diff for EVERY jail mutation (model writes AND host
  /// materializer output) and asks the approver before bytes land; the
  /// model surface is unchanged (no new parameter, no content model-side).
  /// The audit (all diffs + verdicts) ships in the run log.
  WriteGateMode? writeGateMode,

  /// Only meaningful with [writeGateMode]: true → every diff is approved
  /// (CLI `--auto-approve`); false → interactive y/n on stdin.
  bool autoApprove = false,

  /// Host/test override for the approver (takes precedence over
  /// [autoApprove]); the LLM-free diff-gate test injects a scripted one.
  Future<bool> Function(CapturedWrite write)? writeApprover,

  /// P5: resume — an existing world restored from a snapshot store. The
  /// restored actor is idle-resumable (no open decisions); this runner
  /// re-wires the tool surface, verifier and overseer onto it, seeds NO
  /// fixtures (the workspace already carries the run's state), and
  /// continues the goal from the persisted monotonic budgets.
  World? restoredWorld,

  /// P5: called after every loop session with the live world — the host
  /// persists a snapshot (crash/resume support). Awaited: process exit must
  /// never race a pending save.
  Future<void> Function(World world)? onSnapshot,

  /// M1 dogfooding fix: the world's router (empty for scripted runs). The
  /// actor's model must be resolvable HERE for escalation and capacity —
  /// an empty router silently degrades both.
  ModelRouter? router,

  /// M1 dogfooding fix: the actor must bind a model id the ROUTER knows.
  /// A random `ModelId.create()` resolves to a nameless Model whose client
  /// builder is missing → `initRuntime` throws → the actor never generates
  /// (measured: 3 verification attempts, 0 decisions, FAIL in ~2s).
  ModelId? actorModelId,
}) async {
  final sw = Stopwatch()..start();
  final resume = restoredWorld != null;
  final world = restoredWorld ?? (World()..addPlugin(AgentPlugin()));
  final recorder = FlightRecorder();
  onRecorder?.call(recorder);
  if (!resume) {
    world
      ..upsertResource(ToolRegistryResource())
      ..upsertResource(recorder)
      // B7: the verifier-in-loop policy chain — RunGradedGoalPolicy consumes
      // GoalVerified stamps (maxGoalAttempts bounded), ReActContinuationPolicy
      // is the engine. NO driver-level retry loop.
      ..upsertResource(DecisionFlowResource(defaultGoalFlow()))
      // J2 (ADR 0018): session-per-decision bridge — native accumulation is
      // bounded by the harness round cap × per-round ack size.
      ..upsertResource(AgencyPolicy(maxConcurrent: 1, maxToolRounds: 12))
      ..flush();
  } else {
    world.upsertResource(recorder);
  }

  final meter = DecisionMeter(handler);
  world
    ..upsertResource(GenerationHandlerResource())
    ..getResource<GenerationHandlerResource>().registerDefault(meter);
  // The agency grant reads per-model capacity from the router — scripted
  // runs still need the resource (an empty router = default capacity 1).
  // M1: a REAL router (when the host provides one) must survive here —
  // escalation (resolveEscalatedModel) reads this resource.
  world.upsertResource(ModelRouterResource(router ?? ModelRouter()));

  // Tool surface (B3): fs_tools (read/write/list_dir/glob/grep/run + the
  // P3 git projections) always for run-graded tasks; the intent surface
  // (+ run) for intent tasks.
  final fsRoot = FsToolsRoot(jail.path);
  JailWriteGateway? gateway;
  if (writeGateMode != null) {
    gateway = JailWriteGateway(
      fsRoot,
      mode: writeGateMode,
      approver: writeApprover ?? (autoApprove ? (_) async => true : null),
    );
    fsRoot.writeGateway = gateway;
  }
  if (task.usesIntentSurface) {
    registerIntentClosureTools(world, jail, gateway: gateway);
  } else {
    final registry = ToolRegistry();
    for (final t in fsTools(fsRoot)) {
      registry.register(t);
    }
    world.getResource<ToolRegistryResource>().register('default', registry);
  }

  // Host-seeded fixtures (loop.dart, check.dart, …). NOT re-seeded on
  // resume: the workspace already carries the run's state.
  if (!resume) {
    for (final f in task.fixtures) {
      final file = File('${jail.path}/${f.path}')
        ..parent.createSync(recursive: true);
      file.writeAsStringSync(f.content);
    }
  }

  late final Entity actor;
  Entity? resumedThread;
  if (resume) {
    // The goal-carrying actor comes from the snapshot.
    final carriers = world.query2<Actor, Goal>().toList();
    if (carriers.isEmpty) {
      throw StateError('resume: the snapshot carries no goal-carrying actor');
    }
    actor = carriers.single.$1.entity;
  } else {
    final scene = world.spawnComponents([Scene(), SceneFrame()]);
    actor = world.spawnComponents([
      Actor(agentId: AgentId.create()),
      // M1: bind a model id the router registered — a random id resolves to
      // a nameless Model with no client builder and the actor never generates.
      ActorModel(modelId: actorModelId ?? ModelId.create()),
      ActorSystemPrompt(text: task.systemPrompt),
      ActorThreads(threads: []),
      ActorTools(registryName: 'default'),
      PresentInScene(sceneEntity: scene),
      // The Goal + open decision: the acceptance criteria travel in-frame
      // (ADR 0009) — the verifier stamps GoalVerified against THIS goal.
      Goal(text: task.prompt),
      OpenDecision(prompt: task.prompt),
    ]);
    final thread = spawnThread(world, actor, scene);
    world.upsertComponent(actor, ActorThreads(threads: [thread]));
    world.flush();
    resumedThread = thread;
  }

  // B7: verifier INSIDE the loop + bounded repair attempts.
  //
  // The intent-graded / run-graded verifiers are wired into the schedules:
  // they fire whenever a tool result lands (ToolResultPendingMarker) and
  // stamp GoalVerified, which RunGradedGoalPolicy consumes mid-chain.
  //
  // Native tool-loop caveat (measured, coding_agent_afm_run1.log): the AFM
  // native session runs its WHOLE ReAct chain inside ONE decision, so no
  // pending-result marker fires after the model closes that decision — the
  // loop would idle with the goal unverified and ZERO attempts consumed
  // (the exact J1.4 failure shape). The repair loop below is therefore NOT
  // an unbounded while(true): each repair is a fresh host-injected decision
  // (openFreshDecision — the ONLY budget-reset path, J1.5.2) that consumes
  // the monotonic AttemptCount against maxGoalAttempts (J1.5.1), and the
  // mechanical oracle re-grades after every session. Exhaustion stamps
  // GoalAttemptsExhausted (the J8 rung 1 terminal record).
  if (task.usesIntentSurface) {
    wireIntentGradedGoal(world, sequence: task.intents!);
  } else {
    wireRunGradedGoal(world, command: task.runCommand!, cwd: jail.path);
  }

  // J7: the overseer watches for goal-attempt exhaustion and disposes
  // (approve / repair(intent, notes) / escalate) — wired for the intent
  // surface, whose gate failures are meaning-native (the chain-dump brief).
  if (task.usesIntentSurface) {
    wireOverseer(world, moverActor: actor, maxCycles: 1);
  }

  const maxGoalAttempts = 3;
  // P5: the monotonic attempt budget persists across restarts — a resumed
  // run continues where the counter stopped (never a reset).
  var attempt = resume
      ? (world.getEntity(actor).$1.get<AttemptCount>()?.value ?? 0)
      : 0;
  List<CheckerResult> grade() => [
    for (final c in task.checkers) evaluateChecker(c, jail.path),
  ];
  var finalGate = grade();
  var passed = finalGate.isNotEmpty && finalGate.every((c) => c.passed);
  while (!passed && attempt < maxGoalAttempts) {
    attempt++;
    // Uniform budget accounting: the policy increments AttemptCount on the
    // marker path; the driver increments it on the native-session path.
    // Same monotonic component, same cap — no double reset.
    world.getEntity(actor).$1.insert(AttemptCount(attempt));
    world.flush();
    openFreshDecision(
      world,
      actor,
      prompt: resume && attempt == 1
          ? 'You were restored from a snapshot (previous attempt did not '
              'satisfy verification).\nFailing:\n'
              '${[for (final c in finalGate) if (!c.passed) c.detail].join("\n")}\n\n'
              '${task.repairHint}\n\nOriginal task:\n${task.prompt}'
          : 'Your previous attempt did not satisfy verification (attempt '
              '$attempt/$maxGoalAttempts).\nFailing:\n'
              '${[for (final c in finalGate) if (!c.passed) c.detail].join("\n")}\n\n'
              '${task.repairHint}\n\nOriginal task:\n${task.prompt}',
    );
    await HarnessLoop(world: world).runUntilIdle();
    finalGate = grade();
    passed = finalGate.isNotEmpty && finalGate.every((c) => c.passed);
    await onSnapshot?.call(world);
  }
  await onSnapshot?.call(world);
  if (!passed) {
    // J8 rung 1 record FIRST: for NATIVE sessions the policy path cannot
    // fire (no ToolResultPendingMarker — tools execute inside the native
    // ReAct chain), so the DRIVER stamps the terminal record. The J7
    // overseer window below keys off exactly this stamp.
    if (world.query2<Actor, GoalAttemptsExhausted>().toList().isEmpty) {
      world.getEntity(actor).$1.insert(
        GoalAttemptsExhausted(
          'goal_unverifiable: $attempt failed verification attempts '
          '(budget $maxGoalAttempts). Last failure: '
          '${[for (final c in finalGate) c.detail].join(" | ")}',
        ),
      );
      world.flush();
    }
    // J7: the exhaustion stamp alone leaves NO open work — runUntilIdle
    // would exit before the scheduled system ticks. Spawn the overseer
    // explicitly, then give the disposition + (granted) repair one bounded
    // session. Ledger guards keep it to one cycle.
    OverseerLedger? ledger;
    try {
      ledger = world.getResource<OverseerLedger>();
    } on StateError {
      // overseer not wired → base ladder only
    }
    if (ledger != null && ledger.canAct) {
      maybeSpawnOverseer(world);
      await HarnessLoop(world: world).runUntilIdle();
      finalGate = grade();
      passed = finalGate.isNotEmpty && finalGate.every((c) => c.passed);
      await onSnapshot?.call(world);
    }
  }
  if (!passed) {
    // The overseer window ran (approve/escalate/repair_denied) or the
    // granted repair failed again — make sure the structured terminal
    // record ships.
    if (world.query2<Actor, GoalAttemptsExhausted>().toList().isEmpty) {
      world.getEntity(actor).$1.insert(
        GoalAttemptsExhausted(
          'goal_unverifiable: $attempt failed verification attempts '
          '(budget $maxGoalAttempts, overseer window spent). Last failure: '
          '${[for (final c in finalGate) c.detail].join(" | ")}',
        ),
      );
      world.flush();
    }
  }

  // K columns from the durable thread record.
  final moves = <String, int>{};
  var toolRounds = 0;
  final activeThread =
      resumedThread ??
      world.getEntity(actor).$1.get<ActorThreads>()?.threads.firstOrNull;
  final threadEntity = activeThread;
  for (final beat in (threadEntity == null
          ? const <Entity>[]
          : world.getResource<FacetIndex>().beatsOfThread(threadEntity))
      .toList()) {
    final we = world.getEntity(beat).$1;
    final call = we.get<BeatToolCall>();
    if (call == null) continue;
    toolRounds++;
    final action = call.args['action'];
    moves.update(
      action is String ? '${call.name}.$action' : call.name,
      (v) => v + 1,
      ifAbsent: () => 1,
    );
  }
  final view = meaningView(world);
  // Overhead measured over the SAME surface the actor saw (one truth: the
  // registry, not a rebuilt list).
  final seenTools = world.getResource<ToolRegistryResource>().get('default');
  final overhead = overheadTokens(
    systemPrompt: task.systemPrompt,
    tools: seenTools?.tools.values.toList() ?? const [],
  );
  sw.stop();

  return CodingAgentRunResult(
    taskId: task.id,
    backend: backend,
    passed: passed,
    finalGate: finalGate,
    decisions: meter.decisions,
    projectionTokens: meter.projectionTokens,
    toolRounds: toolRounds,
    moves: moves,
    overheadTokens: overhead,
    wallClock: sw.elapsed,
    nodes: view.nodeCount,
    edges: view.edgeCount,
    pulseText: sampleHarness(world, tick: meter.decisions).toText(),
    recorderDump: recorder.dump(),
    writeGateAudit: gateway == null
        ? ''
        : 'writes applied: ${gateway.appliedCount}, '
            'rejected: ${gateway.rejectedCount}\n'
            '${gateway.renderDiffs()}',
  );
}

/// Formats one run as its honest log body (B8: every run ships the pulse +
/// flight-recorder dump, pass or fail).
String formatRunLog(CodingAgentRunResult r) => '''
coding_agent run — task: ${r.taskId}
  backend: ${r.backend}
  verdict: ${r.passed ? 'PASS' : 'FAIL'}
  overhead tokens (system+schemas): ${r.overheadTokens}
  decisions: ${r.decisions}
  tool rounds (thread beats): ${r.toolRounds}
  moves: ${r.moves}
  projection tokens (honest spend, Situation.tokensUsed): ${r.projectionTokens}
  meaning nodes: ${r.nodes}, edges: ${r.edges}
  wall clock: ${r.wallClock.inMilliseconds} ms
  final gate (outer oracle, once): ${r.passed ? 'PASS' : 'FAIL'}
${[
  for (final c in r.finalGate) '    check: ${c.detail}',
].join('\n')}
  failure class: ${r.failureClass.isEmpty ? '-' : r.failureClass}
--- harness pulse (J1.5.3) ---
${r.pulseText}
--- flight recorder ---
${r.recorderDump}${r.writeGateAudit.isEmpty ? '' : '\n--- write-gate audit (P3) ---\n${r.writeGateAudit}'}
''';

/// The pass@k summary row (K discipline: backend, n, pass@k, tokens source,
/// moves/task). NEVER a single-run claim.
String formatSummary({
  required String backend,
  required String taskId,
  required int runs,
  required int passes,
  required List<CodingAgentRunResult> results,
}) {
  final tokenTotals = [
    for (final r in results) r.projectionTokens,
  ];
  final decisionTotals = [
    for (final r in results) r.decisions,
  ];
  final moveTotals = [
    for (final r in results) r.moves.values.fold(0, (a, b) => a + b),
  ];
  final overflowRuns = [
    for (final (i, r) in results.indexed)
      if (r.pulseText.contains('overflow') ||
          r.recorderDump.contains('context overflow'))
        i + 1,
  ];
  return 'summary — task: $taskId | backend: $backend | n: $runs | '
      'passed: ${results.where((r) => r.passed).length} | '
      'pass@$runs: ${results.where((r) => r.passed).length}/$runs | '
      'tokens source: Situation.tokensUsed (projection) | '
      'tokens/run: $tokenTotals | decisions/run: $decisionTotals | '
      'moves/run: $moveTotals | '
      'context overflows: ${overflowRuns.isEmpty ? "0" : "runs $overflowRuns"}';
}

/// Resolve the evidence directory (K4): raw logs to `benchmark/runs/`.
/// Candidates: ./benchmark/runs (harness package cwd), the sibling harness
/// package (when run from xsoulspace_inference_apple_foundation), or a
/// created ./benchmark/runs as a last resort.
Directory resolveRunsDirectory() {
  final candidates = [
    Directory('benchmark/runs'),
    Directory('../xsoulspace_agentic_harness/benchmark/runs'),
    Directory('../../xsoulspace_agentic_harness/benchmark/runs'),
  ];
  for (final d in candidates) {
    if (d.existsSync()) return d;
  }
  return Directory('benchmark/runs')..createSync(recursive: true);
}

/// Appends [body] to the per-run log file (K4 naming).
File writeRunLog(Directory runsDir, String name, String body) {
  final f = File('${runsDir.path}/$name');
  f.writeAsStringSync(
    '${f.existsSync() ? f.readAsStringSync() : ''}$body\n',
    mode: FileMode.write,
  );
  return f;
}

/// Parses `--flag value` / `--flag` style CLI args.
Map<String, String?> parseCliArgs(List<String> args) {
  final positional = <String>[];
  final named = <String, String?>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a.startsWith('--')) {
      final next = i + 1 < args.length ? args[i + 1] : null;
      if (next != null && !next.startsWith('--')) {
        named[a.substring(2)] = next;
        i++;
      } else {
        named[a.substring(2)] = null;
      }
    } else {
      positional.add(a);
    }
  }
  return {'_positional': positional.isEmpty ? null : positional.first,
    ...named};
}

/// jsonEncode helper for logs (keeps the summary row one line).
String summaryLine(Map<String, Object?> row) => jsonEncode(row);
