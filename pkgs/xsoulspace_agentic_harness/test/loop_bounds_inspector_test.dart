// ignore_for_file: lines_longer_than_80_chars

/// J1.5 — loop bounds + runtime observability (LLM-free).
///
/// F1: monotonic [AttemptCount] — the fix-stage endless-loop fix. A failing
/// goal verifier re-prompts at most [AgencyPolicy.maxGoalAttempts] times,
/// then stamps [GoalAttemptsExhausted] + [EscalationRequest] and suspends
/// the thread: the loop PROVABLY terminates, world stays expectIdle.
/// F2: fresh decisions reset the per-decision round budget; the monotonic
/// [TotalRoundCount] ledger never resets.
/// J1.5.3: [sampleHarness] pulse shape + [FlightRecorder] repetition
/// detector + auto-dump on maxTicks exhaustion.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:xsoulspace_agentic_harness/src/tooling/build_gates.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'support/agent_harness_support.dart';

/// Always responds with one `intent_call` for an unimplemented intent —
/// a structured tool FAILURE, never a throw. Models the fix-stage model
/// that keeps "repairing" but never satisfies the oracle.
class AlwaysFailingToolHandler implements GenerationHandler {
  const AlwaysFailingToolHandler(this.intentName);
  final String intentName;

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
        ToolCall(
          name: const ToolName('intent_call'),
          arguments: {'intent': intentName},
        ),
      ],
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

/// Handler that never responds — leaves [AwaitingResponse] forever, so
/// `canSleep()` stays false and maxTicks fires (flight-recorder test).
class NeverRespondingHandler implements GenerationHandler {
  const NeverRespondingHandler();

  @override
  Future<ActorGenerateResponse> generate(World world, ActorGenerateRequest request) =>
      Completer<ActorGenerateResponse>().future;
}

/// The on-device loop shape the flight recorder caught: the backend flaps
/// between hard errors and tool-calling responses (which then fail at the
/// tool level and trigger ReAct continuations). Pre-J1.5.6 this loop was
/// unbounded; now the SAME RetryCount budget must survive the continuations
/// and cap the flapping.
class _FlakyBackendHandler implements GenerationHandler {
  int served = 0;
  bool flip = false;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    served++;
    flip = !flip;
    if (flip) {
      return ActorGenerateResponse(
        actorEntity: request.actorEntity,
        error: 'backend_failed',
        structuredOutput: const {},
        rawOutput: '',
        taskId: request.taskId,
      );
    }
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: const {'text': 'working'},
      rawOutput: 'working',
      toolCalls: [
        const ToolCall(
          name: ToolName('no_such_tool'),
          arguments: {},
        ),
      ],
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

World _wiredWorld({
  required GenerationHandler handler,
  int maxGoalAttempts = 2,
}) {
  final world = World()..addPlugin(AgentPlugin());
  world
    ..upsertResource(
      AgencyPolicy(
        maxConcurrent: 1,
        taskTimeout: Duration.zero, // disable timeout sweeper for determinism
        maxGoalAttempts: maxGoalAttempts,
      ),
    )
    ..upsertResource(ModelRouterResource(ModelRouter()))
    ..upsertResource(ToolRegistryResource())
    ..upsertResource(DecisionFlowResource(defaultGoalFlow()));
  world
      .getResource<ToolRegistryResource>()
      .register('default', ToolRegistry()..register(intentCallTool(world)));
  world.getResource<GenerationHandlerResource>().registerDefault(handler);
  return world;
}

(Entity, Entity) _spawnGoalActor(World world, String prompt) {
  final goal = world.spawnComponents([Goal(text: 'the goal works')]);
  final scene = world.spawnComponents([const Scene(), SceneFrame()]);
  final actor = world.spawnComponents([
    Actor(agentId: AgentId.create()),
    ActorModel(modelId: ModelId.create()),
    const ActorSystemPrompt(text: 'test'),
    ActorThreads(threads: []),
    const ActorTools(registryName: 'default'),
    ActorGoalRef(goal),
    PresentInScene(sceneEntity: scene),
    OpenDecision(prompt: prompt),
  ]);
  final thread = spawnThread(world, actor, scene);
  world.upsertComponent(actor, ActorThreads(threads: [thread]));
  world.flush();
  return (actor, thread);
}

void main() {
  group('J1.5.1 — monotonic attempt budget (endless-loop fix)', () {
    test('budget exhaustion suspends the thread + escalates; loop terminates '
        'with an expectIdle-clean world', () async {
      final world = _wiredWorld(
        handler: const AlwaysFailingToolHandler('never_implemented'),
      );
      final (actor, thread) = _spawnGoalActor(world, 'build and verify');
      wireIntentGradedGoal(world, sequence: [
        const IntentExpectation('never_implemented'),
      ]);

      await HarnessLoop(world: world).runUntilIdle(maxTicks: 5000);
      world.flush();

      final we = world.getEntity(actor).$1;
      expect(we.get<AttemptCount>()?.value, 2,
          reason: 'one monotonic increment per failed verification');
      expect(
        we.get<GoalAttemptsExhausted>()?.reason,
        contains('goal_unverifiable'),
      );
      // EscalationRequest is a TRANSIENT one-shot baton (a racing in-flight
      // response may consume it — see generation_systems). The durable
      // escalation record is the exhaustion tag + structured reason.
      expect(
        we.get<GoalAttemptsExhausted>()!.reason,
        isNotEmpty,
        reason: 'the structured escalation reason must be durable',
      );
      expect(
        world.getEntity(thread).$1.get<ThreadStatus>()?.value,
        ThreadStatusEnum.suspended,
        reason: 'Tier-3 mechanism: suspended thread cannot be re-prompted',
      );

      // THE invariant: the world is genuinely idle — nothing stranded, no
      // re-prompt loop, no orphaned work. This is what failed before.
      expectIdle(world);
    });

    test('attempt counter survives prose turns (never reset by text-only '
        'responses — the pre-fix hazard)', () async {
      final world = _wiredWorld(
        handler: const AlwaysFailingToolHandler('never_implemented'),
        maxGoalAttempts: 99,
      );
      final (actor, _) = _spawnGoalActor(world, 'build and verify');
      // Simulate: failing verification, then a text-only response turn
      // (which resets ToolRoundCount), then another failing verification.
      final we = world.getEntity(actor).$1;
      world.upsertComponent(actor, GoalVerified(passed: false, detail: 'x'));
      world.flush();
      var ctx = DecisionContext(actor: actor, world: world, tick: 1);
      expect(const RunGradedGoalPolicy().evaluate(ctx), isNotNull);
      world.flush();
      expect(we.get<AttemptCount>()?.value, 1);

      // Prose turn: response with NO tool calls resets ToolRoundCount —
      // but AttemptCount must survive.
      world.upsertComponent(actor, ToolRoundCount(5));
      we.remove<OpenDecision>();
      // (generation system would do this on a text-only final answer)
      ctx = DecisionContext(actor: actor, world: world, tick: 2);
      final draft = const RunGradedGoalPolicy().evaluate(ctx);
      world.flush();
      expect(we.get<AttemptCount>()?.value, 2);
      expect(we.get<ToolRoundCount>()?.value, 5,
          reason: 'policy must not touch the round budget');
      expect(draft!.prompt, contains('attempt 2/99'));
      // NOTE: intentionally NOT expectIdle — policy-only unit fixture.
    });
  });

  group('J1.5.2 — round-budget semantics', () {
    test('openFreshDecision resets the per-decision budget, keeps the '
        'monotonic ledger, clears stale verdicts', () async {
      final world = _wiredWorld(handler: const NeverRespondingHandler());
      final (actor, _) = _spawnGoalActor(world, 'first task');
      final we = world.getEntity(actor).$1;
      we
        ..insert(ToolRoundCount(12)) // at the cap
        ..insert(TotalRoundCount(12))
        ..insert(GoalVerified(passed: false, detail: 'stale failure'));
      world.flush();

      openFreshDecision(world, actor, prompt: 'retry attempt');

      // Re-fetch: ecsly facades are stale views after flush-moves.
      final fresh = world.getEntity(actor).$1;
      expect(fresh.get<ToolRoundCount>()?.value ?? 0, 0,
          reason: 'fresh decision = full round budget (fixes the silent '
              'starvation of host-injected retries)');
      expect(fresh.get<TotalRoundCount>()?.value, 12,
          reason: 'lifetime ledger never resets');
      expect(fresh.get<GoalVerified>(), isNull,
          reason: 'stale verdicts must not re-trigger policies');
      expect(fresh.has<OpenDecision>(), isTrue);
      // NOTE: intentionally NOT expectIdle — this fixture deliberately
      // leaves an open decision (the point is the budget reset).
    });

    test('policy-opened decisions do NOT reset the round budget (thenOpen '
        'flows stay chain-bounded); only openFreshDecision does', () {
      final world = _wiredWorld(handler: const NeverRespondingHandler());
      final (actor, _) = _spawnGoalActor(world, 'task');
      // The fixture spawns with an OpenDecision; the flow system skips
      // actors holding one — clear it so the policies can evaluate.
      world.getEntity(actor).$1.remove<OpenDecision>();
      final we = world.getEntity(actor).$1;
      we
        ..insert(ToolRoundCount(7))
        ..insert(TotalRoundCount(7))
        ..insert(const ToolResultPendingMarker());
      world.flush();

      const flow = DecisionFlow([
        _NamedPolicy('run_graded_goal'),
      ]);
      decisionFlowSystem(
        world..upsertResource(DecisionFlowResource(flow)),
      );
      world.flush();

      // Re-fetch: ecsly facades are stale views after flush-moves.
      final afterFlow = world.getEntity(actor).$1;
      expect(afterFlow.get<ToolRoundCount>()?.value, 7,
          reason: 'a policy re-prompt is the SAME repair cycle — resetting '
              'here made thenOpen flows unbounded (regression guard)');
      expect(afterFlow.get<TotalRoundCount>()?.value, 7);
      expect(afterFlow.get<DecisionOrigin>()?.policyName, 'run_graded_goal');

      // The fresh-budget path is openFreshDecision (host-injected retry).
      openFreshDecision(world, actor, prompt: 'new task');
      final fresh = world.getEntity(actor).$1;
      expect(fresh.get<ToolRoundCount>()?.value ?? 0, 0,
          reason: 'host-injected new tasks start with a full budget');
      expect(fresh.get<TotalRoundCount>()?.value, 7,
          reason: 'lifetime ledger never resets');
    });
  });

  group('J1.5.6 — backend-error retry budget (flight-recorder find)', () {
    test('flaky backend alternating error ↔ tool-calling responses still '
        'exhausts the retry budget (no unbounded loop)', () async {
      // The on-device find: RetryCount was reset by EVERY resolved response,
      // so a backend flapping between "backend_failed" and tool-calling
      // responses retried forever (255× identical prompts live).
      final world = _wiredWorld(handler: _FlakyBackendHandler());
      final (actor, _) = _spawnGoalActor(world, 'build something');

      await HarnessLoop(world: world).runUntilIdle(maxTicks: 5000);
      world.flush();

      // Total generations served is bounded: maxRetries (3) error-retries
      // within the chain + the chain-capped tool rounds — NOT unbounded.
      final served =
          (world.getResource<GenerationHandlerResource>().defaultHandler!
                  as _FlakyBackendHandler)
              .served;
      expect(served, lessThan(30),
          reason: 'the error budget must survive tool-call continuations and '
              'cap the flaky-backend loop at ~maxRetries');
      expectIdle(world);
    });
  });

  group('J1.5.3 — WorldInspector pulse + FlightRecorder', () {
    test('pulse carries the whole decision stack per actor', () async {
      final world = _wiredWorld(
        handler: const NeverRespondingHandler(),
        maxGoalAttempts: 3,
      );
      final (actor, thread) = _spawnGoalActor(world, 'the current task');
      world.getEntity(actor).$1
        ..insert(ToolRoundCount(3))
        ..insert(TotalRoundCount(9))
        ..insert(AttemptCount(2))
        ..insert(GoalVerified(passed: false, detail: 'intents failed: boom'))
        ..insert(const LoopStuck(3))
        ..insert(const ToolResultPendingMarker());
      world.flush();

      final pulse = sampleHarness(world);
      expect(pulse.actors, hasLength(1));
      final a = pulse.actors.single;
      expect(a.hasOpenDecision, isTrue);
      expect(a.decisionPrompt, contains('the current task'));
      expect(a.toolRounds, 3);
      expect(a.maxToolRounds, 16);
      expect(a.totalRounds, 9);
      expect(a.attemptCount, 2);
      expect(a.goalVerified, isFalse);
      expect(a.goalDetail, contains('boom'));
      expect(a.loopStuckStreak, 3);
      expect(pulse.loopWarnings.join(' '), contains('loop-breaker streak'));
      expect(pulse.pendingToolResults, 1);

      // Terminal rendering is the "who is looping" one-paste answer.
      final text = pulse.toText();
      expect(text, contains('LOOP STUCK ×3'));
      expect(text, contains('attempts 2/3'));
      expect(text, contains('goal FAIL'));

      // JSON round-trip (for the Flutter profiler view / flight recorder).
      expect(a.toJson()['toolRounds'], 3);

      // NOTE: intentionally NOT expectIdle — this fixture holds an open
      // decision + pending marker by design (the pulse must see them).
    });

    test('flight recorder detects identical-prompt RE-PROMPT cycles (not '
        'held-open decisions) and wraps its ring buffer', () {
      final recorder = FlightRecorder(capacity: 16);
      ActorPulse actor(String prompt, bool open) => ActorPulse(
            agentId: 'a1',
            hasOpenDecision: open,
            decisionOrigin: open ? 'run_graded_goal' : '',
            decisionPrompt: open ? prompt : '',
          );
      HarnessPulse pulse(String prompt, bool open) => HarnessPulse(
            tick: 1,
            actors: [actor(prompt, open)],
          );

      // Held-open decision across samples (long generation): NOT a loop.
      expect(recorder.record(pulse('fix the code', true)), isEmpty);
      expect(recorder.record(pulse('fix the code', true)), isEmpty);
      expect(recorder.record(pulse('fix the code', true)), isEmpty);

      // Open → closed → open cycles with the SAME prompt: the loop signal.
      // streak starts at 1 (first open); each cycle increments it.
      expect(recorder.record(pulse('fix the code', false)), isEmpty); // close
      expect(recorder.record(pulse('fix the code', true)), isEmpty); // streak 2
      expect(recorder.record(pulse('fix the code', false)), isEmpty); // close
      final warnings = recorder.record(pulse('fix the code', true)); // streak 3
      expect(warnings, hasLength(1));
      expect(warnings.single, contains('ENDLESS-LOOP SUSPECT'));
      expect(warnings.single, contains('3×'));
      expect(warnings.single, contains('run_graded_goal'));

      // A different prompt breaks the streak.
      expect(recorder.record(pulse('escalate', false)), isEmpty);
      expect(recorder.record(pulse('escalate', true)), isEmpty);
      expect(recorder.dump(), contains('escalate'));

      // Ring wrap: capacity 16, we recorded 9.
      expect(recorder.length, 9);
      expect(recorder.dump(), contains('FlightRecorder'));
    });

    test('runUntilIdle appends the flight-recorder dump to the maxTicks '
        'StateError (headless post-mortem)', () async {
      final world = _wiredWorld(handler: const NeverRespondingHandler());
      world.upsertResource(FlightRecorder());
      final (actor, _) = _spawnGoalActor(world, 'stuck task');
      // No registered intent tool AND no responding handler: AwaitResponse
      // sits forever → canSleep() false → maxTicks fires.

      StateError? caught;
      try {
        await HarnessLoop(world: world).runUntilIdle(maxTicks: 30);
      } on StateError catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      expect(caught!.message, contains('exceeded 30 ticks'));
      expect(caught.message, contains('FlightRecorder dump'),
          reason: 'the post-mortem must name what was in flight');
      expect(caught.message, contains('stuck task'));
      // The actor's pending decision appears in the dump.
      expect(world.getEntity(actor).$1.has<AwaitingResponse>(), isTrue);
    });
  });
}

/// Minimal named policy for flow-routing tests.
class _NamedPolicy implements DecisionPolicy {
  const _NamedPolicy(this.name);
  @override
  final String name;
  @override
  DecisionDraft? evaluate(DecisionContext ctx) =>
      DecisionDraft(prompt: 'from $name');
}
