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

import 'package:ecsly/ecsly.dart';

import '../data_models/components.dart'
    show Actor, ActorThreads, Goal, ToolResultContent;
import '../narrative/components.dart' show BeatToolCall;
import '../meaning/meaning_tree.dart'
    show MeaningIndex, MeaningNode, impactFrontier, meaningComponentOf;
import '../narrative/facet_index.dart' show FacetIndex;
import 'build_gates.dart' show RunGoalPlan;

/// Per-language/workspace verification convention, contributed by hosts as
/// DATA (the intentcall registry pattern: canonical contract upstream,
/// mechanical resolution; a future registry resource can hold several).
class VerifyConvention {
  const VerifyConvention({
    required this.editBeatNames,
    required this.testScopePrefixes,
    required this.narrowCommand,
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
}

/// The dart stack convention (edit_symbol beats, `test/` labels,
/// `dart test <files…>`).
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

/// Stateless planner wired as [RunGoalSpec.planProvider]. Derives the
/// verification tier purely from graph state:
///
/// - **skip** — no edits pending since the last `goal_verify` beat: the
///   graph state cannot have changed, re-grading is pure cost. The
///   driver's final gate remains the terminal proof (it always grades).
/// - **narrow** — grade only the test files in the refs frontier of the
///   touched files (DERIVED from the tree, never model-chosen).
/// - **full** — no frontier knowledge → null (the convention command runs
///   untouched).
class VerifyTierPlanner {
  const VerifyTierPlanner({this.convention = dartVerifyConvention});

  final VerifyConvention convention;

  Future<RunGoalPlan?> call(World world) async {
    final goalActors = world.query2<Actor, Goal>().toList();
    if (goalActors.isEmpty) return null;
    final actor = goalActors.first.$1.entity;
    final threads =
        world.getEntity(actor).$1.get<ActorThreads>()?.threads ?? const [];
    if (threads.isEmpty) return null;
    final thread = threads.first;

    // Walk the thread IN ORDER, deriving pending-work state: edits since
    // the last verification, and the files they touched.
    var editsSinceVerify = 0;
    List<String> touched = const [];
    for (final beat
        in world.getResource<FacetIndex>().beatsOfThread(thread).toList()) {
      final we = world.getEntity(beat).$1;
      final call = we.get<BeatToolCall>();
      if (call == null) continue;
      if (convention.editBeatNames.contains(call.name)) {
        editsSinceVerify++;
        final output = we.get<ToolResultContent>()?.output;
        if (output is Map) {
          final files = output['files'];
          if (files is List && files.isNotEmpty) {
            touched = [
              for (final f in files)
                if (f is String) f,
            ];
          }
        }
      } else if (call.name == 'goal_verify') {
        // A grade consumed the pending changes.
        editsSinceVerify = 0;
        touched = const [];
      }
    }
    if (editsSinceVerify == 0) return const RunGoalPlan(skip: true);
    if (touched.isEmpty) return null; // edits without file data: full grade

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
}
