/// Non-blocking, concurrent agent harness loop.
///
/// Runs the agent schedules at a fixed timestep and enters event-driven
/// sleep when no work remains. It is a pure schedule driver — it knows
/// nothing about LLM handlers, tools, or I/O. All async work is owned by
/// the world via [TaskRegistryResource] and the agent schedules.
///
/// ## Flutter integration
///
/// For Flutter apps, prefer [EcsFixedStepLoop] from `ecsly_flutter` which
/// drives the same schedules on the Flutter frame ticker. This [HarnessLoop]
/// is for headless/CLI use or when you need full control over the loop.
///
/// ## Concurrency model
///
/// `ActorAct` dispatches all generation requests concurrently (fire-and-forget
/// via the sync executor's `asyncParallel` mode). The loop continues ticking.
/// `ProcessResponses` processes whatever responses arrived on each tick.
/// The loop NEVER blocks on a single LLM call.
///
/// ## Idle/sleep
///
/// The loop sleeps when there is no work:
/// - No `OpenDecision`s
/// - No `Agency`
/// - No `AwaitingResponse`
/// - No in-flight tasks in [TaskRegistryResource]
///
/// Sleep is event-driven: a [Completer] is completed when [wakeup] is called
/// (e.g., when a new `OpenDecision` is created by an external event, or a
/// handler sends a response). This avoids busy-polling.
library;

import 'dart:async';

import 'package:ecsly/ecsly.dart';

import 'data_models/data_models.dart';
import 'events.dart';
import 'resources/resources.dart';
import 'schedules.dart';
import 'systems/decision_flow_system.dart' show ToolResultPendingMarker;

/// Non-blocking, concurrent agent harness loop.
///
/// Runs the agent schedules and enters event-driven sleep when no work
/// remains. Handlers and I/O live in the world as resources; this loop only
/// drives schedules and flushes.
class HarnessLoop {
  /// Create a new [HarnessLoop].
  HarnessLoop({required this.world, this.fixedDt = 1 / 60});

  /// The ECS world to run the loop on.
  final World world;

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
  /// 3. Check if the loop can sleep
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

  /// Drive schedules until the world is idle (no open decisions, no agency,
  /// no awaiting responses, no in-flight tasks), then return.
  ///
  /// This is the CLI/server entry point: spawn actors with [OpenDecision]s,
  /// call this, and read the resulting beats when it completes. A safety cap
  /// ([maxTicks]) guards against a world that keeps producing work forever —
  /// pass `null` for unbounded runs you control via [stop].
  Future<void> runUntilIdle({int? maxTicks = 2000000}) async {
    var ticks = 0;
    while (!canSleep()) {
      if (maxTicks != null && ticks >= maxTicks) {
        throw StateError(
          'HarnessLoop.runUntilIdle exceeded $maxTicks ticks without going '
          'idle. The world keeps producing work — check for retry loops or '
          'self-spawning decisions.',
        );
      }
      ticks++;
      _tick();
      // Yield AND pace: Duration.zero alone busy-spins millions of iterations
      // while an async generation/tool task is in flight (on-device models
      // take seconds), tripping the maxTicks safety cap during perfectly
      // healthy waits. 1ms keeps wake-up latency negligible for microtask
      // worlds while bounding tick burnout to ~1000/s.
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    world.flush();
  }

  /// Run one tick of the agent loop.
  ///
  /// Executes all schedules in order. Handlers receive requests through the
  /// world's event channels and send responses back; the loop does not poll
  /// them directly.
  /// One schedule pass, exposed for host-driven tracing/debug loops.
  void tickForDebug() => _tick();

  void _tick() {
    // 1. Advance the schedule execution frame so that
    //    ScheduleJobResultQueueResource can pipeline across frames.
    syncScheduleExecutionFrame(world);

    // 2. Run all schedules in deterministic order. If the world was cleared
    //    (e.g. a host switched scenarios and called world.clear()), the
    //    schedules are gone — stop the loop instead of crashing on a missing
    //    schedule.
    if (!world.hasSchedule(Schedules.agencyGrant)) {
      _running = false;
      return;
    }
    world.runSchedule(Schedules.agencyGrant);
    world.runSchedule(Schedules.project);
    world.runSchedule(Schedules.actorAct); // asyncParallel — fire-and-forget
    world.runSchedule(Schedules.processResponses);
    world.runSchedule(Schedules.mechanical);
    world.runSchedule(Schedules.narrative);

    // 3. Flush all pending entity/component changes
    world.flush();
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
  /// - No in-flight tasks in [TaskRegistryResource]
  /// Check if the loop can sleep (no work remaining).
  ///
  /// Returns true when:
  /// - No actors with `OpenDecision`
  /// - No actors with `Agency`
  /// - No actors with `AwaitingResponse`
  /// - No in-flight tasks in [TaskRegistryResource]
  /// - No unconsumed events on harness channels
  ///
  /// The channel check closes a race: an async tool completes, sends its
  /// [ToolResultEvent], and resolves its task in the same microtask. Between
  /// that moment and the next `Mechanical` pass (which turns the event into
  /// a beat), the task registry is empty — but the result still needs one
  /// more tick to be processed. Without this check, runUntilIdle exited and
  /// stranded tool results in the channel.
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

    final hasInFlightTasks = !world.getResource<TaskRegistryResource>().isEmpty;

    // Unconsumed harness events are pending work by definition.
    final hasPendingEvents = world.events.reader<ToolResultEvent>().isNotEmpty;

    // A pending decision-flow trigger is work: the next AgencyGrant pass
    // must run to evaluate it (ADR 0005), otherwise runUntilIdle exits with
    // a continuation decision never opened.
    final hasPendingFlowTriggers = world
        .query2<Actor, ToolResultPendingMarker>()
        .toList()
        .isNotEmpty;

    return !hasOpenDecisions &&
        !hasAgency &&
        !hasAwaiting &&
        !hasInFlightTasks &&
        !hasPendingEvents &&
        !hasPendingFlowTriggers;
  }
}
