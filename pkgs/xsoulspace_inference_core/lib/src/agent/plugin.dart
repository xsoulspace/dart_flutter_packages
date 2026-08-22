import 'dart:developer';

import 'package:ecsly/ecsly.dart';
import 'package:ecsly_app/ecsly_app.dart';
import 'package:ecsly_async_parallel/ecsly_async_parallel.dart';

import 'events.dart';
import 'data_models/data_models.dart';
import 'narrative.dart';
import 'resources/resources.dart';
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
      ..registerObjectComponent<RetryCount>();

    // Resources
    world
      ..upsertResource(TaskRegistryResource())
      ..upsertResource(GenerationHandlerResource())
      ..upsertResource(ProjectionBudget())
      ..upsertResource(ProjectionPolicy())
      ..upsertResource(FacetIndex())
      ..upsertResource(AgencyPolicy());

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
    world.createSchedule('AgencyGrant')
      ..add(grantAgencySystem, name: 'grantAgency')
      ..then(flushAllSystem, name: 'flushAfterGrant');

    world.createSchedule('Project')
      ..add(seedIdentitySystem, name: 'seedIdentity')
      ..then(projectSituationSystem, name: 'projectSituation')
      ..then(flushAllSystem, name: 'flushAfterProject');

    world.createSchedule('ActorAct')
      ..add(actorActSystem, name: 'actorAct', mode: ExecutionMode.asyncParallel)
      ..then(flushAllSystem, name: 'flushAfterAct');

    world.createSchedule('ProcessResponses')
      ..add(processStreamEventsSystem, name: 'processStreamEvents')
      ..then(taskTimeoutSweeperSystem, name: 'taskTimeoutSweeper')
      ..then(processResponsesSystem, name: 'processResponses')
      ..then(flushAllSystem, name: 'flushAfterResponses');

    world.createSchedule('Mechanical')
      ..add(toolExecutionSystem, name: 'toolExecution')
      ..then(processToolResultsSystem, name: 'processToolResults')
      ..then(scoreThreadsSystem, name: 'scoreThreads')
      ..then(pruneThreadsSystem, name: 'pruneThreads')
      ..then(mergeThreadsSystem, name: 'mergeThreads')
      ..then(flushAllSystem, name: 'flushAfterMechanical');

    world.createSchedule('Narrative')
      ..add(finalizePartialsSystem, name: 'finalizePartials')
      ..then(flushAllSystem, name: 'flushAfterNarrative');
  }

  @override
  String get name => 'agent-plugin';
}
