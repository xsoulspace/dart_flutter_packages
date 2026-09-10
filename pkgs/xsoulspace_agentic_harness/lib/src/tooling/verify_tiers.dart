// ignore_for_file: lines_longer_than_80_chars

/// TIERED VERIFICATION as a HARNESS capability (R7 follow-up, corrected
/// after architecture review).
///
/// Problem: the in-loop goal verifier re-ran the FULL convention command
/// (`dart test`) after every tool round — 20+ seconds per grade on a real
/// package, catastrophic in-loop.
///
/// Ownership (ADR 0009/0015 discipline): the derivation and policy are
/// GENERIC — thread beats record what changed (`edit_symbol` beats with
/// `files`) and what was last graded (`goal_verify` beats, written by the
/// run-graded verifier); the meaning tree derives the test frontier. The
/// only language-specific bits are workspace CONVENTIONS, contributed by
/// hosts as data ([VerifyConvention]) — never as host-side loop logic.
/// A future rust/typescript host supplies its own convention and its own
/// tree ETL; nothing in the mechanism changes.
///
/// Statelessness: every call derives the decision from the thread's beats —
/// no side-channel counters (the first cut kept `_lastGradedEditCount` in a
/// host closure, a shadow ledger invisible to projection/metrics/snapshot;
/// the graph already records everything). Snapshot/restore safe.
library;

import 'dart:io';

import 'package:ecsly/ecsly.dart';

import '../data_models/components.dart'
    show Actor, ActorThreads, Goal, ToolResultContent;
import '../meaning/meaning_tree.dart'
    show MeaningIndex, MeaningNode, impactFrontier, meaningComponentOf;
import '../narrative/components.dart' show BeatToolCall;
import '../narrative/facet_index.dart' show FacetIndex;
import '../systems/deferred_task_policy.dart'
    show DeferredRouting, classifyCommand, deferredVerifyPoolKey;
import 'build_gates.dart' show RunGoalCommand, RunGoalPlan, RunGoalSpec;
import 'workspace_conventions.dart' show resolveWorkspaceCheck;

/// Per-language/workspace verification convention, contributed by hosts as
/// DATA (the intentcall registry pattern: canonical contract upstream,
/// mechanical resolution; a future registry resource can hold several).
class VerifyConvention {
  const VerifyConvention({
    required this.editBeatNames,
    required this.testScopePrefixes,
    required this.narrowCommand,
    this.packageMarker = 'pubspec.yaml',
    this.checkResolver = resolveWorkspaceCheck,
  });

  /// Beat names that carry edits (the host's structured edit tool, e.g.
  /// dart_meaning's `edit_symbol`). The beat's ToolResultContent.output
  /// must carry `files`: the relPaths the move touched.
  final Set<String> editBeatNames;

  /// File-label prefixes that count as test scope (dart: `test/`,
  /// typescript: `test/`, rust: `tests/`).
  final List<String> testScopePrefixes;

  /// The narrowed command for a given set of test files (pure templating:
  /// dart → `dart test <files…>`, vitest → `npx vitest run <files…>`).
  /// Return null to force the full convention command instead.
  final List<String>? Function(List<String> testFiles) narrowCommand;

  /// P1 per-package tier — the file that marks a PACKAGE root (dart:
  /// `pubspec.yaml`; a rust host contributes `Cargo.toml`). The derivation
  /// walks UP from a touched file to the nearest marker file.
  final String packageMarker;

  /// P1 per-package tier — resolves the check command for a package
  /// directory (dart hosts: [resolveWorkspaceCheck] — `flutter test` vs
  /// `dart test` vs null when the package declares no convention). Null
  /// for ANY active package → the derivation fails honestly → the root
  /// convention (never invented, never skipped).
  final List<String>? Function(Directory packageDir) checkResolver;
}

/// The dart stack convention (edit_symbol beats, `test/` labels,
/// `dart test <files…>`, `pubspec.yaml` package markers,
/// [resolveWorkspaceCheck] per-package conventions).
const VerifyConvention dartVerifyConvention = VerifyConvention(
  editBeatNames: {'edit_symbol'},
  testScopePrefixes: ['test/'],
  narrowCommand: _dartNarrowCommand,
);

List<String>? _dartNarrowCommand(List<String> testFiles) => [
  'dart',
  'test',
  ...testFiles,
];

/// P1 (ADR 0009/0023 — PER-PACKAGE VERIFY DERIVATION, resolved via
/// dogfooding): the delegated verify used to grade the ROOT convention
/// (`flutter test` over a whole monorepo — measured 156.9 s wall vs the
/// 90 s dart-turn budget) even when the session touched ONE package.
/// This derivation resolves the ACTIVE packages from the session's own
/// touched-file beats: touched file → walk UP to the nearest
/// [VerifyConvention.packageMarker] → that directory IS the package → its
/// [VerifyConvention.checkResolver] command runs with the working
/// directory set to the package.
///
/// The steps carry a workspace-root-RELATIVE [RunGoalCommand.cwd] (the
/// jail resolves it — absolute paths would break on symlinked roots like
/// macOS `/var` ↔ `/private/var`).
///
/// Fallback law (never a skipped gate) — returns null (the caller runs
/// the ROOT convention unchanged) when:
/// - there are no touched files (a read-only session); or
/// - ANY touched file resolves to the workspace root itself or to no
///   package at all (a partial map would silently under-verify); or
/// - more than [maxPackages] distinct packages are active (bounded cost:
///   3+ packages re-grade cheaper through the root convention); or
/// - any active package's convention does not resolve (null).
List<RunGoalCommand>? derivePerPackageVerify({
  required String workspaceRoot,
  required Iterable<String> touchedFiles,
  required VerifyConvention convention,
  int maxPackages = 2,
}) {
  final root = _stripTrailingSlash(workspaceRoot);
  if (root.isEmpty) return null;
  final files = touchedFiles.toList();
  if (files.isEmpty) return null; // a read-only session → root fallback
  final packages = <String>[];
  for (final raw in files) {
    final rel = raw.replaceAll('\\', '/').trim();
    if (rel.isEmpty) return null;
    final segs = (rel.startsWith('/') ? rel.substring(1) : rel).split('/');
    // Never escape the root, never resolve through `..` — a touched path
    // that cannot be trusted fails the WHOLE derivation honestly.
    if (segs.any((s) => s == '..' || s.trim().isEmpty)) return null;
    // Walk UP from the touched file's directory to the nearest package
    // marker STRICTLY BELOW the workspace root (a monorepo root pubspec is
    // the workspace, not a package — mapping there IS the root fallback).
    String? packageDir;
    for (var i = segs.length - 1; i >= 1; i--) {
      final candidateRel = segs.sublist(0, i).join('/');
      if (File(
        '$root/$candidateRel/${convention.packageMarker}',
      ).existsSync()) {
        packageDir = candidateRel;
        break;
      }
    }
    if (packageDir == null) return null;
    if (!packages.contains(packageDir)) packages.add(packageDir);
    if (packages.length > maxPackages) return null;
  }
  final steps = <RunGoalCommand>[];
  for (final dir in packages) {
    final command = convention.checkResolver(Directory('$root/$dir'));
    if (command == null) return null;
    steps.add(RunGoalCommand(command: command, cwd: dir));
  }
  return steps;
}

String _stripTrailingSlash(String p) =>
    p.length > 1 && p.endsWith('/') ? p.substring(0, p.length - 1) : p;

/// The goal actor's first thread (the same thread the planner grades), or
/// null when the world carries no goal-carrying actor yet.
Entity? _goalThreadOf(World world) {
  final goalActors = world.query2<Actor, Goal>().toList();
  if (goalActors.isEmpty) return null;
  final actor = goalActors.first.$1.entity;
  final threads =
      world.getEntity(actor).$1.get<ActorThreads>()?.threads ?? const [];
  if (threads.isEmpty) return null;
  return threads.first;
}

/// Touched files from [editBeatNames] beats on the goal actor's thread,
/// walked in thread order (stateless: derived from beats every call —
/// no side-channel counters).
({int edits, List<String> touched}) _walkEditBeats(
  World world, {
  required Set<String> editBeatNames,
  required bool resetOnVerify,
}) {
  final thread = _goalThreadOf(world);
  if (thread == null) return (edits: 0, touched: const <String>[]);
  var edits = 0;
  List<String> touched = const [];
  final accumulated = <String>{};
  for (final beat
      in world.getResource<FacetIndex>().beatsOfThread(thread).toList()) {
    final we = world.getEntity(beat).$1;
    final call = we.get<BeatToolCall>();
    if (call == null) continue;
    if (editBeatNames.contains(call.name)) {
      edits++;
      final output = we.get<ToolResultContent>()?.output;
      if (output is Map) {
        final files = output['files'];
        if (files is List && files.isNotEmpty) {
          final beatFiles = [
            for (final f in files)
              if (f is String) f,
          ];
          if (resetOnVerify) {
            // The tier-planner semantics (unchanged): the LAST edit beat's
            // files are the pending set.
            touched = beatFiles;
          } else {
            accumulated.addAll(beatFiles);
          }
        }
      }
    } else if (call.name == 'goal_verify' && resetOnVerify) {
      // A grade consumed the pending changes.
      edits = 0;
      touched = const <String>[];
    }
  }
  if (!resetOnVerify) touched = accumulated.toList()..sort();
  return (edits: edits, touched: touched);
}

/// The pending-edits view the tier planner grades with: edits since the
/// last `goal_verify` beat and the files they touched.
({int edits, List<String> touched}) pendingEditsOf(
  World world,
  VerifyConvention convention,
) => _walkEditBeats(
  world,
  editBeatNames: convention.editBeatNames,
  resetOnVerify: true,
);

/// The delegated verify's derivation input: EVERY edit beat's files on the
/// goal actor's thread (the session's touched set). An in-loop grade
/// consumes the PENDING changes, but the session still owns the touched
/// set — the terminal gate must grade what the session touched, not what
/// happened to be pending when it ran.
List<String> sessionTouchedFiles(World world, VerifyConvention convention) =>
    _walkEditBeats(
      world,
      editBeatNames: convention.editBeatNames,
      resetOnVerify: false,
    ).touched;

/// Stateless planner wired as [RunGoalSpec.planProvider]. Derives the
/// verification tier purely from graph state:
///
/// - **skip** — no edits pending since the last `goal_verify` beat: the
///   graph state cannot have changed, re-grading is pure cost. The
///   driver's final gate remains the terminal proof (it always grades).
/// - **per-package** — the pending touched files resolve to ACTIVE
///   packages ([derivePerPackageVerify]): each package's own convention
///   runs in its own directory (the 156.9 s monorepo-root fix).
/// - **narrow** — grade only the test files in the refs frontier of the
///   touched files (DERIVED from the tree, never model-chosen).
/// - **full** — no frontier knowledge → null (the convention command runs
///   untouched).
class VerifyTierPlanner {
  const VerifyTierPlanner({this.convention = dartVerifyConvention});

  final VerifyConvention convention;

  Future<RunGoalPlan?> call(World world) async {
    final (:edits, :touched) = pendingEditsOf(world, convention);
    final editsSinceVerify = edits;
    if (editsSinceVerify == 0) return const RunGoalPlan(skip: true);
    if (touched.isEmpty) return null; // edits without file data: full grade

    // P1 PER-PACKAGE tier: the touched files resolve to the ACTIVE
    // packages; each package's convention runs in its own directory. The
    // workspace root comes from the wired [RunGoalSpec] (the verify cwd IS
    // the workspace root — no side-channel). Derivation failure → the
    // legacy tiers below → the root convention. Never skipped.
    final workspaceRoot = _workspaceRootOf(world);
    if (workspaceRoot != null) {
      final steps = derivePerPackageVerify(
        workspaceRoot: workspaceRoot,
        touchedFiles: touched,
        convention: convention,
      );
      if (steps != null && steps.isNotEmpty) {
        return RunGoalPlan(skip: false, commands: steps);
      }
    }

    // NARROW: test files in the refs frontier of the touched files.
    final index = world.getResource<MeaningIndex>();
    final testFiles = <String>{};
    for (final rel in touched) {
      final fileId = 'f_${rel.replaceAll('/', '_')}';
      if (!index.byId.containsKey(fileId)) continue;
      final entity = index.byId[fileId];
      if (entity == null) continue;
      for (final id in impactFrontier(world, fileId, maxDepth: 2)) {
        final frontierEntity = index.byId[id];
        if (frontierEntity == null) continue;
        final node = meaningComponentOf<MeaningNode>(world, frontierEntity);
        if (node == null || node.kind != 'file') continue;
        if (convention.testScopePrefixes.any(node.label.startsWith)) {
          testFiles.add(node.label);
        }
      }
    }
    if (testFiles.isEmpty) return null; // full convention command
    return RunGoalPlan(
      skip: false,
      command: convention.narrowCommand(testFiles.toList()..sort()) ?? null,
    );
  }

  /// The verify workspace root from the wired [RunGoalSpec] (the planner
  /// grades through it, so it is always present on the verify path); null
  /// → the per-package derivation declines (legacy tiers only).
  String? _workspaceRootOf(World world) {
    try {
      final cwd = world.getResource<RunGoalSpec>().cwd;
      return cwd.isEmpty ? null : cwd;
    } on StateError {
      return null;
    }
  }
}

// ─────────────────────────────────────────────
// The deferred-task law (item 3) — ADDITIVE pooling keys + classification
// over the per-package derivation. Nothing above changes: with deferral
// DISABLED (the default) every planner/verifier path runs exactly as
// before — the inline full/narrow/per-package tiers remain the fallback.
// ─────────────────────────────────────────────

/// The deferred-verify POOL key for one per-package verify step: the
/// (package, convention) join identity of the pooling law (see
/// [deferredVerifyPoolKey] in systems/deferred_task_policy.dart). Two
/// actors deriving the same package + convention command share ONE
/// in-flight task; different packages (or a different convention command)
/// never join.
String verifyPoolKeyForStep(RunGoalCommand step) =>
    deferredVerifyPoolKey(packageDir: step.cwd ?? '', convention: step.command);

/// Pool keys for a whole derived plan ([derivePerPackageVerify] output):
/// ONE entry per ACTIVE package — the keys a deferred wire consults when
/// deciding whether a second actor's verify JOINS the in-flight task.
List<String> verifyPoolKeysForSteps(List<RunGoalCommand> steps) =>
    [for (final s in steps) verifyPoolKeyForStep(s)];

/// The verify command's deferral class under the deferred-task law (the
/// class table lives in systems/deferred_task_policy.dart — DATA, never a
/// switch): test conventions classify deferred (test-run); the
/// interactive-classes-never-defer law is enforced there and pinned by the
/// gate. With deferral DISABLED this ALWAYS routes inline — the fallback
/// law preserving the legacy tiers verbatim.
DeferredRouting classifyVerifyCommand(
  Iterable<String> command, {
  bool deferralEnabled = true,
}) => classifyCommand(command, deferralEnabled: deferralEnabled);

/// ADDITIVE (production deferral wiring, follow-up 2): the per-package
/// steps a plan carries — the deferred wire grades the SAME steps the
/// inline verifier would have run, so pooling keys and execution stay
/// one-truth. `commands` (the per-package tier) wins; the legacy
/// single-command tiers project as ONE step carrying [RunGoalPlan.cwd];
/// an empty result means the plan grades the ROOT convention unchanged
/// (the caller's own root step — nothing to pool).
List<RunGoalCommand> planStepsOf(RunGoalPlan plan) {
  if (plan.commands.isNotEmpty) return plan.commands;
  if (plan.command != null) {
    return [RunGoalCommand(command: plan.command!, cwd: plan.cwd)];
  }
  return const <RunGoalCommand>[];
}
