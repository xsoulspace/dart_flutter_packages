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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xsoulspace_agentic_harness/benchmark_api.dart'
    show
        CheckerResult,
        CheckerSpec,
        RunGoalCommand,
        VerifyTierPlanner,
        dartVerifyConvention,
        derivePerPackageVerify,
        sessionTouchedFiles,
        FixtureFile,
        defaultGoalFlow,
        openFreshDecision,
        wireIntentGradedGoal,
        wireRunGradedGoal,
        declareCheckTool,
        wireOverseer,
        maybeSpawnOverseer,
        OverseerLedger,
        IntentExpectation,
        evaluateChecker;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_agentic_harness/src/tooling/workspace_map.dart'
    show WorkspaceMapProvider;
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart'
    show
        fsTools,
        FsToolsRoot,
        CapturedWrite,
        JailWriteGateway,
        WriteGateMode;
import 'package:xsoulspace_agentic_harness/src/systems/deferred_task_policy.dart'
    show
        DeferredTaskAccounting,
        DeferredTaskPolicy,
        DeferredVerifyEntry,
        DeferredVerifyPool,
        completeDeferredVerify;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart'
    show EnvConfig;
import 'package:xsoulspace_agentic_harness/src/decisions/step_resolver.dart'
    show
        AmbiguousStep,
        HostVerbStep,
        ReadyStep,
        TierRoutedStep,
        ambiguousStepDirective,
        readyStepDirective,
        resolveTaskPrompt,
        spawnResolvedStep;
import 'package:xsoulspace_agentic_harness/src/tools/task_grammar.dart'
    show executableDecisionForTask, parseTaskSentence, TaskGrammarMatch;
import 'package:agentic_executables_wire/agentic_executables_wire.dart'
    show EditExecutableWire;

import 'derived_context.dart'
    show DerivedContextLimits, deriveContextRow;
import 'intent_closure_runner.dart'
    show DecisionMeter, afmSystemPrompt, registerIntentClosureTools;
import 'meaning_profile_surface.dart'
    show buildMeaningProfileSurface;
// ADR 0003 — conditional workspace import: on the web target the honest
// stub (agentic_workspace_web_stub.dart) replaces the workspace barrel, so
// its dart:io edit/ETL tier stays OUT of the web graph. VM/macOS: the real
// import, unchanged.
import 'package:xsoulspace_agentic_workspace/xsoulspace_agentic_workspace.dart'
    if (dart.library.js_interop) 'agentic_workspace_web_stub.dart'
    show SpanEditPlan;

/// ~110 tokens — the run-graded (fs_tools) teaching prompt. B6: teaching
/// lives in tool descriptions + the system prompt ONLY.
///
/// R7b DEMOTION (ADR 0023): this run-graded fs arm is LEGACY-HOST-ONLY —
/// direct-profile hosts keep it; the meaning profile edits through
/// `edit_symbol` (the span materializer) and never sees `write`. Do not
/// add new tasks/surfaces to this arm; new work routes through the
/// meaning profile ([CodingAgentTask.meaningProfile]).
const codingSystemPrompt =
    'You build or fix Dart code inside the workspace. You never leave it. '
    'Tools: read, write, list_dir, glob, grep, run.\n'
    'Flow: 1) read the files you need (read/list_dir/glob/grep). 2) make '
    'the change with write. 3) run the target program with the run tool — '
    'it must exit 0. A mechanical verifier runs the goal check after your '
    'tool results; when it reports a failure, fix the code and try again. '
    'Keep going until the check passes. Finish by stating what you changed.';

/// The meaning-profile teaching prompt (R7): the actor scans the workspace
/// into the meaning tree, reads it budgeted, and edits through meaning
/// moves. It never reads a file and never writes code tokens.
///
/// fs tier (ADR 0024, as amended): the map-graph covers EVERY file —
/// mapped classes (md/yaml/json) have section/keypath sub-nodes; point zoom
/// on an anchor reads its span (budgeted). Text NEVER enters context as a
/// whole file or line window. Non-code files mutate ONLY through
/// `write_review` (consent-gated escape hatch; a reject never lands);
/// code moves through `edit_symbol` only.
const meaningProfileSystemPrompt =
    'Edit code through the meaning tree — no file reads, no code '
    'tokens. ONE tool call per decision: after the result, end the '
    'turn; next decision gets a fresh cut. Flow: 1) repo_etl scan '
    '(once). 2) READ in ONE call: meaning_program — ops: locate(query) '
    'sets the cursor; zoom/impact/read consume it (focusId overrides); '
    'read serves the span through the node\'s own class. 3) ACT: '
    'edit_symbol (symbolId from a cut) for code; write_review only for '
    'non-code (human consents; never Dart). Bounces name valid ids. '
    'Moves verify and auto-revert. Finish when green.';

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
    this.meaningProfile = false,
    this.readOnly = false,
    this.repairHint =
        'Fix the workspace so the check passes, verify with the tools, '
        'then finish.',
    this.systemPrompt = codingSystemPrompt,
  }) : assert(
         (intents == null) != (runCommand == null) || meaningProfile,
         'exactly one in-loop verifier per task: intent-graded OR run-graded',
       );

  final String id;
  final String prompt;

  /// ADR 0027 §1: the delegator DECLARED this a read task (host-declared
  /// data, never inferred from laziness). The actor runs and streams its
  /// reads, but no verifier is wired and the final gate is stamped
  /// `read_only_not_applicable` — recorded as data, excluded from
  /// pass-rate columns. Mutation tasks can NEVER take this flag.
  final bool readOnly;

  /// Host-seeded files (also oracle artifacts — the host authors them).
  final List<FixtureFile> fixtures;

  /// Final gate (outer oracle, run ONCE after the loop idles).
  final List<CheckerSpec> checkers;

  /// Non-null → intent-graded verifier inside the loop + the intent tool
  /// surface (act_with_project + intent_define/call).
  final List<IntentExpectation>? intents;

  /// Non-null → run-graded verifier inside the loop + the fs_tools surface.
  /// LEGACY-HOST-ONLY (R7b demotion, ADR 0023): direct-profile hosts keep
  /// whole-file writes; the meaning profile must not gain them back.
  final List<String>? runCommand;

  /// R7: the meaning-profile surface — [repo_etl, meaning_program,
  /// edit_symbol, run] (ADR 0030 §3 graduation). Zero `read`, zero
  /// `write`: the
  /// tree is the code interface, `edit_symbol` is the only ACT verb. The
  /// workspace convention stays the gate (run-graded).
  final bool meaningProfile;

  /// Repair teaching for the bounded retry prompts (host-authored; NOT new
  /// teaching in the model's context — it only appears on a failing gate).
  final String repairHint;

  final String systemPrompt;

  bool get usesIntentSurface => intents != null;
  bool get usesMeaningSurface => meaningProfile && intents == null;
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
  bool meaningProfile = false,
  bool readOnly = false,
}) {
  final resolved =
      check ?? (workspace == null ? null : resolveWorkspaceCheck(workspace));
  final command =
      resolved ??
      (workspace == null ? const ['dart', 'run', 'main.dart'] : null);
  if (command == null) {
    throw StateError(
      'no verification criterion resolvable for the workspace at '
      '"${workspace?.path}": no pubspec.yaml, no main.dart, no --check. '
      'Pass --check <command> to declare what "done" means.',
    );
  }
  return CodingAgentTask(
    id: 'free_form',
    prompt: meaningProfile
        ? '$sentence Work through the meaning tree: repo_etl scan, '
              'the meaning_program read ops to read, edit_symbol to act '
              'on code, write_review for non-code files (the human '
              'consents). Never touch files directly.'
        : '$sentence Verify with the run tool — the check must exit 0.',
    // ADR 0027: host-declared read task — no oracle, no grade.
    readOnly: readOnly,
    // R7: the meaning profile — the tree is the only code interface.
    meaningProfile: meaningProfile,
    systemPrompt: meaningProfile
        ? meaningProfileSystemPrompt
        : codingSystemPrompt,
    // The final gate mirrors the SAME command the in-loop verifier runs
    // ('runs' checkers default to `dart run <path>` — an override value is
    // required for non-run commands like `dart analyze`).
    checkers: [
      CheckerSpec(type: 'runs', path: command.last, value: command.join(' ')),
    ],
    runCommand: command,
  );
}

/// P2 — the TASK-GRAMMAR PRE-PASS, retired INTO the frontier resolver
/// (ADR 0009 Amendment 2026-09-08 — NO parallel pre-pass): the ONE
/// mechanical resolver ([resolveTaskPrompt]) covers the grammar verbs
/// (pack executables), the prompt-named anchors (md sections / yaml
/// keypaths / backticked symbol+executable — the wave rows 2–4 class),
/// and bounces with REAL candidate ids when resolution is ambiguous. The
/// ready decision is host-injected (the row-1 pattern, pass@1 ×3
/// on-device): the actor CARRIES the move, never composes ids.
///
/// The tree must exist for the resolution; a fresh world has none, and a
/// parse hit justifies the host-side scan (mechanical, zero tokens — the
/// same ETL the actor would run as its first move anyway).
Future<String?> taskGrammarPrepass(
  World world,
  ToolDef etl,
  String taskPrompt,
) async {
  if ((world.maybeGetResource<MeaningIndex>()?.nodeCount ?? 0) == 0) {
    await etl.execute({'action': 'scan'});
  }
  final resolution = resolveTaskPrompt(world, taskPrompt);
  switch (resolution) {
    case final ReadyStep ready:
      // The resolved step lands on the frontier as graph data (claim +
      // resolved StepAction + classification) — the projection/metrics
      // and the mechanical actor read it from the tree, never from prose.
      spawnResolvedStep(world, ready, claim: taskPrompt);
      return readyStepDirective(ready);
    case final AmbiguousStep ambiguous:
      // TOTAL-or-bounce: the bounce carries REAL candidate ids — the
      // model picks one or zooms; it never invents an id.
      return ambiguousStepDirective(ambiguous);
    case HostVerbStep() || TierRoutedStep():
      // The host verb (run) owns it / no mechanical pattern covers the
      // sentence — the normal decision path is the right surface.
      return null;
  }
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
    this.attemptsExhausted = false,
    required this.nodes,
    required this.edges,
    required this.pulseText,
    required this.recorderDump,
    this.writeGateAudit = '',
    this.toolResults = const [],
    this.verifyWallMs = 0,
    // ADDITIVE (the deferred-task law, item 3): accounting on the task
    // outcome. Zero/empty when deferral is not wired (the disabled
    // fallback runs the legacy inline verify — nothing to account).
    this.deferralRate = 0,
    this.deferredVerifyBeats = 0,
    this.deferredVerifyDefects = const [],
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

  /// R7 transparency: the tool RESULT texts recorded on this run's beats
  /// (name + output excerpt, in order). The daemon streams these so an ACP
  /// client sees not just "edit_symbol completed" but WHAT the host did —
  /// patches, verify tier verdicts, bounce reasons, auto-reverts.
  final List<String> toolResults;

  /// P3 (revised): unified diffs of every gated write (review/apply audit).
  /// Empty when no host write gateway was attached.
  final String writeGateAudit;

  /// J8 rung 1: the monotonic attempt budget exhausted and the mechanical
  /// oracle still fails — the terminal record the escalation ladder keys off.
  final bool attemptsExhausted;

  /// P1 BUDGET LAW: the wall of the FINAL gate's verification work
  /// (analyzer-before-tests + the convention/steps runs), reported in the
  /// verdict so a dart-turn budget miss is visible on every verify —
  /// never a silent cost. 0 when no gate ran (read-only tasks).
  final int verifyWallMs;

  /// ADDITIVE (the deferred-task law): deferred share of verify-shaped
  /// requests ([DeferredTaskAccounting.deferralRate]); 0 when unwired.
  final double deferralRate;

  /// ADDITIVE: completion beats landed on requesting actors' threads by
  /// the pooled verify ([DeferredTaskAccounting.completionBeats]).
  final int deferredVerifyBeats;

  /// ADDITIVE: the named defects of THIS outcome — a deferral that never
  /// produced its verification beat ([DeferredTaskAccounting
  /// .namedDefects]). Empty when every deferral kept its beat contract.
  final List<String> deferredVerifyDefects;

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

  /// M0b: register the `declare_check` tool — the actor may propose its own
  /// verification command as data; the host validates the shape (allowlist,
  /// no shell metacharacters) and the verifier executes mechanically.
  bool allowDeclaredChecks = false,

  /// Escalation rung (N4): widened attempt allowance for a guidance round.
  /// Monotonic within the session: callers must never LOWER it.
  int maxGoalAttempts = 3,

  /// R7c item 3: HOST edit approver for the meaning profile — every
  /// `edit_symbol` move asks this approver before any byte lands
  /// (deny-by-default; the daemon routes it to the ACP client).
  Future<bool> Function(SpanEditPlan plan)? editApprover,

  /// P1 trusted-author tier: the PACK-WRITE consent gate for authored-body
  /// pack executables ([SpanEditMaterializer.packConsent]). The daemon
  /// threads a SYNC consent-plan answer here (the pack load loop inside
  /// `editSymbolTool` is synchronous — the async ACP permission
  /// round-trip cannot reach it): a plan allowing `pack_write` over the
  /// pack path consents at registration; no plan / exhausted uses / no
  /// match → false (the entry skips as named data — never a crash).
  bool Function(EditExecutableWire wire, String authoredBodyDiff)?
  packConsent,

  /// R4 — large-model tier: wider cut (observations 24) + raised projection
  /// budget (32k). Same slot semantics, scaled capacities — the
  /// amplification delta is then a measurement, not an illustration.
  bool largeContextProfile = false,

  /// R1/AFM — small-window tier: leanest cut (observations 4) so system +
  /// tool schemas + working set + observations fit AFM's ~4k window under
  /// the pre-flight `maxContextTokens` guard.
  bool leanContextProfile = false,

  /// R7 transparency (parallel hygiene): called MID-TURN as each tool
  /// result lands — the host observes the actor's thread for new
  /// [ToolResultContent] beats while the loop runs instead of emitting at
  /// run end, so a 30–60s tool call is never silent. Emission-only: the
  /// poller never mutates the world.
  void Function(String toolName, Object? output)? onToolResult,
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
      // ADR 0020: the coder cut composition — goal/map/observations/verdict
      // slots with dedup + drop-empty; required slots input-gated. The map
      // slot is fed by the workspace map provider (fs-as-graph v1).
      // R4: the large-model tier scales the cut + budget for 200k-class
      // models; identical slot semantics.
      ..upsertResource(
        CutCompositionResource(
          largeContextProfile
              ? CutComposition.coderLarge()
              : leanContextProfile
              ? CutComposition.coderLean()
              : CutComposition.coder(),
          mapProvider: WorkspaceMapProvider(
            jail.path,
            maxDepth: leanContextProfile ? 1 : 2,
            maxEntries: leanContextProfile ? 16 : 30,
          ).map,
        ),
      )
      ..upsertResource(
        ProjectionBudget(tokens: largeContextProfile ? 32000 : 4000),
      )
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
  // P2 — task-grammar pre-pass result (the ready apply_executable decision
  // data when the sentence parses to the structured grammar AND a pack
  // executable matches; null → the normal decision path). Computed below
  // for meaning-profile runs, threaded into the goal frame at spawn.
  String? grammarDirective;
  JailWriteGateway? gateway;
  if (writeGateMode != null) {
    gateway = JailWriteGateway(
      fsRoot,
      mode: writeGateMode,
      approver: writeApprover ?? (autoApprove ? (_) async => true : null),
    );
    fsRoot.writeGateway = gateway;
  }
  final declaredChecks = <String, List<String>>{};
  if (task.usesIntentSurface) {
    registerIntentClosureTools(world, jail, gateway: gateway);
  } else if (task.usesMeaningSurface) {
    // R7 meaning profile, GRADUATED (ADR 0030 §3, 2026-09-07): repo_etl +
    // meaning_program + edit_symbol + (write_review) + run — the program
    // REPLACED the locate/zoom/impact verbs. NO read, NO write, NO
    // fs_tools — the tree is the only code interface. ADR 0033 §2: the
    // surface is built by the ONE-TRUTH builder (`buildMeaningProfileSurface`)
    // shared with the overhead gate — the metered registry and the wired
    // registry can no longer drift.
    final surface = await buildMeaningProfileSurface(
      world: world,
      workspace: jail,
      fsRoot: fsRoot,
      gateway: gateway,
      editApprover: editApprover,
      packConsent: packConsent,
    );
    world.getResource<ToolRegistryResource>().register(
      'default',
      surface.registry,
    );
    // ADR 0033 §1 — the derived context equation (AFM tier only: the
    // constants are the measured AFM window; the large tier derives
    // against its own window in a later row). The cut budget is DERIVED
    // from the LIVE registry (never a constant): window(native) −
    // native-truth overhead − output reserve − margin. When the derived
    // budget cannot fund a cut, the run proceeds with the honest 0-budget
    // (the pre-flight bounces named) — the repair is surface convergence
    // (ADR 0030), never a bigger constant.
    if (leanContextProfile) {
      // ADR 0033 §1 as amended — the limits are CONFIGURABLE per backend
      // (ADR 0008 EnvConfig: process env → ./.xsoulspace/config.json →
      // global). AFM ships the measured defaults (4,096 / 1,024 / 1.45);
      // an OpenRouter model sets derived_context_window_tokens (and
      // friends) and the SAME equation derives that tier's cut budget.
      // Per-backend scoping: derived_context_window_tokens_<backend>.
      final config = await EnvConfig.load(
        localPath:
            EnvConfig.discoverLocalPath(start: jail.path) ??
            EnvConfig.defaultLocalPath(),
      );
      final limits = DerivedContextLimits.resolve(
        config: config,
        backend: backend,
      );
      final derivation = deriveContextRow(
        overheadTokens: overheadTokens(
          systemPrompt: task.systemPrompt,
          tools: surface.registry.tools.values.toList(),
        ),
        nativeWindowTokens: limits.windowTokens,
        outputReserveTokens: limits.outputReserveTokens,
        nativeTruthFactor: limits.nativeTruthFactor,
        marginFraction: limits.marginFraction,
        minCutTokens: limits.minCutTokens,
      );
      // ignore: avoid_print
      print(
        '[derived-context] backend=$backend window=${derivation.window} '
        'reserve=${derivation.reserve} '
        'nativeTruth=${derivation.nativeTruthFactor} '
        'nativeOverhead=${derivation.nativeOverhead} '
        'margin=${derivation.margin} '
        '→ cutBudget=${derivation.derivedBudget} '
        'fits=${derivation.fits}',
      );
      world.upsertResource(ProjectionBudget(tokens: derivation.derivedBudget));
    }
    world
      // ADR 0033 §4 — the decision ends MECHANICALLY after the move: the
      // native inline loop finishes the generation on the first tool
      // result instead of trusting the model to end its turn.
      ..upsertResource(NativeLoopPolicy(endAfterFirstTool: true))
      ..flush();
    // P2 — the pre-pass runs AFTER the tool surface exists (the tree may
    // have been refreshed above) and BEFORE the actor's first decision:
    // host-side, zero model tokens, zero decisions.
    grammarDirective = await taskGrammarPrepass(world, surface.etl, task.prompt);
  } else {
    final registry = ToolRegistry();
    for (final t in fsTools(fsRoot)) {
      registry.register(t);
    }
    if (allowDeclaredChecks) {
      registry.register(
        declareCheckTool(
          declaredChecks: declaredChecks,
          registryName: 'default',
        ),
      );
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
    // P2 — the pre-pass decision data rides the goal frame: ONE decision
    // carries it verbatim; without a parse hit the frame is untouched.
    // The ready move LEADS (R7e/afm_wave lesson: the model reads the first
    // line; the task sentence follows as context).
    final goalText = grammarDirective == null
        ? task.prompt
        : '$grammarDirective\n\nOriginal task: ${task.prompt}';
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
      Goal(text: goalText),
      OpenDecision(prompt: goalText),
    ]);
    final thread = spawnThread(world, actor, scene);
    world.upsertComponent(actor, ActorThreads(threads: [thread]));
    world.flush();
    resumedThread = thread;
  }

  // R7 transparency: MID-TURN tool-result streaming. A 40ms observer
  // polls the actor's thread for new [ToolResultContent] beats and emits
  // them as they land (ECS queries are microseconds; the poller only
  // reads). This replaces the old emit-at-run-end copy — a long `run` or
  // `edit_symbol` verify now streams into the ACP session while it
  // executes.
  final pollThread =
      resumedThread ??
      world.getEntity(actor).$1.get<ActorThreads>()?.threads.firstOrNull;
  final emittedBeats = <Entity>{};
  Timer? resultPoller;
  if (onToolResult != null && pollThread != null) {
    resultPoller = Timer.periodic(const Duration(milliseconds: 40), (_) {
      for (final beat
          in world
              .getResource<FacetIndex>()
              .beatsOfThread(pollThread)
              .toList()) {
        if (!emittedBeats.add(beat)) continue;
        final result = world.getEntity(beat).$1.get<ToolResultContent>();
        if (result != null) onToolResult(result.name, result.output);
      }
    });
  }
  try {
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
    // ADR 0027: read-only tasks wire NO verifier — reads have no oracle
    // (the zoom cut IS the answer); the gate would be theater.
    if (task.readOnly) {
      // no verifier wiring — the loop runs to idle and the turn ends.
    } else if (task.usesIntentSurface) {
      wireIntentGradedGoal(world, sequence: task.intents!);
    } else if (task.usesMeaningSurface) {
      // The workspace convention is the gate (D8); explicit runCommand wins
      // when the delegator declared one.
      final command =
          task.runCommand ??
          resolveWorkspaceCheck(jail) ??
          (throw StateError(
            'meaning-profile task: no verification criterion resolvable for '
            '${jail.path} — pass runCommand or declare a workspace convention',
          ));
      wireRunGradedGoal(
        world,
        command: command,
        cwd: jail.path,
        // Tiered verification (the 20–23s fix): skip grades with no new
        // move, narrow to frontier-selected tests; the full suite stays
        // the terminal proof at the final gate.
        // Tiered verification is HARNESS machinery (verify_tiers.dart): the
        // beat-derived stateless planner; the dart convention is data.
        planProvider: const VerifyTierPlanner(convention: dartVerifyConvention),
      );
    } else {
      wireRunGradedGoal(
        world,
        command: task.runCommand!,
        cwd: jail.path,
        commandByRegistry: declaredChecks.isEmpty ? null : declaredChecks,
      );
    }

    // J7: the overseer watches for goal-attempt exhaustion and disposes
    // (approve / repair(intent, notes) / escalate) — wired for the intent
    // surface, whose gate failures are meaning-native (the chain-dump brief).
    if (task.usesIntentSurface) {
      wireOverseer(world, moverActor: actor, maxCycles: 1);
    }

    // P5: the monotonic attempt budget persists across restarts — a resumed
    // run continues where the counter stopped (never a reset).
    var attempt = resume
        ? (world.getEntity(actor).$1.get<AttemptCount>()?.value ?? 0)
        : 0;

    /// P1 (ADR 0009/0023) — PER-PACKAGE FINAL GATE derivation: the ACTIVE
    /// packages come from the session's own touched-file beats, resolved
    /// fresh at every grade. Null (no touched files, root-level files,
    /// 3+ packages, an unresolvable convention, or a non-convention gate)
    /// → the root checkers run unchanged — never a skipped gate.
    List<RunGoalCommand>? deriveVerifySteps() {
      final isSingleRunsGate =
          task.checkers.length == 1 && task.checkers.single.type == 'runs';
      if (!isSingleRunsGate) return null;
      return derivePerPackageVerify(
        workspaceRoot: jail.path,
        touchedFiles: sessionTouchedFiles(world, dartVerifyConvention),
        convention: dartVerifyConvention,
      );
    }

    /// ADR 0027 §2 — analyzer-before-tests: when the gate is a test
    /// command and the jail has a resolved package config, a full
    /// `dart analyze` runs FIRST. An analyze failure IS the failure data
    /// (named, with the analyzer output) and skips the ~20–40s test
    /// compile. The oracle is invoked less, never diluted. Skipped
    /// honestly when the jail has no package config (bare fixtures).
    /// P1: with the per-package derivation active, the analyzer runs IN
    /// each ACTIVE package (fail fast on the package that changed), never
    /// at the monorepo root.
    Future<List<CheckerResult>?> analyzeBeforeTests() async {
      final steps = deriveVerifySteps();
      final isTestGate =
          steps != null ||
          task.checkers.any(
            (c) =>
                c.type == 'runs' &&
                (c.value?.startsWith('dart test') ?? false ||
                    (c.value?.startsWith('flutter test') ?? false)),
          );
      if (!isTestGate) return null;
      if (!File('${jail.path}/.dart_tool/package_config.json').existsSync()) {
        return null;
      }
      final analyzeTargets = steps == null
          ? [jail.path]
          : [for (final s in steps) '${jail.path}/${s.cwd}'];
      for (final dir in analyzeTargets) {
        final analyze = await Process.run(
          'dart',
          ['analyze'],
          workingDirectory: dir,
        );
        if (analyze.exitCode != 0) {
          return [
            CheckerResult(
              passed: false,
              detail:
                  'analyzer_before_tests: dart analyze exit '
                  '${analyze.exitCode} in $dir — tests not run (fail fast).\n'
                  '${analyze.stdout}\n${analyze.stderr}',
            ),
          ];
        }
      }
      return null; // clean — run the tests
    }

    List<CheckerResult> grade() {
      final steps = deriveVerifySteps();
      if (steps != null) {
        return [for (final s in steps) _runVerifyStep(s, jail.path)];
      }
      return [for (final c in task.checkers) evaluateChecker(c, jail.path)];
    }

    // THE ACTOR ALWAYS GETS ITS FIRST SESSION — R7 daemon finding: a
    // workspace whose gate is ALREADY green must not silently skip the
    // turn (decisions 0): the actor may still need to act (scan / zoom /
    // edit directives), and a task is not "done" before the actor ran.
    // Measured on the R7 daemon gate: without this, an already-green
    // workspace graded PASS with zero work.
    if (!resume) {
      await HarnessLoop(world: world).runUntilIdle();
    } else {
      // Resumed actor: idle-resumable, so the new prompt needs an open
      // decision even when the gate already passes.
      openFreshDecision(
        world,
        actor,
        prompt:
            '${task.prompt}\n\n(Continuing a restored session — the gate '
            'currently passes; do any work the task still needs, or state '
            'what you changed.)',
      );
      await HarnessLoop(world: world).runUntilIdle();
    }

    // ADR 0027 §1: read-only tasks stream their reads and end — the gate
    // is honestly stamped not-applicable (the task DECLARED itself a
    // read; laziness cannot manufacture this, only the delegator can).
    List<CheckerResult> finalGate;
    var verifyWallMs = 0;
    if (task.readOnly) {
      finalGate = [
        CheckerResult(
          passed: true,
          detail:
              'read_only_not_applicable: no oracle for reads (ADR 0027) — '
              'excluded from pass-rate columns',
        ),
      ];
    } else {
      final gateSw = Stopwatch()..start();
      finalGate = await analyzeBeforeTests() ?? grade();
      gateSw.stop();
      verifyWallMs = gateSw.elapsedMilliseconds;
    }
    var passed = finalGate.isNotEmpty && finalGate.every((c) => c.passed);
    while (!passed && attempt < maxGoalAttempts) {
      // J8.1 (the exhausted-attempt pump, measured on-device Σ26): the
      // monotonic budget is ONE truth. When the in-run policy stamped
      // [GoalAttemptsExhausted], the decision ENDS — no driver re-send on
      // an exhausted actor (the overseer window below is the designated
      // post-exhaustion path, never more attempt prompts).
      if (world.query2<Actor, GoalAttemptsExhausted>().toList().isNotEmpty) {
        break;
      }
      // ONE truth (P5): the monotonic [AttemptCount] is the budget — the
      // driver READS it, never clobbers it (the in-run policy consumes the
      // same counter for its 1:1 verification re-sends). The old code
      // overwrote the counter with its own loop index — two writers, the
      // divergence the pump lived in.
      attempt =
          (world.getEntity(actor).$1.get<AttemptCount>()?.value ?? attempt) +
          1;
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
                  '${[for (final c in finalGate)
                    if (!c.passed) c.detail].join("\n")}\n\n'
                  '${task.repairHint}\n\nOriginal task:\n${task.prompt}'
            : 'Your previous attempt did not satisfy verification (attempt '
                  '$attempt/$maxGoalAttempts).\nFailing:\n'
                  '${[for (final c in finalGate)
                    if (!c.passed) c.detail].join("\n")}\n\n'
                  '${task.repairHint}\n\nOriginal task:\n${task.prompt}',
      );
      await HarnessLoop(world: world).runUntilIdle();
      if (!task.readOnly) {
        final gateSw = Stopwatch()..start();
        finalGate = await analyzeBeforeTests() ?? grade();
        gateSw.stop();
        verifyWallMs = gateSw.elapsedMilliseconds;
      }
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
        world
            .getEntity(actor)
            .$1
            .insert(
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
        world
            .getEntity(actor)
            .$1
            .insert(
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
    final toolResults = <String>[];
    var toolRounds = 0;
    final activeThread =
        resumedThread ??
        world.getEntity(actor).$1.get<ActorThreads>()?.threads.firstOrNull;
    final threadEntity = activeThread;
    for (final beat
        in (threadEntity == null
                ? const <Entity>[]
                : world.getResource<FacetIndex>().beatsOfThread(threadEntity))
            .toList()) {
      final we = world.getEntity(beat).$1;
      final call = we.get<BeatToolCall>();
      if (call != null) {
        toolRounds++;
        final action = call.args['action'];
        moves.update(
          action is String ? '${call.name}.$action' : call.name,
          (v) => v + 1,
          ifAbsent: () => 1,
        );
      }
      final result = we.get<ToolResultContent>();
      if (result != null) {
        final out = '${result.output}';
        toolResults.add(
          '${result.name}: '
          '${out.length > 240 ? out.substring(0, 240) : out}',
        );
      }
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

    final attemptsExhausted = world
        .query2<Actor, GoalAttemptsExhausted>()
        .toList()
        .isNotEmpty;
    // ADDITIVE (the deferred-task law, item 3): the deferral accounting
    // rides the task outcome when a host wired the pool; unwired → zeros
    // (the disabled fallback — the legacy inline verify has nothing to
    // account).
    DeferredTaskAccounting? deferredAccounting;
    try {
      deferredAccounting = world.getResource<DeferredTaskAccounting>();
    } on StateError {
      deferredAccounting = null;
    }
    return CodingAgentRunResult(
      taskId: task.id,
      backend: backend,
      passed: passed,
      attemptsExhausted: attemptsExhausted,
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
      verifyWallMs: verifyWallMs,
      toolResults: toolResults,
      deferralRate: deferredAccounting?.deferralRate ?? 0,
      deferredVerifyBeats: deferredAccounting?.completionBeats ?? 0,
      deferredVerifyDefects: deferredAccounting?.namedDefects() ?? const [],
      writeGateAudit: gateway == null
          ? ''
          : 'writes applied: ${gateway.appliedCount}, '
                'rejected: ${gateway.rejectedCount}\n'
                '${gateway.renderDiffs()}',
    );
  } finally {
    resultPoller?.cancel();
  }
}

/// P1: ONE per-package verify step of the final gate — the package's own
/// convention in its own directory, wall-measured into the verdict detail
/// (the same budget-law data the `goal_verify` beat carries as
/// `verify_wall_ms`).
CheckerResult _runVerifyStep(RunGoalCommand step, String workspaceRoot) {
  final cwd = step.cwd == null || step.cwd!.isEmpty
      ? workspaceRoot
      : '$workspaceRoot/${step.cwd}';
  final sw = Stopwatch()..start();
  final result = Process.runSync(
    step.command.first,
    step.command.sublist(1),
    workingDirectory: cwd,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  sw.stop();
  return CheckerResult(
    passed: result.exitCode == 0,
    detail:
        '${step.command.join(" ")} in ${step.cwd ?? "."} '
        'exit=${result.exitCode} (verify_wall_ms=${sw.elapsedMilliseconds})'
        '${result.exitCode == 0 ? "" : ": ${result.stderr}".trim()}',
  );
}

/// Formats one run as its honest log body (B8: every run ships the pulse +
/// flight-recorder dump, pass or fail).
String formatRunLog(CodingAgentRunResult r) =>
    '''
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
${[for (final c in r.finalGate) '    check: ${c.detail}'].join('\n')}
  failure class: ${r.failureClass.isEmpty ? '-' : r.failureClass}
  deferred verify (item 3): rate=${r.deferralRate.toStringAsFixed(3)} beats=${r.deferredVerifyBeats}${r.deferredVerifyDefects.isEmpty ? '' : ' DEFECTS: ${r.deferredVerifyDefects.join(" | ")}'}
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
  final tokenTotals = [for (final r in results) r.projectionTokens];
  final decisionTotals = [for (final r in results) r.decisions];
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
  return {
    '_positional': positional.isEmpty ? null : positional.first,
    ...named,
  };
}

/// jsonEncode helper for logs (keeps the summary row one line).
String summaryLine(Map<String, Object?> row) => jsonEncode(row);

// ─────────────────────────────────────────────
// The deferred-task law (item 3) — minimal ADDITIVE wiring
// ─────────────────────────────────────────────

/// Deferred-verify wiring for a coding-runner world. ADDITIVE and OPT-IN:
/// a host that never calls this keeps EVERY existing behavior byte-identical
/// (the disabled-fallback law — the verifier runs inline exactly as before).
/// When called, the policy (enabled), the (package, convention) pool and the
/// deferral accounting exist, and per-package verify steps may route through
/// [maybeJoinDeferredVerify] — one pooled task per (package, convention),
/// completion beats re-opening every requesting actor.
void wireDeferredVerify(World world) {
  world
    ..upsertResource(DeferredTaskPolicy(enabled: true))
    ..upsertResource(DeferredVerifyPool())
    ..upsertResource(DeferredTaskAccounting())
    ..flush();
}

/// Route ONE derived per-package verify step through the pooling law:
/// the same (package, convention) → JOIN the in-flight task (one task
/// runs, both actors get the completion beat); otherwise register a NEW
/// pooled task. Returns null (and the caller runs the EXISTING inline
/// step) when deferral is unwired/disabled or the step classifies inline —
/// the disabled fallback preserving the legacy behavior verbatim.
DeferredVerifyEntry? maybeJoinDeferredVerify(
  World world, {
  required RunGoalCommand step,
  required Entity requester,
}) {
  DeferredTaskPolicy? policy;
  try {
    policy = world.getResource<DeferredTaskPolicy>();
  } on StateError {
    return null; // unwired → inline fallback
  }
  if (!policy.enabled) return null; // disabled → inline fallback
  DeferredVerifyPool? pool;
  try {
    pool = world.getResource<DeferredVerifyPool>();
  } on StateError {
    return null; // policy without a pool → honest inline fallback
  }
  return pool.join(
    world: world,
    packageDir: step.cwd ?? '',
    conventionCommand: step.command,
    requester: requester,
  );
}

/// Complete a pooled deferred verify (thin host-side alias over the
/// harness completion — the EXISTING in-flight task machinery: the
/// registered TaskHandle completer resolves, and every requesting actor
/// gets the completion beat + re-open via the ToolResultPendingMarker
/// continuation; no poll loop anywhere).
void completeDeferredVerifyTask(
  World world, {
  required TaskId taskId,
  required bool passed,
  required String detail,
  int? verifyWallMs,
  List<String>? command,
}) => completeDeferredVerify(
  world,
  taskId: taskId,
  passed: passed,
  detail: detail,
  verifyWallMs: verifyWallMs,
  command: command,
);
