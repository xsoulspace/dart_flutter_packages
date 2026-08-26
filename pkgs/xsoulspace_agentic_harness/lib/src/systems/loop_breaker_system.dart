// ignore_for_file: lines_longer_than_80_chars

/// Mechanical loop breaker: detect identical failing tool calls repeated
/// within one thread and intervene deterministically.
///
/// Evidence (edit_01, guided arm): after a legitimate `anchor_not_unique`
/// rejection the model echoed diagnostic tokens back as arguments for 15
/// consecutive rounds — no mechanism noticed. Three tiers:
///
/// 1. **Teach** (streak == 2): insert a harness observation beat stating the
///    rule ("diagnostic words are not argument values; read first").
/// 2. **Raise the baton** (streak >= 3): stamp [LoopStuck] on the owning
///    actor — a [DecisionPolicy] ([LoopEscalationPolicy]) consumes it and
///    opens an escalated decision via [OpenDecision.escalate], so hosts can
///    swap the handoff behavior declaratively instead of relying on
///    baked-in escalation.
/// 3. **Fail fast** (teaching already done + still looping): suspend the
///    thread and withdraw the ReAct continuation marker so rounds aren't
///    burned, then let checkers classify the workspace honestly.
///
/// LLM-free, stateless (derived entirely from the beat graph), bounded by
/// [AgencyPolicy.maxToolRounds].
library;

import 'dart:convert';

import 'package:ecsly/ecsly.dart';

import '../data_models/data_models.dart';
import '../narrative/narrative.dart';
import '../resources/resources.dart';
import 'decision_flow_system.dart' show ToolResultPendingMarker;
import 'projection/relevance.dart' show keywordsOf;
import 'tool_systems.dart' show attachBeatToActorThread;

/// Marker payload key on the harness teaching beat ([ObservationData]).
const kLoopGuardKind = 'loop_guard';

/// Number of consecutive identical failing calls before teaching.
const _teachAtStreak = 2;

/// Number of consecutive identical failing calls before escalation.
const _escalateAtStreak = 3;

/// Scans every thread's trailing tool-call window; teaches and/or escalates.
///
/// Threads are identified by their [ThreadStatus] marker (spawnThread does
/// not attach the [Thread] container component), which also makes the guard
/// cover goal-threads and any future thread factories.
///
/// Three tiers, each deterministic: teach at streak 2, raise the baton
/// (escalation tag) at streak 3, and — when a teaching beat ALREADY exists
/// and the loop persists anyway — stop the thread (suspend + withdraw the
/// continuation marker) instead of burning the remaining tool rounds.
/// Evidence (edit_01 guided arm): the teach tier alone did not steer this
/// model out of echoing its own diagnostics; rounds saved are wall clock
/// saved, and checkers still classify the workspace honestly.
void loopBreakerSystem(World world) {
  final index = world.getResource<FacetIndex>();
  for (final (threadWe, status) in world.query<ThreadStatus>()) {
    if (status.value != ThreadStatusEnum.active) continue;
    final origin = threadWe.get<OriginActor>()?.actor;
    if (origin == null) continue;
    final (actorWe, actorAlive) = world.getEntity(origin);
    if (!actorAlive) continue;

    final beats = index.beatsOfThread(threadWe.entity).toList();
    final verdict = _trailingLoopVerdict(world, beats);
    if (verdict == null) continue;

    if (verdict.streak == _teachAtStreak &&
        !_hasGuardAfter(world, beats, verdict.secondDuplicatePosition)) {
      _insertTeachingBeat(
        world,
        actorWe,
        origin,
        threadWe.entity,
        verdict,
      );
    }
    // Escalate: stamp LoopStuck so a DecisionFlow policy opens an escalated
    // decision at the next agency grant (see LoopEscalationPolicy). Detection
    // is mechanical; the response is declarative and host-replaceable.
    if (verdict.streak >= _escalateAtStreak) {
      actorWe.insert(LoopStuck(verdict.streak));
    }
    // Tier 3: taught but still looping → fail fast. Suspending the thread
    // also excludes it from projection; history stays queryable. Withdraw
    // the ReAct continuation marker only — removing OpenDecision here would
    // race the agency pipeline mid-flight.
    if (verdict.streak >= _escalateAtStreak && _hasAnyGuard(world, beats)) {
      status.value = ThreadStatusEnum.suspended;
      actorWe.remove<ToolResultPendingMarker>();
    }
  }
}

class _LoopVerdict {
  _LoopVerdict({
    required this.streak,
    required this.toolName,
    required this.lastOutput,
    required this.secondDuplicatePosition,
  });
  final int streak;
  final String toolName;
  final String lastOutput;
  final int secondDuplicatePosition;
}

/// Walks the thread's beats in insertion order and reports the trailing
/// streak of identical tool-call signatures, requiring every call in the
/// streak to have failed.
_LoopVerdict? _trailingLoopVerdict(World world, List<Entity> beats) {
  String? signature;
  var streak = 0;
  var secondDuplicatePosition = -1;
  var lastOutput = '';
  var toolName = '';

  for (var i = 0; i < beats.length; i++) {
    final we = world.getEntity(beats[i]).$1;
    final call = we.get<BeatToolCall>();
    if (call == null) {
      // A non-tool beat (assistant text, teaching note) breaks nothing by
      // itself — but a NEW distinct call below restarts the count.
      continue;
    }
    final sig = '${call.name}:${jsonEncode(call.args)}';
    final failed = _isFailure(we.get<ToolResultContent>());
    if (failed && sig == signature) {
      streak++;
      if (streak == _teachAtStreak) {
        secondDuplicatePosition = i;
        toolName = call.name;
        lastOutput = _outputText(we.get<ToolResultContent>());
      }
    } else {
      signature = sig;
      streak = failed ? 1 : 0;
      secondDuplicatePosition = -1;
      toolName = call.name;
    }
  }
  if (streak < _teachAtStreak) return null;
  return _LoopVerdict(
    streak: streak,
    toolName: toolName,
    lastOutput: lastOutput,
    secondDuplicatePosition: secondDuplicatePosition,
  );
}

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

String _outputText(ToolResultContent? result) => result == null
    ? ''
    : result.output is Map ? jsonEncode(result.output) : '${result.output}';

/// True when a teaching beat already follows the detected duplicate pair —
/// prevents re-teaching on every mechanical pass while the streak sits at 2.
bool _hasGuardAfter(World world, List<Entity> beats, int position) {
  for (var i = position + 1; i < beats.length; i++) {
    final data = world.getEntity(beats[i]).$1.get<ObservationData>();
    if (data?.data is Map && (data!.data as Map)['kind'] == kLoopGuardKind) {
      return true;
    }
  }
  return false;
}

/// True when the thread carries ANY teaching beat — used by tier 3 to
/// distinguish "never taught" from "taught and still looping".
bool _hasAnyGuard(World world, List<Entity> beats) => _hasGuardAfter(
      world,
      beats,
      -1,
    );

void _insertTeachingBeat(
  World world,
  WorldEntity actorWe,
  Entity origin,
  Entity thread,
  _LoopVerdict verdict,
) {
  final text = 'Loop guard: the identical failing call to "${verdict.toolName}" '
      'was repeated ${verdict.streak}x. Diagnostic words are NOT argument '
      'values. Read the target file first (read path), then retry with a '
      'distinct anchor copied EXACTLY from the file content that occurs once. '
      'Last diagnostic: ${verdict.lastOutput}';
  final beat = world.reserveEmptyEntity().entity;
  world.getEntity(beat).$1
    ..insert(ObservationData({'kind': kLoopGuardKind}))
    ..insert(TextContent(text))
    ..insert(Speaker(origin))
    ..insert(PrivateToActor(origin))
    ..insert(BeatStatus(BeatStatusEnum.complete))
    ..insert(BeatModality(BeatModalityEnum.observation));
  attachBeatToActorThread(world, actorWe, beat);
  indexBeat(
    world,
    beat,
    keywordsOf(text),
    thread: world.getEntity(beat).$1.get<BelongsToThread>()?.thread,
  );
}
