// ignore_for_file: lines_longer_than_80_chars

/// Loop-breaker guard tests: identical failing tool calls within a thread
/// must trigger deterministic teaching (streak 2) and escalation (streak 3),
/// and stay silent on distinct or succeeding calls.
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'support/agent_harness_support.dart';

/// Records every generation request so projection reachability of the
/// teaching beat can be asserted.
class CapturingHandler implements GenerationHandler {
  CapturingHandler({required this.respond});
  final ActorGenerateResponse Function(ActorGenerateRequest request) respond;
  final List<ActorGenerateRequest> requests = [];

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    requests.add(request);
    final response = respond(request);
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

/// Mirrors processToolResultsSystem's beat shape for a canned call/result.
Entity addToolBeat(
  World world,
  Entity thread,
  Entity actor,
  ToolCall call,
  Map<String, dynamic> output,
) {
  final beat = world.reserveEmptyEntity().entity;
  world.getEntity(beat).$1
    ..insert(ToolResultContent(name: call.name.value, output: jsonEncode(output)))
    ..insert(Speaker(actor))
    ..insert(BeatToolCall(call.name.value, call.arguments))
    ..insert(TextContent('${call.name} → ${jsonEncode(output)}'))
    ..insert(BeatStatus(BeatStatusEnum.complete))
    ..insert(BeatModality(BeatModalityEnum.toolCall))
    ..insert(BelongsToThread(thread));
  indexBeat(
    world,
    beat,
    keywordsOf('${call.name} ${jsonEncode(output)}'),
    thread: thread,
  );
  world.flush();
  return beat;
}

ToolCall sameCall() => const ToolCall(
      name: ToolName('patch_file'),
      arguments: {
        'path': 'config.dart',
        'anchor': 'MAX_USERS',
        'new_text': 'maxUserLimit',
      },
    );

void main() {
  test('teaching beat inserted once at streak 2, no escalation', () async {
    final world = await buildTestWorld();
    final scene = spawnScene(world);
    final actor = spawnActor(world, scene);
    world.flush();
    final thread = spawnThread(world, actor, scene);
    world.upsertComponent(actor, ActorThreads(threads: [thread]));
    world.flush();

    addToolBeat(world, thread, actor, sameCall(), {'ok': false, 'code': 'anchor_not_unique'});
    addToolBeat(world, thread, actor, sameCall(), {'ok': false, 'code': 'anchor_not_unique'});

    world.runSchedule(Schedules.mechanical);
    world.flush();

    final guards = beatsWithText(world, 'Loop guard');
    expect(guards, hasLength(1), reason: 'one teaching beat at streak 2');
    expect(world.query2<Actor, LoopStuck>(), isEmpty);

    // Idempotent: another mechanical pass with NO new failures must not
    // re-teach.
    world.runSchedule(Schedules.mechanical);
    world.flush();
    expect(beatsWithText(world, 'Loop guard'), hasLength(1));
    expectIdle(world);
  });

  test('escalation stamped at streak 3', () async {
    final world = await buildTestWorld();
    final scene = spawnScene(world);
    final actor = spawnActor(world, scene);
    world.flush();
    final thread = spawnThread(world, actor, scene);
    world.upsertComponent(actor, ActorThreads(threads: [thread]));
    world.flush();

    for (var i = 0; i < 3; i++) {
      addToolBeat(world, thread, actor, sameCall(), {'ok': false, 'code': 'x'});
    }

    world.runSchedule(Schedules.mechanical);
    world.flush();

    final stuck = world.query2<Actor, LoopStuck>().toList();
    expect(stuck, hasLength(1));
    expect(stuck.first.$3.streak, greaterThanOrEqualTo(3));
    // Escalation is now declarative: LoopStuck is consumed by a DecisionFlow
    // policy into DecisionDraft(escalate:true); the mechanical layer no longer
    // writes EscalationRequest directly.
    expect(world.query2<Actor, EscalationRequest>(), isEmpty);
    expectIdle(world);
  });

  test('distinct calls and successes never trigger the guard', () async {
    final world = await buildTestWorld();
    final scene = spawnScene(world);
    final actor = spawnActor(world, scene);
    world.flush();
    final thread = spawnThread(world, actor, scene);
    world.upsertComponent(actor, ActorThreads(threads: [thread]));
    world.flush();

    addToolBeat(world, thread, actor, sameCall(), {'ok': false, 'code': 'a'});
    addToolBeat(
      world,
      thread,
      actor,
      const ToolCall(
        name: ToolName('patch_file'),
        arguments: {'path': 'config.dart', 'anchor': ') => MAX_USERS *', 'new_text': ') => maxUserLimit *'},
      ),
      {'ok': false, 'code': 'b'},
    );
    addToolBeat(world, thread, actor, sameCall(), {'ok': true});

    world.runSchedule(Schedules.mechanical);
    world.flush();

    expect(beatsWithText(world, 'Loop guard'), isEmpty);
    expect(world.query2<Actor, EscalationRequest>(), isEmpty);
    expectIdle(world);
  });

  test('tier 3: taught but still looping suspends thread and stops continuation',
      () async {
    final world = await buildTestWorld();
    final scene = spawnScene(world);
    final actor = spawnActor(world, scene);
    world.flush();
    final thread = spawnThread(world, actor, scene);
    world.upsertComponent(actor, ActorThreads(threads: [thread]));
    world.upsertComponent(actor, const ActorTools(registryName: 'default'));
    // A teaching beat already exists earlier in this thread.
    addToolBeat(world, thread, actor, sameCall(), {'ok': false, 'code': 'old'});
    final guardBeat = world.reserveEmptyEntity().entity;
    world.getEntity(guardBeat).$1
      ..insert(ObservationData({'kind': 'loop_guard'}))
      ..insert(TextContent('Loop guard: earlier teaching beat'))
      ..insert(BelongsToThread(thread));
    indexBeat(world, guardBeat, keywordsOf('Loop guard'), thread: thread);
    addToolBeat(world, thread, actor, sameCall(), {'ok': false, 'code': 'x'});
    addToolBeat(world, thread, actor, sameCall(), {'ok': false, 'code': 'x'});
    addToolBeat(world, thread, actor, sameCall(), {'ok': false, 'code': 'x'});
    world.upsertComponent(actor, const ToolResultPendingMarker());
    world.flush();

    world.runSchedule(Schedules.mechanical);
    world.flush();

    expect(
      world.getEntity(thread).$1.get<ThreadStatus>()?.value,
      ThreadStatusEnum.suspended,
      reason: 'taught + looping => suspend',
    );
    expect(
      world.getEntity(actor).$1.has<ToolResultPendingMarker>(),
      isFalse,
      reason: 'continuation withdrawn — no more rounds burned',
    );
    expectIdle(world);
  });

  test('end-to-end: teaching beat reaches the next decision projection',
      () async {
    final registry = ToolRegistry()
      ..register(
        ToolDef(
          name: const ToolName('patch_file'),
          description: 'always fails here',
          execute: (args) async =>
              jsonEncode({'ok': false, 'code': 'anchor_not_unique'}),
        ),
      );
    final world = await buildTestWorld(toolRegistry: registry);
    final scene = spawnScene(world);
    var turn = 0;
    final handler = CapturingHandler(
      respond: (request) {
        // Turns 1-2: identical failing call. Turn 3: answer.
        turn++;
        return ActorGenerateResponse(
          actorEntity: request.actorEntity,
          structuredOutput: {'text': 'turn $turn'},
          rawOutput: 'turn $turn',
          toolCalls: turn <= 2 ? [sameCall()] : const [],
          taskId: request.taskId,
        );
      },
    );
    world.getResource<GenerationHandlerResource>().registerDefault(handler);
    final actor = spawnActor(world, scene, openDecisionPrompt: 'fix it');
    world.upsertComponent(
      actor,
      const ActorTools(registryName: 'default'),
    );
    world.flush();
    final thread = spawnThread(world, actor, scene);
    world.upsertComponent(actor, ActorThreads(threads: [thread]));
    world.flush();

    const settle = Duration(milliseconds: 50);
    await runCycle(world, drainDelay: settle); // t1 → failed call #1
    await runCycle(world, drainDelay: settle); // t2 → identical fail #2 → teach
    await runCycle(world, drainDelay: settle); // t3 → guard must project

    expect(handler.requests.length, greaterThanOrEqualTo(3));
    expect(beatsWithText(world, 'Loop guard'), hasLength(1));
    expect(
      handler.requests[2].contextFragments.join('\n'),
      contains('Loop guard'),
      reason: 'projection must surface the teaching beat to the model',
    );
    expectIdle(world);
  });
}
