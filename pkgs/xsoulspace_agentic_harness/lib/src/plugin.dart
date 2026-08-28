import 'dart:developer';

import 'package:ecsly/ecsly.dart';
import 'package:ecsly_app/ecsly_app.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'events.dart';
import 'data_models/data_models.dart';
import 'decisions/decision_flow.dart';
import 'narrative/narrative.dart';
import 'meaning/intents.dart' show IntentCallState, IntentRuntime;
import 'meaning/meaning_tree.dart';
import 'resources/resources.dart';
import 'schedules.dart';
import 'systems/systems.dart';

/// Plugin that installs the agent harness into an ecsly [World].
///
/// Registers all components, resources, event channels, and the core
/// schedules for the cinematic multi-actor loop.
class AgentPlugin extends Plugin {
  @override
  void install(World world) {
    // Install async parallel plugin for ScheduleJobResultQueueResource
    world.addPlugin(const AsyncParallelPlugin());

    world.components
      ..registerObjectComponent<Actor>()
      ..registerObjectComponent<ActorModel>()
      ..registerObjectComponent<ActorSystemPrompt>()
      ..registerObjectComponent<ActorTools>()
      ..registerObjectComponent<ActorThreads>()
      ..registerObjectComponent<Agency>()
      ..registerObjectComponent<AwaitingResponse>()
      ..registerObjectComponent<OpenDecision>()
      ..registerObjectComponent<EscalationRequest>()
      ..registerObjectComponent<LoopStuck>()
      ..registerObjectComponent<Scene>()
      ..registerObjectComponent<SceneFrame>()
      ..registerObjectComponent<PresentInScene>()
      ..registerObjectComponent<PresentProp>()
      ..registerObjectComponent<Prop>()
      ..registerObjectComponent<Situation>()
      ..registerObjectComponent<Goal>()
      ..registerObjectComponent<StreamingBeat>()
      // Thread & Beat ontology (from narrative.dart)
      ..registerObjectComponent<Thread>()
      ..registerObjectComponent<ThreadScore>()
      ..registerObjectComponent<ThreadId>()
      ..registerObjectComponent<ThreadStatus>()
      ..registerObjectComponent<ParentScene>()
      ..registerObjectComponent<OriginActor>()
      ..registerObjectComponent<GoalLink>()
      ..registerObjectComponent<DependsOnStep>()
      ..registerObjectComponent<Step>()
      ..registerObjectComponent<DerivedFromThread>()
      ..registerObjectComponent<ThreadVisibility>()
      ..registerObjectComponent<BeatId>()
      ..registerObjectComponent<BelongsToThread>()
      ..registerObjectComponent<BeatSequence>()
      ..registerObjectComponent<Speaker>()
      ..registerObjectComponent<AddressedTo>()
      ..registerObjectComponent<BeatModality>()
      ..registerObjectComponent<BeatStatus>()
      ..registerObjectComponent<ReplyToBeat>()
      ..registerObjectComponent<ObservesProp>()
      ..registerObjectComponent<PrivateToActor>()
      ..registerObjectComponent<TextContent>()
      ..registerObjectComponent<TextStream>()
      ..registerObjectComponent<AudioStream>()
      ..registerObjectComponent<ActionPayload>()
      ..registerObjectComponent<BeatToolCall>()
      ..registerObjectComponent<ToolResult>()
      ..registerObjectComponent<ThoughtContent>()
      ..registerObjectComponent<ObservationData>()
      // Memory summary provenance (deliberate graph transforms only)
      ..registerObjectComponent<MemorySummary>()
      ..registerObjectComponent<SummaryOwner>()
      ..registerObjectComponent<SummaryThread>()
      ..registerObjectComponent<SummarizesBeats>()
      ..registerObjectComponent<ToolResultContent>()
      ..registerObjectComponent<IdentityBeat>()
      ..registerObjectComponent<RetryCount>()
      ..registerObjectComponent<RetryCount>()
      ..registerObjectComponent<ToolRoundCount>()
      ..registerObjectComponent<IdentitySeeded>()
      ..registerObjectComponent<DecisionOrigin>()
      ..registerObjectComponent<DeferredThinking>()
      ..registerObjectComponent<ToolResultPendingMarker>()
      // ADR 0009 plan-frontier components (live in data_models).
      ..registerObjectComponent<GoalVerified>()
      ..registerObjectComponent<StepStatus>()
      ..registerObjectComponent<StepGoalLink>()
      ..registerObjectComponent<ActorGoalRef>()
      ..registerObjectComponent<IdleNudgeCount>()
      ..registerObjectComponent<StepClaim>()
      ..registerObjectComponent<StepAction>()
      ..registerObjectComponent<StepIndex>()
      // Meaning tree (PLAN Stage F): nodes are entities, edges/props are
      // components — projected per decision, never loaded whole.
      //
      // INVARIANT: every Component class must be registered here.
      // An unregistered object component co-spawning with registered ones
      // corrupts ecsly archetype column allocation ("Column should exist
      // after archetype creation").
      ..registerObjectComponent<MeaningNode>()
      ..registerObjectComponent<MeaningProps>()
      ..registerObjectComponent<MeaningEdge>();

    // Resources
    world
      ..upsertResource(TaskRegistryResource())
      ..upsertResource(GenerationHandlerResource())
      ..upsertResource(StreamingTapResource())
      ..upsertResource(ProjectionBudget())
      ..upsertResource(ProjectionPolicy())
      ..upsertResource(FacetIndex())
      ..upsertResource(AgencyPolicy())
      ..upsertResource(ToolExecutorResource())
      ..upsertResource(DecisionFlowResource(DecisionFlow.defaultReAct()))
      ..upsertResource(MeaningIndex())
      ..upsertResource(IntentRuntime())
      ..upsertResource(IntentCallState());

    // Event channels for async LLM I/O.
    //
    // Capacity is sized above the default because a single tick can produce
    // many events (N actors × tool calls). The default policy `dropNew` would
    // silently drop overflow events — which dangles tasks and hangs actors —
    // so these channels use `dropOld` plus an overflow metrics hook.
    void registerChannel<T extends EcsEvent>() => world.events.register<T>(
      capacity: 256,
      capacityPolicy: EventCapacityPolicy.dropOld,
      metricsHook: (overflow) {
        // Surfaced via dart:developer log; ScenarioRunner/MetricsCollector
        // can also detect dangling tools downstream.
        log(
          'EventChannel<${T}> overflow: dropped '
          '${overflow.dropped ? "new" : "old"} event',
        );
      },
    );
    registerChannel<ActorGenerateRequest>();
    registerChannel<ActorGenerateResponse>();
    registerChannel<ActorGenerateStreamEvent>();
    registerChannel<ToolCallEvent>();
    registerChannel<ToolResultEvent>();

    // Schedules — the cinematic multi-actor loop
    //
    // 1. AgencyGrant: grant Agency to actors with OpenDecision
    // 2. Project: build minimal Situations for actors with Agency
    // 3. ActorAct: dispatch generation requests (fire-and-forget)
    // 4. ProcessResponses: handle LLM responses, dispatch tool calls
    // 5. Mechanical: execute tools, score/prune threads
    // 6. Narrative: advance Thread/Beat playheads, finalize partials
    world.createSchedule(Schedules.agencyGrant)
      ..add(decisionFlowSystem, name: 'decisionFlow')
      ..then(grantAgencySystem, name: 'grantAgency')
      ..then(flushAllSystem, name: 'flushAfterGrant');

    world.createSchedule(Schedules.project)
      ..add(seedIdentitySystem, name: 'seedIdentity')
      ..then(projectSituationSystem, name: 'projectSituation')
      ..then(flushAllSystem, name: 'flushAfterProject');

    world.createSchedule(Schedules.actorAct)
      ..add(actorActSystem, name: 'actorAct', mode: ExecutionMode.asyncParallel)
      ..then(flushAllSystem, name: 'flushAfterAct');

    world.createSchedule(Schedules.processResponses)
      ..add(processStreamEventsSystem, name: 'processStreamEvents')
      ..then(taskTimeoutSweeperSystem, name: 'taskTimeoutSweeper')
      ..then(processResponsesSystem, name: 'processResponses')
      ..then(flushAllSystem, name: 'flushAfterResponses');

    world.createSchedule(Schedules.mechanical)
      ..add(toolExecutionSystem, name: 'toolExecution')
      ..then(processToolResultsSystem, name: 'processToolResults')
      ..then(loopBreakerSystem, name: 'loopBreaker')
      ..then(verifyStepSystem, name: 'verifyStep')
      ..then(scoreThreadsSystem, name: 'scoreThreads')
      ..then(pruneThreadsSystem, name: 'pruneThreads')
      ..then(mergeThreadsSystem, name: 'mergeThreads')
      ..then(flushAllSystem, name: 'flushAfterMechanical');

    world.createSchedule(Schedules.narrative)
      ..add(finalizePartialsSystem, name: 'finalizePartials')
      ..then(flushAllSystem, name: 'flushAfterNarrative');
  }

  @override
  String get name => 'agent-plugin';
}
