// ignore_for_file: lines_longer_than_80_chars

/// Runtime observability (J1.5.3): a live, LLM-free view of the whole
/// harness — "the Flutter profiler for the agent loop".
///
/// - [sampleHarness] reads ONLY world state (no model calls, no side
///   effects) and emits a [HarnessPulse]: per-actor decision stack, round
///   budgets, retry/attempt counts, loop streaks, verification verdicts,
///   last tool call/result, and world-level work counts.
/// - [FlightRecorder] is a ring buffer of pulses with a repetition
///   detector: an identical decision prompt repeating across consecutive
///   samples IS the endless loop — it names the prompt instead of making
///   you bisect. Dump it on maxTicks StateError / SIGINT so headless runs
///   ship failure data (standing rule: failures are data).
///
/// Consumption: poll [sampleHarness] on a Timer (Flutter profiler view),
/// print `pulse.toText()` from a host loop (terminal profiler), or attach a
/// [FlightRecorder] and let `HarnessLoop.runUntilIdle` auto-sample.
library;

import 'dart:convert';

import 'package:ecsly/ecsly.dart';

import '../data_models/data_models.dart';
import '../decisions/decision_flow.dart' show DecisionOrigin;
import '../narrative/narrative.dart';
import '../resources/resources.dart';
import '../systems/decision_flow_system.dart' show ToolResultPendingMarker;

// ---------------------------------------------------------------------------
// Pulse data shapes (plain data — renderable anywhere)
// ---------------------------------------------------------------------------

/// One actor's live decision stack (J1.5.3).
class ActorPulse {
  ActorPulse({
    required this.agentId,
    this.hasOpenDecision = false,
    this.decisionPrompt = '',
    this.decisionOrigin = '',
    this.toolRounds = 0,
    this.maxToolRounds = 0,
    this.totalRounds = 0,
    this.retryCount = 0,
    this.attemptCount = 0,
    this.maxGoalAttempts = 0,
    this.goalAttemptsExhausted = false,
    this.exhaustionReason = '',
    this.escalationRequested = false,
    this.goalVerified,
    this.goalDetail = '',
    this.loopStuckStreak,
    this.awaitingResponse = false,
    this.threadStatuses = const [],
    this.lastToolName,
    this.lastToolSignature,
    this.lastToolOk,
    this.lastToolError,
  });

  final String agentId;
  final bool hasOpenDecision;
  final String decisionPrompt;
  final String decisionOrigin;
  final int toolRounds;
  final int maxToolRounds;
  final int totalRounds;
  final int retryCount;
  final int attemptCount;
  final int maxGoalAttempts;
  final bool goalAttemptsExhausted;
  final String exhaustionReason;
  final bool escalationRequested;
  /// null = never verified; true/false = last mechanical verdict.
  final bool? goalVerified;
  final String goalDetail;
  /// Non-null when the loop breaker has stamped [LoopStuck].
  final int? loopStuckStreak;
  final bool awaitingResponse;
  final List<String> threadStatuses;
  final String? lastToolName;
  /// `toolName:argsHash` — the loop signature to grep the ledger for.
  final String? lastToolSignature;
  final bool? lastToolOk;
  final String? lastToolError;

  Map<String, Object?> toJson() => {
    'agentId': agentId,
    'hasOpenDecision': hasOpenDecision,
    if (decisionPrompt.isNotEmpty) 'decisionPrompt': decisionPrompt,
    if (decisionOrigin.isNotEmpty) 'decisionOrigin': decisionOrigin,
    'toolRounds': toolRounds,
    'maxToolRounds': maxToolRounds,
    'totalRounds': totalRounds,
    'retryCount': retryCount,
    'attemptCount': attemptCount,
    'maxGoalAttempts': maxGoalAttempts,
    if (goalAttemptsExhausted) 'goalAttemptsExhausted': true,
    if (exhaustionReason.isNotEmpty) 'exhaustionReason': exhaustionReason,
    if (escalationRequested) 'escalationRequested': true,
    if (goalVerified != null) 'goalVerified': goalVerified,
    if (goalDetail.isNotEmpty) 'goalDetail': goalDetail,
    if (loopStuckStreak != null) 'loopStuckStreak': loopStuckStreak,
    if (awaitingResponse) 'awaitingResponse': true,
    'threadStatuses': threadStatuses,
    if (lastToolName != null) 'lastToolName': lastToolName,
    if (lastToolSignature != null) 'lastToolSignature': lastToolSignature,
    if (lastToolOk != null) 'lastToolOk': lastToolOk,
    if (lastToolError != null) 'lastToolError': lastToolError,
  };

  /// Terminal-profile rendering: one actor block.
  String toText() {
    final b = StringBuffer(agentId);
    b.write(hasOpenDecision ? '  [decision open' : '  [idle');
    if (decisionOrigin.isNotEmpty) b.write(' via $decisionOrigin');
    b.write(']');
    if (awaitingResponse) b.write('  generating…');
    b.write('  rounds $toolRounds/$maxToolRounds (Σ$totalRounds)');
    if (attemptCount > 0) {
      b.write('  attempts $attemptCount'
          '${maxGoalAttempts > 0 ? '/$maxGoalAttempts' : ''}'
          '${goalAttemptsExhausted ? ' EXHAUSTED' : ''}');
    }
    if (goalVerified != null) {
      b.write(goalVerified! ? '  goal PASS' : '  goal FAIL');
    }
    if (loopStuckStreak != null) b.write('  ⚠ LOOP STUCK ×$loopStuckStreak');
    if (lastToolName != null) {
      b.write('\n    last: $lastToolSignature → '
          '${lastToolOk == null ? '?' : lastToolOk! ? 'ok' : 'FAILED'}');
      if (lastToolError != null) b.write('\n      error: $lastToolError');
    }
    if (decisionPrompt.isNotEmpty) b.write('\n    prompt: $decisionPrompt');
    return '$b';
  }
}

/// A world-wide snapshot: the current stack of the whole harness.
class HarnessPulse {
  HarnessPulse({
    required this.tick,
    this.actors = const [],
    this.openDecisions = 0,
    this.inFlightTasks = 0,
    this.pendingToolResults = 0,
    this.loopWarnings = const [],
  });

  final int tick;
  final List<ActorPulse> actors;
  final int openDecisions;
  final int inFlightTasks;
  final int pendingToolResults;
  /// Loop-smoke detector output: loop-breaker streaks, attempt exhaustion,
  /// and (via the flight recorder) repeated identical decision prompts.
  final List<String> loopWarnings;

  Map<String, Object?> toJson() => {
    'tick': tick,
    'openDecisions': openDecisions,
    'inFlightTasks': inFlightTasks,
    'pendingToolResults': pendingToolResults,
    if (loopWarnings.isNotEmpty) 'loopWarnings': loopWarnings,
    'actors': [for (final a in actors) a.toJson()],
  };

  String toJsonString() => jsonEncode(toJson());

  /// Terminal-profile rendering — paste this into an issue and it IS the
  /// "what's the harness doing right now" answer.
  String toText() {
    final b = StringBuffer(
      'tick $tick | decisions $openDecisions | in-flight $inFlightTasks | '
      'pending results $pendingToolResults',
    );
    for (final w in loopWarnings) {
      b.write('\n⚠ $w');
    }
    for (final a in actors) {
      b.write('\n— ${a.toText()}');
    }
    return '$b';
  }
}

// ---------------------------------------------------------------------------
// Sampler — reads world state, side-effect free
// ---------------------------------------------------------------------------

String _signature(Map<String, dynamic> args) {
  if (args.isEmpty) return '';
  final canonical = jsonEncode(args);
  return canonical.length <= 60
      ? canonical
      : '${canonical.substring(0, 57)}…';
}

String _short(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max - 3)}…';

bool _isFailure(ToolResultContent? result) {
  if (result == null) return false;
  final output = result.output;
  if (output is Map) {
    if (output.containsKey('error')) return true;
    return output['ok'] == false;
  }
  final text = '$output';
  return text.contains('"error"') || text.contains('"ok":false');
}

/// Samples the whole harness into a [HarnessPulse]. Reads only world state
/// (components + resources); deterministic, no wall clock (tick comes from
/// the schedule frame id, or pass it explicitly).
HarnessPulse sampleHarness(World world, {int? tick}) {
  var frame = tick ?? -1;
  try {
    frame = tick ?? world
        .getResource<ScheduleExecutionPolicyResource>()
        .frameId;
  } on StateError {
    // not wired (e.g. sampled outside a running loop) — keep -1
  }

  var maxToolRounds = 16;
  var maxGoalAttempts = 3;
  try {
    final policy = world.getResource<AgencyPolicy>();
    maxToolRounds = policy.maxToolRounds;
    maxGoalAttempts = policy.maxGoalAttempts;
  } on StateError {
    // defaults
  }

  final actors = <ActorPulse>[];
  final warnings = <String>[];
  var openDecisions = 0;
  var pendingToolResults = 0;

  for (final (facade, actor, _)
      in world.query2<Actor, ActorModel>().toList()) {
    final we = world.getEntity(facade.entity).$1;
    final decision = we.get<OpenDecision>();
    final hasDecision = decision != null;
    if (hasDecision) openDecisions++;
    if (we.has<ToolResultPendingMarker>()) pendingToolResults++;

    // Last tool call + result from the actor's thread beats (durable record).
    String? lastName;
    String? lastSig;
    bool? lastOk;
    String? lastError;
    final facetIndex = _tryGet<FacetIndex>(world);
    final threads = we.get<ActorThreads>()?.threads ?? const <Entity>[];
    if (facetIndex != null) {
      for (final t in threads) {
        for (final beat in facetIndex.beatsOfThread(t).toList().reversed) {
          final bwe = world.getEntity(beat).$1;
          final call = bwe.get<BeatToolCall>();
          if (call == null) continue;
          lastName = call.name;
          lastSig = '${call.name}:${_signature(call.args)}';
          final result = bwe.get<ToolResultContent>();
          lastOk = result == null ? null : !_isFailure(result);
          if (lastOk == false) lastError = _short('${result!.output}', 120);
          break;
        }
        if (lastName != null) break;
      }
    }

    final exhausted = we.get<GoalAttemptsExhausted>();
    if (exhausted != null) {
      warnings.add('actor ${actor.agentId}: goal-attempt budget exhausted — '
          '${exhausted.reason}');
    }
    final loopStuck = we.get<LoopStuck>();
    if (loopStuck != null) {
      warnings.add('actor ${actor.agentId}: loop-breaker streak '
          '${loopStuck.streak} (repeated failing tool calls)');
    }

    final threadStatuses = [
      for (final t in threads)
        () {
          final (_, valid) = world.getEntity(t);
          if (!valid) return 'gone';
          return world.getEntity(t).$1.get<ThreadStatus>()?.value.name ??
              'unknown';
        }(),
    ];

    actors.add(
      ActorPulse(
        agentId: '${actor.agentId}',
        hasOpenDecision: hasDecision,
        decisionPrompt: decision == null ? '' : _short(decision.prompt, 120),
        decisionOrigin: _short(we.get<DecisionOrigin>()?.policyName ?? '', 40),
        toolRounds: we.get<ToolRoundCount>()?.value ?? 0,
        maxToolRounds: maxToolRounds,
        totalRounds: we.get<TotalRoundCount>()?.value ?? 0,
        retryCount: we.get<RetryCount>()?.value ?? 0,
        attemptCount: we.get<AttemptCount>()?.value ?? 0,
        maxGoalAttempts: maxGoalAttempts,
        goalAttemptsExhausted: exhausted != null,
        exhaustionReason: exhausted == null ? '' : exhausted.reason,
        escalationRequested: we.has<EscalationRequest>(),
        goalVerified: we.get<GoalVerified>()?.passed,
        goalDetail: _short(we.get<GoalVerified>()?.detail ?? '', 120),
        loopStuckStreak: loopStuck?.streak,
        awaitingResponse: we.has<AwaitingResponse>(),
        threadStatuses: threadStatuses,
        lastToolName: lastName,
        lastToolSignature: lastSig,
        lastToolOk: lastOk,
        lastToolError: lastError,
      ),
    );
  }

  var inFlight = 0;
  try {
    inFlight = world.getResource<TaskRegistryResource>().length;
  } on StateError {
    // no task registry wired
  }

  return HarnessPulse(
    tick: frame,
    actors: actors,
    openDecisions: openDecisions,
    inFlightTasks: inFlight,
    pendingToolResults: pendingToolResults,
    loopWarnings: warnings,
  );
}

T? _tryGet<T extends Resource>(World world) {
  try {
    return world.getResource<T>();
  } on StateError {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Flight recorder — ring buffer + repetition detector
// ---------------------------------------------------------------------------

/// Ring buffer of [HarnessPulse]s with the endless-loop detector: the same
/// actor re-opening an IDENTICAL decision prompt after it has been closed
/// is a re-prompt loop (e.g. a policy re-prompting a failing verifier).
/// A decision merely HELD open across samples (long generation in flight)
/// is NOT a repeat — the detector counts open→closed→open cycles, not
/// consecutive snapshots (on-device find: a 60s generation sampled every
/// 100 ticks looked like a 163× loop without this distinction).
///
/// Register it as a resource and `HarnessLoop.runUntilIdle` auto-samples it
/// and appends the dump to its maxTicks StateError — headless runs leave a
/// post-mortem instead of a silent hang.
class FlightRecorder extends Resource {
  FlightRecorder({this.capacity = 256, this.promptRepeatThreshold = 3});

  final int capacity;
  final int promptRepeatThreshold;

  final List<HarnessPulse> _ring = [];
  final Map<String, _LoopTrack> _tracks = {};

  int get length => _ring.length;

  /// Records a pulse and returns any NEW loop warnings it detected.
  List<String> record(HarnessPulse pulse) {
    if (_ring.length == capacity) _ring.removeAt(0);
    _ring.add(pulse);
    final newWarnings = <String>[];
    for (final a in pulse.actors) {
      if (!a.hasOpenDecision || a.decisionPrompt.isEmpty) {
        // Decision closed (or actor idle): the NEXT identical open prompt
        // is a genuine re-prompt, not a continued sample.
        _tracks[a.agentId]?.closedSinceLastOpen = true;
        continue;
      }
      final track = _tracks.putIfAbsent(a.agentId, _LoopTrack.new);
      if (track.prompt == a.decisionPrompt) {
        if (track.closedSinceLastOpen) {
          track.streak++;
          track.closedSinceLastOpen = false;
          if (track.streak == promptRepeatThreshold) {
            newWarnings.add(
              'ENDLESS-LOOP SUSPECT: actor ${a.agentId} re-opened the '
              'identical decision ${track.streak}× (origin: '
              '${a.decisionOrigin}). Prompt: "${a.decisionPrompt}"',
            );
          }
        }
        // else: same decision still open — long generation, not a repeat.
      } else {
        track.prompt = a.decisionPrompt;
        track.streak = 1;
        track.closedSinceLastOpen = false;
      }
    }
    return newWarnings;
  }

  /// Sample + record in one step.
  List<String> sampleAndRecord(World world) {
    final pulse = sampleHarness(world);
    return record(pulse);
  }

  /// Human-readable dump (tail-biased): the post-mortem for a stuck run.
  String dump() {
    if (_ring.isEmpty) return 'FlightRecorder: empty (no pulses recorded).';
    final b = StringBuffer(
      'FlightRecorder: ${_ring.length} pulse(s), '
      'ticks ${_ring.first.tick}..${_ring.last.tick}\n',
    );
    // Repetition warnings are computed from the RECORDED ring (not live
    // state) so a dump reflects the whole window, even after the streak
    // was broken. Counts open→closed→open cycles only (held-open decisions
    // across consecutive samples are not repeats).
    final best = <String, (String, int)>{}; // agentId → (prompt, best streak)
    final live = <String, ({String prompt, int streak, bool closedSince})>{};
    for (final p in _ring) {
      for (final a in p.actors) {
        if (!a.hasOpenDecision || a.decisionPrompt.isEmpty) {
          final t = live[a.agentId];
          if (t != null) {
            live[a.agentId] = (
              prompt: t.prompt,
              streak: t.streak,
              closedSince: true,
            );
          }
          continue;
        }
        final prev = live[a.agentId];
        if (prev != null && prev.prompt == a.decisionPrompt) {
          var streak = prev.streak;
          if (prev.closedSince) {
            streak++;
            final b = best[a.agentId];
            if (b == null || streak > b.$2) {
              best[a.agentId] = (a.decisionPrompt, streak);
            }
          }
          live[a.agentId] = (
            prompt: a.decisionPrompt,
            streak: streak,
            closedSince: false,
          );
        } else {
          live[a.agentId] = (prompt: a.decisionPrompt, streak: 1, closedSince: false);
          final b = best[a.agentId];
          if (b == null || 1 > b.$2) best[a.agentId] = (a.decisionPrompt, 1);
        }
      }
    }
    for (final e in best.entries) {
      if (e.value.$2 >= promptRepeatThreshold) {
        b.writeln(
          '⚠ actor ${e.key}: decision prompt repeated ${e.value.$2}× '
          '(identical): "${e.value.$1}"',
        );
      }
    }
    // Compact per-pulse lines for the tail, with the open decision prompt —
    // the "what was the harness doing when it got stuck" answer.
    final tail = _ring.length > 20 ? _ring.sublist(_ring.length - 20) : _ring;
    for (final p in tail) {
      b.writeln(
        'tick ${p.tick}: decisions=${p.openDecisions} '
        'inFlight=${p.inFlightTasks} pending=${p.pendingToolResults} '
        'actors=${[for (final a in p.actors) '${a.agentId}:${a.toolRounds}r/${a.attemptCount}a'].join(' ')}'
        '${p.loopWarnings.isEmpty ? '' : ' ⚠ ${p.loopWarnings.join(' | ')}'}',
      );
      for (final a in p.actors) {
        if (a.hasOpenDecision && a.decisionPrompt.isNotEmpty) {
          b.writeln('    ${a.agentId} ← ${a.decisionOrigin}: '
              '"${a.decisionPrompt}"');
        }
      }
    }
    return '$b';
  }

  String dumpJson() => jsonEncode([for (final p in _ring) p.toJson()]);
}

/// Per-actor loop-detection state for [FlightRecorder].
class _LoopTrack {
  String prompt = '';
  int streak = 0;
  bool closedSinceLastOpen = false;
}
