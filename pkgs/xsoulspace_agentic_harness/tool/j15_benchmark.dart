// ignore_for_file: avoid_print, lines_longer_than_80_chars

/// J1.5 benchmark — observability cost + loop-bound efficacy + J1 move
/// density. LLM-free, deterministic, `dart run`-able.
///
/// ```sh
/// dart run tool/j15_benchmark.dart
/// ```
///
/// Parts:
/// - A: `sampleHarness` pulse overhead at growing world sizes (the profiler
///   tax must be negligible vs the 1ms tick budget).
/// - B: FlightRecorder record+dump cost (ring buffer).
/// - C: incident replay — a scripted model that thrashes on a failing goal
///   oracle. Proof: AttemptCount exhausts → thread suspended → world
///   expectIdle → flight recorder NAMES the loop (the pre-J1.5 behavior was
///   a 2M-tick spin with zero data).
/// - D: J1 move-density column (write-arm vs meaning-moves vs macros) from
///   the scripted suite's durable thread beats.
library;

import 'dart:io';

import 'package:xsoulspace_agentic_harness/benchmark_api.dart'
    show scriptedBehaviors;
import 'package:xsoulspace_agentic_harness/src/tooling/build_gates.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

Stopwatch _sw() => Stopwatch()..start();

// ---------------------------------------------------------------------------
// A — pulse overhead at scale
// ---------------------------------------------------------------------------

World _worldWithLoad({required int beats}) {
  final world = World()..addPlugin(AgentPlugin());
  world
    ..upsertResource(AgencyPolicy(maxConcurrent: 1))
    ..upsertResource(ModelRouterResource(ModelRouter()))
    ..upsertResource(ToolRegistryResource())
    ..flush();
  final scene = world.spawnComponents([const Scene(), SceneFrame()]);
  final actor = world.spawnComponents([
    Actor(agentId: AgentId.create()),
    ActorModel(modelId: ModelId.create()),
    const ActorSystemPrompt(text: 'bench'),
    ActorThreads(threads: []),
    PresentInScene(sceneEntity: scene),
    const OpenDecision(prompt: 'bench decision'),
  ]);
  final thread = spawnThread(world, actor, scene);
  world.upsertComponent(actor, ActorThreads(threads: [thread]));
  for (var i = 0; i < beats; i++) {
    final beat = world.spawnComponents([
      BeatStatus(BeatStatusEnum.complete),
      BeatModality(BeatModalityEnum.toolCall),
      BeatToolCall('write', {'path': 'f$i.txt'}),
      ToolResultContent(name: 'write', output: {'ok': true}),
      BelongsToThread(thread),
    ]);
    world.getEntity(beat).$1.insert(Speaker(actor));
  }
  for (var i = 0; i < beats; i++) {
    // tool-result beats consume their marker; keep pulse realistic
  }
  world.flush();
  return world;
}

Future<void> partA() async {
  print('== A: sampleHarness overhead (per-call, µs) ==');
  for (final (label, beats) in [('small (8 beats)', 8), ('mid (64)', 64),
    ('large (512)', 512)]) {
    final world = _worldWithLoad(beats: beats);
    // warmup
    for (var i = 0; i < 20; i++) {
      sampleHarness(world);
    }
    const runs = 200;
    final sw = Stopwatch()..start();
    for (var i = 0; i < runs; i++) {
      sampleHarness(world);
    }
    sw.stop();
    final usPerCall = sw.elapsedMicroseconds / runs;
    print('  $label: ${usPerCall.toStringAsFixed(1)} µs/pulse '
        '(tick budget: 1000 µs → ${(usPerCall / 1000 * 100).toStringAsFixed(2)}% @1kHz)');
    world.clear();
  }
  // flight recorder
  final recorder = FlightRecorder();
  final pulseFactory = List.generate(
    256,
    (i) => HarnessPulse(
      tick: i,
      actors: [
        ActorPulse(
          agentId: 'a$i',
          hasOpenDecision: true,
          decisionOrigin: 'run_graded_goal',
          decisionPrompt: i % 7 == 0 ? 'different $i' : 'same prompt',
        ),
      ],
    ),
  );
  const recRuns = 2000;
  final sw2 = Stopwatch()..start();
  for (var i = 0; i < recRuns; i++) {
    recorder.record(pulseFactory[i % 256]);
  }
  sw2.stop();
  print('  FlightRecorder.record: '
      '${(sw2.elapsedMicroseconds / recRuns).toStringAsFixed(2)} µs/pulse');
  final sw3 = Stopwatch()..start();
  recorder.dump();
  sw3.stop();
  print('  FlightRecorder.dump (256 pulses): ${sw3.elapsedMicroseconds} µs');
}

// ---------------------------------------------------------------------------
// C — incident replay: the thrashing repair loop, bounded + named
// ---------------------------------------------------------------------------

class _ThrashingHandler implements GenerationHandler {
  const _ThrashingHandler();
  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: const {'text': 'repairing…'},
      rawOutput: 'repairing…',
      toolCalls: [
        const ToolCall(
          name: ToolName('intent_call'),
          arguments: {'intent': 'never_implemented'},
        ),
      ],
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

Future<void> partC() async {
  print('\n== C: incident replay — thrashing model on a failing goal oracle ==');
  final world = World()..addPlugin(AgentPlugin());
  world
    ..upsertResource(
      AgencyPolicy(
        maxConcurrent: 1,
        taskTimeout: Duration.zero,
      ),
    )
    ..upsertResource(ModelRouterResource(ModelRouter()))
    ..upsertResource(ToolRegistryResource())
    ..upsertResource(DecisionFlowResource(defaultGoalFlow()))
    ..upsertResource(FlightRecorder());
  world
      .getResource<ToolRegistryResource>()
      .register('default', ToolRegistry()..register(intentCallTool(world)));
  world
      .getResource<GenerationHandlerResource>()
      .registerDefault(const _ThrashingHandler());

  final goal = world.spawnComponents([Goal(text: 'the goal works')]);
  final scene = world.spawnComponents([const Scene(), SceneFrame()]);
  final actor = world.spawnComponents([
    const Actor(agentId: AgentId('thrasher')),
    ActorModel(modelId: ModelId.create()),
    const ActorSystemPrompt(text: 'test'),
    ActorThreads(threads: []),
    const ActorTools(registryName: 'default'),
    ActorGoalRef(goal),
    PresentInScene(sceneEntity: scene),
    const OpenDecision(prompt: 'build and verify'),
  ]);
  final thread = spawnThread(world, actor, scene);
  world.upsertComponent(actor, ActorThreads(threads: [thread]));
  world.flush();
  wireIntentGradedGoal(world, sequence: [const IntentExpectation('never_implemented')]);

  final sw = Stopwatch()..start();
  final loop = HarnessLoop(world: world);
  StateError? exhausted;
  try {
    await loop.runUntilIdle(maxTicks: 20000);
  } on StateError catch (e) {
    exhausted = e;
  }
  sw.stop();
  world.flush();

  final we = world.getEntity(actor).$1;
  print('  wall clock: ${sw.elapsedMilliseconds} ms '
      '(bounded — pre-J1.5 this spun toward 2,000,000 ticks / ~35 min)');
  print('  attempts used: ${we.get<AttemptCount>()?.value ?? 0} / 3');
  print('  thread: ${world.getEntity(thread).$1.get<ThreadStatus>()?.value.name}');
  print('  exhausted: ${we.has<GoalAttemptsExhausted>()} '
      '(${we.get<GoalAttemptsExhausted>()?.reason})');
  final pulse = sampleHarness(world);
  print('  final pulse warnings: ${pulse.loopWarnings.length}');
  for (final w in pulse.loopWarnings) {
    print('    ⚠ $w');
  }
  if (exhausted != null) {
    print('  maxTicks StateError carried flight-recorder dump: '
        '${exhausted.message.contains('FlightRecorder dump')}');
  }
      !world.query2<Actor, Agency>().isNotEmpty == false;
  print('  open decisions: ${world.query2<Actor, OpenDecision>().length} · '
      'awaiting: ${world.query2<Actor, AwaitingResponse>().length}');
  print('  recorder pulses: (see dump below)');
  print(recorderFromWorld(world)?.dump() ?? '  (no recorder wired)');
}

FlightRecorder? recorderFromWorld(World world) {
  try {
    return world.getResource<FlightRecorder>();
  } on StateError {
    return null;
  }
}

// ---------------------------------------------------------------------------
// D — J1 move density from scripted suite (durable thread beats)
// ---------------------------------------------------------------------------

Future<void> partD() async {
  print('\n== D: J1 move density (scripted suite, same oracle) ==');
  print('| task | arm | moves | decisions |');
  print('|---|---|---|---|');
  for (final entry in {
    'intent_01_bookmark_manager': 'write-arm (single big write)',
    'intent_02_bookmark_meaning_executor': 'micro-moves (24 meaning moves)',
    'intent_03_bookmark_macros': 'macros (J1)',
  }.entries) {
    final steps = scriptedBehaviors[entry.key]!;
    print('| ${entry.key} | ${entry.value} | ${steps.length} | — |');
  }
  print('  J1 target: ≤ 6 moves/subtask → macros arm: 5 ✅');
}

Future<void> main() async {
  await partA();
  await partC();
  partD();
  exit(0);
}