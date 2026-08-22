// ignore_for_file: lines_longer_than_80_chars

/// Dev-only per-tick execution ledger for the agent harness.
///
/// An [EcsExecutionObserver] that records, per tick: schedule/system names,
/// durations, and harness event-channel drain counts before/after each
/// schedule. Dump it (or let a test dump it on failure) and you can see
/// exactly which schedule consumed which events — the "Mechanical ran,
/// ToolResultEvent went 0→0, then loop exited" class of bug becomes visible
/// in one log instead of an afternoon of bisection.
///
/// Usage (debug builds / tests only — it allocates):
///
/// ```dart
/// final ledger = HarnessExecutionLedger(world);
/// world.executionObserver = ledger;
/// await HarnessLoop(world: world).runUntilIdle();
/// debugPrint(ledger.dump()); // or print in tests
/// ```
library;

import 'package:ecsly/ecsly.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// One observed system execution within a schedule.
class LedgerEntry {
  LedgerEntry._({
    required this.tick,
    required this.schedule,
    required this.system,
    required this.elapsedMicroseconds,
    required this.channelCountsBefore,
    required this.channelCountsAfter,
    this.error,
  });

  /// Tick index (incremented at each [HarnessLoop] schedule pass start).
  final int tick;
  final String schedule;
  final String system;
  final int elapsedMicroseconds;
  final Object? error;

  /// Harness channel lengths before this system ran.
  final Map<String, int> channelCountsBefore;

  /// Harness channel lengths after this system ran.
  final Map<String, int> channelCountsAfter;
}

/// Records per-system executions with before/after harness channel counts.
class HarnessExecutionLedger extends EcsExecutionObserverBase {
  HarnessExecutionLedger(this.world);

  final World world;
  final List<LedgerEntry> entries = [];

  int _tick = 0;
  Map<String, int>? _scheduleStartCounts;

  /// Channels tracked by the ledger, in drain order.
  static const _trackedChannels = <String, void Function(World)>{
    'ActorGenerateRequest': _len<ActorGenerateRequest>,
    'ActorGenerateResponse': _len<ActorGenerateResponse>,
    'ActorGenerateStreamEvent': _len<ActorGenerateStreamEvent>,
    'ToolCallEvent': _len<ToolCallEvent>,
    'ToolResultEvent': _len<ToolResultEvent>,
  };

  static int _len<T extends EcsEvent>(World w) =>
      w.events.hasRegistered<T>() ? w.events.reader<T>().length : -1;

  Map<String, int> _snapshot() => {
    for (final name in _trackedChannels.keys) name: _lenFor(name),
  };

  int _lenFor(String name) => switch (name) {
    'ActorGenerateRequest' => _len<ActorGenerateRequest>(world),
    'ActorGenerateResponse' => _len<ActorGenerateResponse>(world),
    'ActorGenerateStreamEvent' => _len<ActorGenerateStreamEvent>(world),
    'ToolCallEvent' => _len<ToolCallEvent>(world),
    'ToolResultEvent' => _len<ToolResultEvent>(world),
    _ => -1,
  };

  /// Call once per loop pass to advance the tick counter.
  void beginTick() {
    _tick++;
  }

  @override
  void onScheduleStart(
    final World world,
    final String scheduleName, {
    required final int systemCount,
  }) {
    _scheduleStartCounts = _snapshot();
  }

  @override
  void onSystemStart(
    final World world,
    final String scheduleName,
    final SystemDescriptor system,
  ) {}

  @override
  void onSystemEnd(
    final World world,
    final String scheduleName,
    final SystemDescriptor system, {
    required final int elapsedMicroseconds,
    final Object? error,
    final StackTrace? stackTrace,
  }) {
    entries.add(
      LedgerEntry._(
        tick: _tick,
        schedule: scheduleName,
        system: system.name ?? '<anon>',
        elapsedMicroseconds: elapsedMicroseconds,
        channelCountsBefore: _scheduleStartCounts ?? const {},
        channelCountsAfter: _snapshot(),
        error: error,
      ),
    );
  }

  /// Human-readable trace of every recorded entry.
  ///
  /// Only prints channels whose count changed across the schedule, so the
  /// interesting lines are dense:
  ///
  /// ```
  /// tick 3 | ProcessResponses.processResponses | 120µs
  ///   ActorGenerateResponse 1→0, ToolCallEvent 0→1
  /// ```
  String dump() {
    final b = StringBuffer();
    for (final e in entries) {
      b.write(
        'tick ${e.tick} | ${e.schedule}.${e.system} '
        '| ${e.elapsedMicroseconds}µs',
      );
      if (e.error != null) b.write(' | ERROR: ${e.error}');
      b.writeln();

      final changes = <String>[];
      for (final name in _trackedChannels.keys) {
        final before = e.channelCountsBefore[name];
        final after = e.channelCountsAfter[name];
        if (before != null && after != null && before != after) {
          changes.add('$name $before→$after');
        }
      }
      if (changes.isNotEmpty) {
        b.writeln('  ${changes.join(', ')}');
      }
    }
    return b.toString();
  }

  /// Clear recorded entries (e.g., between test phases).
  void reset() => entries.clear();
}
