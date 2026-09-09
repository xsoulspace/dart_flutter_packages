// ignore_for_file: avoid_redundant_argument_values, lines_longer_than_80_chars

/// THE DEFERRED-TASK LAW (interactive-path item 3).
///
/// The interactive path NEVER blocks ≳1 s: oracles and builds DEFER as
/// REGISTERED TASKS — [TaskId]/[TaskHandle] in [TaskRegistryResource], the
/// EXISTING one-truth in-flight machinery (reuse, never a fork). Completion
/// lands a BEAT on every requesting actor's thread, and the requesting
/// actor is RE-OPENED on completion via the [ToolResultPendingMarker]
/// continuation ([processToolResultsSystem]) — no poll loop anywhere.
///
/// Deferral NEVER skips verification: deferred time lands as beats
/// (`verify_wall_ms` on the completion beat — the same budget-law data the
/// run-graded verifier stamps). A deferral that never produces its
/// verification beat is a NAMED DEFECT
/// ([DeferredTaskAccounting.namedDefects]) — never silence.
///
/// Deferral is DATA, not control flow: the class table ([kDeferredClasses])
/// and the command matchers ([kDeferredCommandMatchers]) are const tables a
/// host extends by contributing rows. Interactive/mechanical read-edit
/// classes ([kInteractiveIntents]) NEVER defer — asserted negatively in the
/// gate (test/deferred_task_policy_test.dart).
///
/// DISABLED by default: every existing inline behavior is preserved
/// verbatim until a host wires [DeferredTaskPolicy] with `enabled: true`
/// (the fallback law — see `wireDeferredVerify` in the coding runner).
library;

import 'dart:convert';

import 'package:ecsly/ecsly.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart'
    show ToolExecutionResult;

import '../data_models/task.dart' show TaskHandle, TaskId;
import '../events.dart' show ToolResultEvent;
import '../resources/resources.dart' show TaskRegistryResource;
import 'tool_systems.dart' show resolveToolTaskForRequesters;

// ─────────────────────────────────────────────
// The class table (AS DATA)
// ─────────────────────────────────────────────

/// One deferral CLASS as data: {id, beatContract, completionReopen}.
class DeferredTaskClass {
  const DeferredTaskClass({
    required this.id,
    required this.beatContract,
    this.completionReopen = true,
  });

  /// Stable class id (the accounting + pool key component).
  final String id;

  /// The NAMED beat the completion MUST land on the requesting actor's
  /// thread (e.g. `goal_verify` — the run-graded verifier's beat name).
  /// A deferral that never lands this beat is a named defect.
  final String beatContract;

  /// The requesting actor is RE-OPENED when the task completes (the
  /// ToolResultPendingMarker continuation — never a poll loop).
  final bool completionReopen;
}

/// The deferral-class table. COMPLETE for v1: test-run, pub-get, build,
/// app-run, dylib-build. Every class carries `completionReopen: true` —
/// a completion that does not re-open the requester is the defect class
/// the law names, not a configuration option.
const Map<String, DeferredTaskClass> kDeferredClasses = {
  'test-run': DeferredTaskClass(
    id: 'test-run',
    beatContract: 'goal_verify',
    completionReopen: true,
  ),
  'pub-get': DeferredTaskClass(
    id: 'pub-get',
    beatContract: 'pub_get',
    completionReopen: true,
  ),
  'build': DeferredTaskClass(
    id: 'build',
    beatContract: 'build_verify',
    completionReopen: true,
  ),
  'app-run': DeferredTaskClass(
    id: 'app-run',
    beatContract: 'app_run',
    completionReopen: true,
  ),
  'dylib-build': DeferredTaskClass(
    id: 'dylib-build',
    beatContract: 'dylib_build',
    completionReopen: true,
  ),
};

/// Interactive/mechanical read-edit intents NEVER defer. These are the
/// meaning-surface reads and edits (measured 24–54 ms — the ADR 0027 row):
/// blocking them behind a deferral would starve the tiny-model path.
const Set<String> kInteractiveIntents = {
  'read',
  'write',
  'list_dir',
  'glob',
  'grep',
  'edit_symbol',
  'meaning_program',
  'act_with_project',
  'repo_etl',
  'harness_scan',
  'harness_zoom',
  'harness_impact',
  'harness_locate',
  'harness_edit',
  'harness_fs_write',
  'harness_verify',
  'intent_define',
  'intent_call',
  'write_review',
  'declare_check',
};

/// Command matchers per deferred class (AS DATA — a host extends the table
/// by contributing rows). Each row is an exact token-prefix match; the
/// LONGEST matching prefix wins (so `flutter build ios-framework` lands in
/// dylib-build, not build). Interactive commands (read/edit-shaped heads)
/// are deliberately ABSENT: absent → inline.
const Map<String, List<List<String>>> kDeferredCommandMatchers = {
  'test-run': [
    ['dart', 'test'],
    ['flutter', 'test'],
    ['npx', 'vitest', 'run'],
    ['cargo', 'test'],
    ['go', 'test'],
    ['dotnet', 'test'],
  ],
  'pub-get': [
    ['dart', 'pub', 'get'],
    ['flutter', 'pub', 'get'],
    ['pub', 'get'],
  ],
  'build': [
    ['flutter', 'build'],
    ['dart', 'build'],
    ['npm', 'run', 'build'],
    ['tsc'],
    ['cmake'],
    ['make'],
    ['dotnet', 'build'],
  ],
  'app-run': [
    ['flutter', 'run'],
    ['dart', 'run'],
  ],
  'dylib-build': [
    ['flutter', 'build', 'ios-framework'],
    ['flutter', 'build', 'aar'],
    ['flutter', 'build', 'ios'],
    ['flutter', 'build', 'apk'],
    ['xcodebuild'],
  ],
};

/// The routing verdict.
enum DeferredRouting { inline, deferred }

/// The deferred class for [command], or null → INLINE (the interactive
/// path). Most-specific (longest) prefix wins.
DeferredTaskClass? matchDeferredClass(List<String> command) {
  final args = [
    for (final t in command)
      if (t.trim().isNotEmpty) t.trim(),
  ];
  DeferredTaskClass? best;
  var bestLen = -1;
  for (final entry in kDeferredCommandMatchers.entries) {
    for (final prefix in entry.value) {
      if (prefix.length > args.length) continue;
      var ok = true;
      for (var i = 0; i < prefix.length; i++) {
        if (args[i] != prefix[i]) {
          ok = false;
          break;
        }
      }
      if (!ok) continue;
      if (prefix.length > bestLen) {
        bestLen = prefix.length;
        best = kDeferredClasses[entry.key];
      }
    }
  }
  return best;
}

/// classify(command) → inline | deferred. DISABLED deferral ALWAYS routes
/// inline (the fallback law: existing behavior preserved verbatim).
DeferredRouting classifyCommand(
  Iterable<String> command, {
  bool deferralEnabled = true,
}) {
  if (!deferralEnabled) return DeferredRouting.inline;
  return matchDeferredClass(command.toList()) == null
      ? DeferredRouting.inline
      : DeferredRouting.deferred;
}

/// classify(intent) → inline | deferred. Interactive/mechanical read-edit
/// intents NEVER defer — even when deferral is ENABLED (the negative law,
/// pinned by the gate). Run/exec-shaped intents classify by the command
/// table's verb prefixes.
const List<String> kIntentVerbPrefixes = ['run', 'exec', 'test', 'build', 'pub'];

DeferredRouting classifyIntent(String intent, {bool deferralEnabled = true}) {
  if (!deferralEnabled) return DeferredRouting.inline;
  if (kInteractiveIntents.contains(intent)) return DeferredRouting.inline;
  final verb = intent.toLowerCase();
  for (final prefix in kIntentVerbPrefixes) {
    if (verb.startsWith(prefix)) return DeferredRouting.deferred;
  }
  return DeferredRouting.inline;
}

// ─────────────────────────────────────────────
// Accounting: deferral rate + verify-wall beats (failures are data)
// ─────────────────────────────────────────────

/// Deferral-rate + verify-wall-beat accounting on task outcomes. The
/// named-defect ledger is the law's enforcement: a deferral with no
/// completion beat is a DEFECT, never a silent cost.
class DeferredTaskAccounting extends Resource {
  /// Requests that ran the EXISTING inline path (deferral disabled or an
  /// inline class).
  int inlineRuns = 0;

  /// Deferred tasks REGISTERED as tasks (one per pool entry).
  int deferredStarted = 0;

  /// Requests that JOINED an in-flight pooled task (one task, N actors).
  int joinedRequests = 0;

  /// Completion beats landed on requesting actors' threads.
  int completionBeats = 0;

  /// Sum of `verify_wall_ms` carried by completion beats — deferred time
  /// lands as BEATS, never a side-channel.
  int verifyWallBeatMsTotal = 0;

  /// Class ids deferred but awaiting their verification beat.
  final Set<String> _awaitingBeat = {};

  int get deferredRequests => deferredStarted + joinedRequests;
  int get totalRequests => inlineRuns + deferredRequests;

  /// Deferred share of all verify-shaped requests (0 when nothing routed).
  double get deferralRate =>
      totalRequests == 0 ? 0 : deferredRequests / totalRequests;

  void recordInline() => inlineRuns++;

  void recordDeferred(String classId) {
    deferredStarted++;
    _awaitingBeat.add(classId);
  }

  void recordJoin() => joinedRequests++;

  /// One completion beat per requesting actor ([actors] = requester count
  /// of the pooled entry).
  void recordBeat({required String classId, int actors = 1, int? verifyWallMs}) {
    completionBeats += actors;
    _awaitingBeat.remove(classId);
    if (verifyWallMs != null) verifyWallBeatMsTotal += verifyWallMs;
  }

  /// THE NAMED DEFECTS: a deferral that never produced its verification
  /// beat. Empty only when every deferral kept its beat contract.
  List<String> namedDefects() => [
    for (final c in _awaitingBeat) renderDefect(c),
  ];

  /// One rendered defect row (kept out of the list literal so the lint
  /// surface stays clean).
  static String renderDefect(String classId) {
    final contract = kDeferredClasses[classId]?.beatContract;
    return 'deferred_task_defect: class "$classId" deferred but its '
            '${contract ?? 'verification'} beat never landed';
  }
}

/// The accounting resource of [world] (lazily wired — pool/policy callers
/// never crash on an unwired ledger; the data just starts at zero).
DeferredTaskAccounting deferredAccountingOf(World world) {
  try {
    return world.getResource<DeferredTaskAccounting>();
  } on StateError {
    final a = DeferredTaskAccounting();
    world.upsertResource(a);
    return a;
  }
}

// ─────────────────────────────────────────────
// The policy + the verify pool (keyed per (package, convention))
// ─────────────────────────────────────────────

/// The deferral policy as a world resource. DISABLED by default — with no
/// wired policy (or `enabled: false`) every caller takes the EXISTING
/// inline path unchanged (the disabled-fallback law).
class DeferredTaskPolicy extends Resource {
  DeferredTaskPolicy({
    this.enabled = false,

    /// The interactive-path wall budget the law protects (informational
    /// data hosts may measure against — the policy itself never blocks).
    this.interactiveWallBudget = const Duration(seconds: 1),
  });

  final bool enabled;
  final Duration interactiveWallBudget;
}

/// One pooled deferred-verify entry: ONE registered task, N requesters.
class DeferredVerifyEntry {
  DeferredVerifyEntry({
    required this.taskId,
    required this.poolKey,
    required this.classId,
    required List<Entity> requesters,
  }) : requesters = [...requesters];

  final TaskId taskId;

  /// The (package, convention) join identity — see
  /// [deferredVerifyPoolKey].
  final String poolKey;

  /// The [kDeferredClasses] id this verify classifies to.
  final String classId;

  /// Every actor awaiting the completion beat (the JOIN law: a second
  /// actor's same-package verify appends itself here — one task runs,
  /// BOTH actors get the completion beat).
  final List<Entity> requesters;
}

/// The canonical (package, convention) pool key. Different packages NEVER
/// join; the same package under a DIFFERENT convention command never joins
/// either (a different command is a different verification).
String deferredVerifyPoolKey({
  required String packageDir,
  required List<String> convention,
}) => 'pkg:${packageDir.replaceAll(r'\', '/')}|conv:${convention.join(' ')}';

/// The pooling ledger. Deferred verify is keyed per (package, convention):
/// a second actor's SAME-package verify JOINS the in-flight task — one
/// task runs, BOTH actors get the completion beat; different packages
/// never join.
class DeferredVerifyPool extends Resource {
  final Map<String, DeferredVerifyEntry> _inFlight = {};

  int get inFlightCount => _inFlight.length;

  DeferredVerifyEntry? entryOf(String poolKey) => _inFlight[poolKey];

  DeferredVerifyEntry? entryByTaskId(TaskId taskId) {
    for (final e in _inFlight.values) {
      if (e.taskId == taskId) return e;
    }
    return null;
  }

  /// JOIN the in-flight same-(package, convention) verify, or register a
  /// NEW pooled task in the world's [TaskRegistryResource] (the existing
  /// in-flight machinery — canSleep never exits under a pending verify).
  DeferredVerifyEntry join({
    required World world,
    required String packageDir,
    required List<String> conventionCommand,
    required Entity requester,
  }) {
    final key = deferredVerifyPoolKey(
      packageDir: packageDir,
      convention: conventionCommand,
    );
    final existing = _inFlight[key];
    if (existing != null &&
        world.getResource<TaskRegistryResource>().has(existing.taskId)) {
      existing.requesters.add(requester);
      deferredAccountingOf(world).recordJoin();
      return existing;
    }
    final taskId = TaskId.create();
    world.getResource<TaskRegistryResource>().register(taskId, TaskHandle());
    final classId =
        matchDeferredClass(conventionCommand)?.id ?? kDeferredClasses.keys.first;
    final entry = DeferredVerifyEntry(
      taskId: taskId,
      poolKey: key,
      classId: classId,
      requesters: [requester],
    );
    _inFlight[key] = entry;
    deferredAccountingOf(world).recordDeferred(classId);
    return entry;
  }

  /// Remove and return the entry on completion.
  DeferredVerifyEntry? takeEntry(TaskId taskId) {
    DeferredVerifyEntry? found;
    _inFlight.removeWhere((_, e) {
      if (e.taskId == taskId) {
        found = e;
        return true;
      }
      return false;
    });
    return found;
  }
}

// ─────────────────────────────────────────────
// Completion — the EXISTING machinery, reused (never forked)
// ─────────────────────────────────────────────

/// Complete a pooled deferred verify. REUSES the existing in-flight task
/// completion machinery end-to-end:
///
/// 1. the registered [TaskHandle] completer resolves (the same one-truth
///    path [resolveToolTask] drives);
/// 2. a [ToolResultEvent] is published for EVERY requesting actor, so the
///    scheduled [processToolResultsSystem] lands the verification beat on
///    each actor's thread AND re-opens each actor via the
///    [ToolResultPendingMarker] continuation — the requesting actor wakes
///    on completion, no poll loop;
/// 3. the beat carries `verify_wall_ms` (deferred time lands as a beat)
///    and the class's [DeferredTaskClass.beatContract] as the beat name.
///
/// No-op (honest) when [taskId] pools nothing.
void completeDeferredVerify(
  World world, {
  required TaskId taskId,
  required bool passed,
  required String detail,
  int? verifyWallMs,
  List<String>? command,
}) {
  final pool = world.getResource<DeferredVerifyPool>();
  final entry = pool.takeEntry(taskId);
  if (entry == null) return;
  final cls = kDeferredClasses[entry.classId];
  final output = <String, Object?>{
    'ok': passed,
    'deferred': true,
    'class': entry.classId,
    'beat_contract': cls?.beatContract ?? 'goal_verify',
    'completion_reopen': cls?.completionReopen ?? true,
    'pool_key': entry.poolKey,
    'requesters': entry.requesters.length,
    'detail': detail,
  };
  if (command != null) output['command'] = command;
  if (verifyWallMs != null) output['verify_wall_ms'] = verifyWallMs;
  final result = ToolExecutionResult(
    name: cls?.beatContract ?? 'goal_verify',
    output: jsonEncode(output),
  );
  resolveToolTaskForRequesters(world, world.getResource<TaskRegistryResource>(),
      taskId, result, entry.requesters);
  deferredAccountingOf(world).recordBeat(
    classId: entry.classId,
    actors: entry.requesters.length,
    verifyWallMs: verifyWallMs,
  );
}
