/// Non-blocking, concurrent agent harness loop.
///
/// Runs the agent schedules at a fixed timestep, polls the external
/// [ActorGenerateHandler] for LLM responses, and enters event-driven
/// sleep when no work remains.
///
/// ## Concurrency model
///
/// `ActorAct` dispatches all LLM calls concurrently (fire-and-forget via
/// sync executor's `asyncParallel` mode). The loop continues ticking.
/// `ProcessResponses` processes whatever responses arrived on each tick.
/// The loop NEVER blocks on a single LLM call.
///
/// ## Idle/sleep
///
/// The loop sleeps when there is no work:
/// - No `OpenDecision`s
/// - No `Agency`
/// - No `AwaitingResponse`
/// - No in-flight jobs in `ScheduleJobResultQueueResource`
///
/// Sleep is event-driven: a [Completer] is completed when [wakeup] is called
/// (e.g., when a new `OpenDecision` is created by an external event).
/// This avoids busy-polling.
library;

import 'dart:async';

import 'package:ecsly/ecsly.dart';
import 'package:ecsly_async_parallel/ecsly_async_parallel.dart';

import 'agent_plugin.dart';

/// Non-blocking, concurrent agent harness loop.
///
/// Runs the agent schedules at a fixed timestep, polls the external
/// [ActorGenerateHandler] for LLM responses, and enters event-driven
/// sleep when no work remains.
class HarnessLoop {
  /// Create a new [HarnessLoop].
  ///
  /// The [handler] is polled on each tick via
  /// [ActorGenerateHandler.processPending].
  HarnessLoop({
    required this.world,
    required this.handler,
    this.fixedDt = 1 / 60,
  });

  /// The ECS world to run the loop on.
  final World world;

  /// The external handler that processes LLM requests.
  final ActorGenerateHandler handler;

  /// Fixed timestep in seconds (default 60Hz).
  final double fixedDt;

  /// Whether the loop is currently running.
  bool _running = false;

  /// Completer that completes when new work arrives while the loop is asleep.
  Completer<void>? _wakeupCompleter;

  /// Start the loop.
  ///
  /// The loop runs until [stop] is called or [until] completes.
  /// On each tick:
  /// 1. Advance the schedule execution frame
  /// 2. Run all agent schedules in order
  /// 3. Poll the handler for pending LLM requests
  /// 4. Check if the loop can sleep
  Future<void> start({Future<void>? until}) async {
    _running = true;

    // Listen for stop signal
    if (until != null) {
      unawaited(until.then((_) => stop()));
    }

    // Main loop
    while (_running) {
      _tick();

      if (canSleep()) {
        // Event-driven sleep: await wakeup signal
        _wakeupCompleter = Completer<void>();
        await _wakeupCompleter!.future;
        _wakeupCompleter = null;
      } else {
        // Continue ticking at fixed rate
        await Future.delayed(Duration(milliseconds: (fixedDt * 1000).toInt()));
      }
    }
  }

  /// Stop the loop.
  void stop() {
    _running = false;
    _wakeupCompleter?.complete();
    _wakeupCompleter = null;
  }

  /// Run one tick of the agent loop.
  ///
  /// Executes all schedules in order, then polls the handler.
  void _tick() {
    // 1. Advance the schedule execution frame so that
    //    ScheduleJobResultQueueResource can pipeline across frames.
    syncScheduleExecutionFrame(world);

    // 2. Run all schedules in deterministic order
    world.runSchedule('AgencyGrant');
    world.runSchedule('Project');
    world.runSchedule('ActorAct'); // asyncParallel — fire-and-forget
    world.runSchedule('ProcessResponses');
    world.runSchedule('Mechanical');
    world.runSchedule('Narrative');

    // 3. Flush all pending entity/component changes
    world.flush();

    // 4. Poll the handler — drain request channel, send responses
    //    (fire-and-forget: the handler's async work is tracked via
    //    ScheduleJobResultQueueResource and AwaitingResponse)
    unawaited(handler.processPending(world));
  }

  /// Wake up the loop from sleep.
  ///
  /// Called by the host application when new work arrives (e.g., a new
  /// `OpenDecision` is created, or an external event is injected into the
  /// world). If the loop is not sleeping, this is a no-op.
  void wakeup() {
    if (_wakeupCompleter != null && !_wakeupCompleter!.isCompleted) {
      _wakeupCompleter!.complete();
      _wakeupCompleter = null;
    }
  }

  /// Check if the loop can sleep (no work remaining).
  ///
  /// Returns true when:
  /// - No actors with `OpenDecision`
  /// - No actors with `Agency`
  /// - No actors with `AwaitingResponse`
  /// - No in-flight jobs in `ScheduleJobResultQueueResource`
  bool canSleep() {
    final hasOpenDecisions = world
        .query2<Actor, OpenDecision>()
        .toList()
        .isNotEmpty;
    final hasAgency = world.query2<Actor, Agency>().toList().isNotEmpty;
    final hasAwaiting = world
        .query2<Actor, AwaitingResponse>()
        .toList()
        .isNotEmpty;

    final hasInFlight =
        world.resources.has<ScheduleJobResultQueueResource>() &&
        world.getResource<ScheduleJobResultQueueResource>().hasInFlightJob(
          'actorAct',
        );

    return !hasOpenDecisions && !hasAgency && !hasAwaiting && !hasInFlight;
  }
}
