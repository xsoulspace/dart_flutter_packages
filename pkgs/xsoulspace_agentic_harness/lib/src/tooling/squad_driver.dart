// ignore_for_file: lines_longer_than_80_chars

/// Stage N2 — the multi-actor squad (single process, one shared workspace).
///
/// Several actors claim FILE-DISJOINT tasks from a board; assignment is
/// MECHANICAL (agency discipline: assignment is not an LLM decision). Each
/// actor gets its own [FsToolsRoot] instance over the SAME directory with
/// its own [JailWriteGateway], all sharing one [FileLockTable] — writes to
/// another actor's file are rejected with a structured ack. Verification is
/// per-actor run-graded (D8: criteria live in the tasks, not in code).
///
/// Escalation (N5): exhaustion → structured FAIL (the J1.5 ladder); actor-to-
/// actor reassignment is the N5 coordination layer.
library;

import 'dart:io';

import 'package:ecsly/ecsly.dart';

import '../agent.dart';
import '../handler.dart';
import '../harness_loop.dart';
import '../narrative/graph_ops.dart';
import '../systems/projection/cut_composition.dart';
import 'build_gates.dart';
import '../tools/fs_tools.dart';
import 'workspace_map.dart';

/// ADR 0020 §5 — model ≠ actor: a ROLE is (composition + system prompt +
/// tool surface + model binding). One model can field many roles; one role
/// can run on any model. Roles are host data over the same seams.
class AgentRole {
  const AgentRole({
    required this.name,
    this.composition,
    this.systemPrompt,
  });

  final String name;

  /// Null → the squad default composition (coder).
  final CutComposition? composition;

  /// Null → the squad default prompt.
  final String? systemPrompt;
}

/// One board task: goal sentence + mechanical criterion + owned files.
class SquadTask {
  SquadTask({
    required this.id,
    required this.prompt,
    required this.checkCommand,
    required this.ownedFiles,
    this.fixtures = const [],
    this.role,
  });

  final String id;
  final String prompt;

  /// Mechanical criterion (D8): must exit 0. Resolved by the HOST, never
  /// per-task checker code.
  final List<String> checkCommand;

  /// Files this task owns — claimed in the [FileLockTable] so no other
  /// actor's writes can land on them.
  final List<String> ownedFiles;

  /// Host-seeded files (check scripts, pre-state). NOT model-authored.
  final List<SquadFixture> fixtures;

  /// Optional role binding (ADR 0020 §5): per-actor composition + prompt.
  final AgentRole? role;
}

class SquadFixture {
  SquadFixture({required this.path, required this.content});
  final String path;
  final String content;
}

/// One actor's row in the squad result (a2a columns, K2-style).
class SquadRow {
  SquadRow({
    required this.actorName,
    required this.taskId,
    required this.passed,
    required this.verdict,
    required this.decisions,
    required this.projectionTokens,
  });
  final String actorName;
  final String taskId;
  final bool passed;
  final String verdict;

  /// a2a column: generation calls this actor consumed.
  final int decisions;

  /// a2a column: honest projection spend of the final cut.
  final int projectionTokens;
}

class SquadResult {
  SquadResult({required this.rows, required this.allPassed});
  final List<SquadRow> rows;
  final bool allPassed;
}

/// Counts generation calls per actor (a2a column) and delegates.
class _CountingHandler implements GenerationHandler {
  _CountingHandler({
    required this.inner,
    required this.decisions,
    required this.entityName,
  });

  final GenerationHandler inner;
  final Map<String, int> decisions;
  final Map<Entity, String> entityName;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final name = entityName[request.actorEntity];
    if (name != null) decisions[name] = (decisions[name] ?? 0) + 1;
    return inner.generate(world, request);
  }
}

/// Routes generation requests to a per-actor handler (the resource resolves
/// ONE default; the squad needs one per actor).
class _SquadRoutingHandler implements GenerationHandler {
  _SquadRoutingHandler({required this.byActor, required this.entityName});

  final Map<String, GenerationHandler> byActor;
  final Map<Entity, String> entityName; // actor entity -> name

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) {
    final name = entityName[request.actorEntity];
    final handler = name == null ? null : byActor[name];
    if (handler == null) {
      world.events.writer<ActorGenerateResponse>().send(
            ActorGenerateResponse(
              actorEntity: request.actorEntity,
              structuredOutput: {'text': 'no handler for actor'},
              rawOutput: 'no handler for actor',
              taskId: request.taskId,
            ),
          );
      return Future.value(
        ActorGenerateResponse(
          actorEntity: request.actorEntity,
          structuredOutput: {'text': 'no handler for actor'},
          rawOutput: 'no handler for actor',
          taskId: request.taskId,
        ),
      );
    }
    return handler.generate(world, request);
  }
}

/// Runs the squad: one actor per task (mechanical 1:1 assignment), shared
/// workspace, single-writer locks, per-actor run-graded verification.
Future<SquadResult> runSquad({
  required Directory workspace,
  required List<SquadTask> tasks,
  required GenerationHandler Function(String actorName) handlerFor,
  ModelRouter? router,
  FlightRecorder? recorder,
}) async {
  final world = World()..addPlugin(AgentPlugin());
  world
    ..upsertResource(ToolRegistryResource())
    ..upsertResource(ModelRouterResource(router ?? ModelRouter()))
    ..upsertResource(DecisionFlowResource(defaultGoalFlow()))
    ..upsertResource(AgencyPolicy(maxConcurrent: tasks.length, maxToolRounds: 12))
    ..flush();

  final locks = FileLockTable();
  final entityName = <Entity, String>{};
  final byActor = <String, GenerationHandler>{};
  final decisionsByActor = <String, int>{};
  final commandByRegistry = <String, List<String>>{};
  final compositionByRegistry = <String, CutComposition>{};
  final actorTasks = <String, SquadTask>{};

  final scene = world.spawnComponents([Scene(), SceneFrame()]);

  for (var i = 0; i < tasks.length; i++) {
    final task = tasks[i];
    final actorName = 'squad_${task.id}';
    final registryName = 'squad_${task.id}';

    // Host-seeded fixtures (check scripts etc.) — never model-authored.
    for (final f in task.fixtures) {
      final file = File('${workspace.path}/${f.path}')
        ..parent.createSync(recursive: true);
      file.writeAsStringSync(f.content);
    }

    // Per-actor root instance over the SAME directory, with the shared
    // single-writer lock table. Ownership is claimed BEFORE the run.
    final root = FsToolsRoot(workspace.path);
    root.writeGateway = JailWriteGateway(
      root,
      mode: WriteGateMode.apply,
      locks: locks,
      owner: actorName,
    );
    for (final f in task.ownedFiles) {
      final ok = locks.claim(f, actorName);
      if (!ok) {
        throw StateError(
          'squad: file "$f" is claimed twice — tasks are not file-disjoint',
        );
      }
    }
    final registry = ToolRegistry();
    for (final t in fsTools(root)) {
      registry.register(t);
    }
    world.getResource<ToolRegistryResource>().register(registryName, registry);
    commandByRegistry[registryName] = task.checkCommand;

    final role = task.role;
    final actor = world.spawnComponents([
      Actor(agentId: AgentId.create()),
      ActorModel(modelId: ModelId.create()),
      ActorSystemPrompt(
        text: role?.systemPrompt ??
            'You are $actorName. Work ONLY on your task.',
      ),
      ActorThreads(threads: []),
      ActorTools(registryName: registryName),
      PresentInScene(sceneEntity: scene),
      Goal(text: task.prompt),
      OpenDecision(prompt: task.prompt),
    ]);
    if (role?.composition != null) {
      compositionByRegistry[registryName] = role!.composition!;
    }
    final thread = spawnThread(world, actor, scene);
    world.upsertComponent(actor, ActorThreads(threads: [thread]));
    world.flush();

    entityName[actor] = actorName;
    byActor[actorName] = handlerFor(actorName);
    decisionsByActor[actorName] = 0;
    actorTasks[actorName] = task;
  }

  world.getResource<GenerationHandlerResource>().registerDefault(
        _CountingHandler(
          inner: _SquadRoutingHandler(
            byActor: byActor,
            entityName: entityName,
          ),
          decisions: decisionsByActor,
          entityName: entityName,
        ),
      );
  if (recorder != null) world.upsertResource(recorder);

  // ADR 0020: squad composition with per-role cuts + the workspace map
  // provider (fs-as-graph v1) feeding the required map slot.
  final mapProvider = WorkspaceMapProvider(workspace.path);
  world.upsertResource(
    CutCompositionResource(
      CutComposition.coder(),
      compositionByRegistry: compositionByRegistry,
      mapProvider: mapProvider.map,
    ),
  );

  // Per-actor run-graded verification (stamps ONLY the pending actor).
  world.upsertResource(
    RunGoalSpec(
      command: tasks.first.checkCommand,
      commandByRegistry: commandByRegistry,
    ),
  );
  world.schedule(Schedules.narrative).add(runGoalVerifier, name: 'runGradedVerifier');
  world.flush();

  await HarnessLoop(world: world).runUntilIdle();

  // N2: the verifier's check command runs asynchronously (a real subprocess);
  // the loop can reach idle while a pending stamp is still in flight. Settle:
  // wait (bounded) until every goal-carrying actor holds a verdict.
  for (var i = 0; i < 50; i++) {
    var missing = 0;
    for (final (facade, _, _) in world.query2<Actor, Goal>().toList()) {
      final we = world.getEntity(facade.entity).$1;
      if (!we.has<GoalVerified>()) missing++;
    }
    if (missing == 0) break;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    world.runSchedule(Schedules.narrative);
    world.flush();
  }

  final rows = <SquadRow>[];
  for (final (facade, _, _) in world.query2<Actor, Goal>().toList()) {
    final name = entityName[facade.entity];
    if (name == null) continue;
    final verdict = world.getEntity(facade.entity).$1.get<GoalVerified>();
    final situation = world.getEntity(facade.entity).$1.get<Situation>();
    rows.add(
      SquadRow(
        actorName: name,
        taskId: actorTasks[name]!.id,
        passed: verdict?.passed ?? false,
        verdict: verdict?.detail ?? 'no verdict stamped',
        decisions: decisionsByActor[name] ?? 0,
        projectionTokens: situation?.tokensUsed ?? 0,
      ),
    );
  }
  return SquadResult(
    rows: rows,
    allPassed: rows.isNotEmpty && rows.every((r) => r.passed),
  );
}
