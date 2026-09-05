// ignore_for_file: lines_longer_than_80_chars

/// The workspace-oracle meaning runner (ADR 0022 / PLAN R6).
///
/// One task attempt, end to end, LLM-free-testable:
///
/// 1. **ETL-in** — [deriveWorkspaceIntents] turns the workspace's OWN test
///    suite into intent skeletons + derived expectations. The expectation
///    table is never host-authored (the A-closure fix).
/// 2. The model fills the bounded slots of those skeletons via
///    `intent_define` (specs = op rows). Chains are never authored from
///    scratch; the skeleton's name/params/returns are host data (the
///    ADR 0021 division of labor).
/// 3. The in-loop verifier replays the DERIVED expectations through the
///    interpreter mechanically (`wireIntentGradedGoal`).
/// 4. Before every gate the HOST materializes workspace Dart (zero model
///    tokens — the model never even runs `materialize`) and the workspace
///    convention (`dart test`) grades it (the C-closure fix: the final
///    gate is the workspace, not a VM replay).
///
/// The model never writes code tokens, never sees an AST, never holds the
/// whole meaning tree. Attempts are bounded by [maxGoalAttempts] (monotonic
/// `AttemptCount`, J1.5 discipline); exhaustion stamps
/// `GoalAttemptsExhausted` — never a retry loop.
library;

import 'dart:io';

import 'package:xsoulspace_agentic_harness/benchmark_api.dart'
    show
        actWithProjectTool,
        defaultGoalFlow,
        openFreshDecision,
        wireIntentGradedGoal;
import 'package:xsoulspace_agentic_harness/src/tooling/workspace_map.dart'
    show WorkspaceMapProvider;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'dart_materializer.dart'
    show DartMaterializerResult, materializeWorkspaceDart;
import 'test_etl.dart' show DerivedIntent, deriveWorkspaceIntents;

/// The meaning-profile teaching prompt (B6: teaching lives in tool
/// descriptions + this prompt ONLY). The skeleton travels in the goal
/// prompt as data — name/params/returns per intent, nothing else.
const meaningWorkspaceSystemPrompt =
    'You implement intents of a Dart program through meaning moves only — '
    'you never write code tokens, never see an AST. '
    'The goal names each intent with its typed params and return type. '
    'Define each intent with intent_define (action define, WITH specs: '
    'op rows {label, a?, b?, next?}). The closed op vocabulary: '
    'load_arg, literal, add, sub, mul, lt, gt, eq, not, starts_with, '
    'list_len, get_item, call, jump_if_false, jump, return. '
    'A chain loads its params, computes, ends at return. '
    'Verify with intent_call before finishing. The host materializes and '
    'the workspace suite grades.';

/// One workspace-meaning run's measured result (same column discipline as
/// CodingAgentRunResult: backend, decision path, tokens source, n).
class WorkspaceMeaningResult {
  WorkspaceMeaningResult({
    required this.backend,
    required this.passed,
    required this.finalGateDetail,
    required this.decisions,
    required this.projectionTokens,
    required this.toolRounds,
    required this.moves,
    required this.wallClock,
    required this.derivedIntents,
    required this.derivedExpectationCount,
    required this.unresolvedRows,
    required this.generatedFiles,
    required this.nodes,
    required this.edges,
    this.attemptsExhausted = false,
  });

  final String backend;
  final bool passed;
  final String finalGateDetail;

  String get failureClass => passed ? '' : 'final gate: $finalGateDetail';

  final int decisions;

  /// Honest spend: sum of Situation.tokensUsed per decision.
  final int projectionTokens;
  final int toolRounds;
  final Map<String, int> moves;
  final Duration wallClock;

  /// Names of the intents the ETL derived from the suite.
  final List<String> derivedIntents;

  /// How many expectations the SUITE contributed (never host-authored).
  final int derivedExpectationCount;

  /// Honest unresolved test rows (classified data, never dropped).
  final List<String> unresolvedRows;

  /// What the host materialized (file → source), pass or fail.
  final Map<String, String> generatedFiles;
  final int nodes;
  final int edges;
  final bool attemptsExhausted;
}

/// Counts decisions + honest projection spend (same shape as the AFM
/// driver's DecisionMeter; local to this host to avoid a provider-package
/// dependency).
class WorkspaceDecisionMeter implements GenerationHandler {
  WorkspaceDecisionMeter(this.inner);
  final GenerationHandler inner;
  int decisions = 0;
  int projectionTokens = 0;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final situation = world.getEntity(request.actorEntity).$1.get<Situation>();
    if (situation != null) projectionTokens += situation.tokensUsed;
    final response = await inner.generate(world, request);
    decisions++;
    return response;
  }
}

/// Runs ONE workspace task attempt through the meaning profile with the
/// workspace oracle. Deterministic for a scripted handler.
Future<WorkspaceMeaningResult> runWorkspaceMeaningAgent({
  required Directory workspace,
  required GenerationHandler handler,
  required String backend,
  ModelRouter? router,

  /// The actor must bind a model id the ROUTER knows (M1 dogfooding fix).
  ModelId? actorModelId,

  /// Monotonic attempt budget (escalation widens it, never lowers it).
  int maxGoalAttempts = 3,

  /// Host materializer override (tests). Default: compile the meaning tree
  /// to workspace Dart before every gate.
  DartMaterializerResult Function(List<DerivedIntent> intents)?
      materializeOverride,
}) async {
  final sw = Stopwatch()..start();
  final world = World()..addPlugin(AgentPlugin());
  final recorder = FlightRecorder();

  // 1. ETL-in: the workspace suite IS the spec. Honest failure when it
  // derives nothing — never invent a criterion the workspace does not
  // declare (D8).
  final derivation = deriveWorkspaceIntents(workspace);
  if (derivation.isEmpty) {
    throw StateError(
      'workspace-oracle ETL derived no implementable intents from the '
      'suite at ${workspace.path}. Unresolved: '
      '${derivation.unresolved.join(" | ")}',
    );
  }
  final expectations = [
    for (final i in derivation.intents) ...i.expectations,
  ];

  // 2. World wiring — same shape as the coding-agent runner's intent path.
  world
    ..upsertResource(ToolRegistryResource())
    ..upsertResource(recorder)
    ..upsertResource(DecisionFlowResource(defaultGoalFlow()))
    ..upsertResource(AgencyPolicy(maxConcurrent: 1, maxToolRounds: 12))
    ..upsertResource(
      CutCompositionResource(
        CutComposition.coderLean(),
        mapProvider: WorkspaceMapProvider(
          workspace.path,
          maxDepth: 1,
          maxEntries: 16,
        ).map,
      ),
    )
    ..upsertResource(ProjectionBudget(tokens: 4000))
    ..upsertResource(GenerationHandlerResource())
    ..upsertResource(ModelRouterResource(router ?? ModelRouter()))
    ..flush();
  final meter = WorkspaceDecisionMeter(handler);
  world.getResource<GenerationHandlerResource>().registerDefault(meter);

  // 3. Tool surface: intent_define / intent_call + act_with_project for
  // op-level repair (set_prop). Materialize stays host-side (step 4) — the
  // model never needs the materialize move.
  final registry = ToolRegistry();
  for (final t in [
    intentDefineTool(world),
    intentCallTool(world),
    actWithProjectTool(
      world: world,
      materialize: () async => {
        'materialized': false,
        'note': 'the host materializes workspace Dart before every gate; '
            'you do not need the materialize move',
      },
    ),
  ]) {
    registry.register(t);
  }
  world.getResource<ToolRegistryResource>().register('default', registry);

  // 4. The actor carries the goal; the skeleton travels in-frame (ADR 0009).
  final skeleton = [
    for (final i in derivation.intents)
      '${i.intent}(${i.params.map((p) => "${p.name}:${p.type}").join(", ")}) '
          '-> ${i.returns}',
  ].join('; ');
  final taskPrompt = 'Implement the intents of this workspace: $skeleton. '
      'Define each with intent_define (specs), verify with intent_call.';
  final scene = world.spawnComponents([Scene(), SceneFrame()]);
  final actor = world.spawnComponents([
    Actor(agentId: AgentId.create()),
    ActorModel(modelId: actorModelId ?? ModelId.create()),
    ActorSystemPrompt(text: meaningWorkspaceSystemPrompt),
    ActorThreads(threads: []),
    ActorTools(registryName: 'default'),
    PresentInScene(sceneEntity: scene),
    Goal(text: taskPrompt),
    OpenDecision(prompt: taskPrompt),
  ]);
  final thread = spawnThread(world, actor, scene);
  world.upsertComponent(actor, ActorThreads(threads: [thread]));
  world.flush();

  // 5. THE R6 CHANGE: the in-loop oracle replays DERIVED expectations —
  // never a host-authored table (the A-closure fix).
  wireIntentGradedGoal(world, sequence: expectations);

  // 6. Host materialization + the workspace gate. `dart pub get` runs once
  // (mechanical, zero model tokens) when the workspace has no resolution.
  var generated = const <String, String>{};
  Future<({bool passed, String detail})> grade() async {
    final mat = materializeOverride != null
        ? materializeOverride(derivation.intents)
        : materializeWorkspaceDart(world, intents: derivation.intents);
    if (!mat.ok) {
      return (
        passed: false,
        detail: 'materializer: ${mat.problems.join(" | ")}',
      );
    }
    generated = mat.files;
    for (final entry in mat.files.entries) {
      final f = File('${workspace.path}/${entry.key}');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(entry.value);
    }
    if (File('${workspace.path}/pubspec.yaml').existsSync() &&
        !File(
          '${workspace.path}/.dart_tool/package_config.json',
        ).existsSync()) {
      final get = await Process.run(
        'dart',
        ['pub', 'get'],
        workingDirectory: workspace.path,
      );
      if (get.exitCode != 0) {
        return (
          passed: false,
          detail: 'dart pub get failed: ${get.stdout} ${get.stderr}',
        );
      }
    }
    final check = resolveWorkspaceCheck(workspace) ?? const ['dart', 'test'];
    final result = await Process.run(
      check.first,
      check.sublist(1),
      workingDirectory: workspace.path,
    );
    final out = ('${result.stdout}${result.stderr}').trim();
    return (
      passed: result.exitCode == 0,
      detail: '${check.join(" ")} exit=${result.exitCode}'
          '${out.isEmpty ? "" : "\n${out.split("\n").take(8).join("\n")}"}',
    );
  }

  var gate = await grade();
  var passed = gate.passed;
  var attempt = 0;
  while (!passed && attempt < maxGoalAttempts) {
    attempt++;
    world.getEntity(actor).$1.insert(AttemptCount(attempt));
    world.flush();
    openFreshDecision(
      world,
      actor,
      prompt: 'Your previous attempt did not satisfy verification (attempt '
          '$attempt/$maxGoalAttempts).\nFailing:\n${gate.detail}\n\n'
          'Fix the failing intent with intent_define (action define, '
          'corrected specs — replacing an existing chain is atomic). '
          'Original task:\n$taskPrompt',
    );
    await HarnessLoop(world: world).runUntilIdle();
    gate = await grade();
    passed = gate.passed;
  }
  if (!passed) {
    world.getEntity(actor).$1.insert(
      GoalAttemptsExhausted(
        'goal_unverifiable: $attempt failed verification attempts '
        '(budget $maxGoalAttempts). Last failure: ${gate.detail}',
      ),
    );
    world.flush();
  }

  // K columns from the durable thread record.
  final moves = <String, int>{};
  var toolRounds = 0;
  final carriers = world.query2<Actor, ActorThreads>().toList();
  final threadEntity = carriers.isEmpty
      ? null
      : carriers.first.$1.get<ActorThreads>()?.threads.firstOrNull;
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
  sw.stop();
  return WorkspaceMeaningResult(
    backend: backend,
    passed: passed,
    finalGateDetail: gate.detail,
    decisions: meter.decisions,
    projectionTokens: meter.projectionTokens,
    toolRounds: toolRounds,
    moves: moves,
    wallClock: sw.elapsed,
    derivedIntents: [
      for (final i in derivation.intents) i.intent,
    ],
    derivedExpectationCount: expectations.length,
    unresolvedRows: derivation.unresolved,
    generatedFiles: generated,
    nodes: view.nodeCount,
    edges: view.edgeCount,
    attemptsExhausted: !passed &&
        world.query2<Actor, GoalAttemptsExhausted>().toList().isNotEmpty,
  );
}
