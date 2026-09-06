// ignore_for_file: lines_longer_than_80_chars

/// P2 — the task-grammar classifier: mechanical parse of a task sentence
/// into {verb-class, target, params}, ZERO model tokens. Gates:
/// - grammar coverage (fix / rename / run / apply, with file + trailing
///   teaching-boilerplate tolerance);
/// - HONEST failure: a non-grammar sentence gets a NAMED class — never a
///   guess;
/// - the decision lookup: verb-class → pack executable repair class → the
///   ready apply_executable decision data, with named miss reasons.
library;

import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/src/agent.dart' show AgentPlugin;
import 'package:xsoulspace_agentic_harness/src/meaning/capability_nodes.dart';
import 'package:xsoulspace_agentic_harness/src/meaning/meaning_tree.dart';
import 'package:xsoulspace_agentic_harness/src/tools/task_grammar.dart';

void main() {
  group('parseTaskSentence — grammar coverage', () {
    test('fix <Symbol> [in <file>]', () {
      final m = parseTaskSentence('fix product in lib/geometry.dart.');
      expect(m, isA<TaskGrammarMatch>());
      final match = m as TaskGrammarMatch;
      expect(match.verbClass, 'fix');
      expect(match.target, 'product');
      expect(match.targetKind, 'symbol');
      expect(match.params['file'], 'lib/geometry.dart');
    });
    test('fix tolerates the runner teaching boilerplate after the sentence',
        () {
      final m = parseTaskSentence(
        'fix product in lib/geometry.dart Work through the meaning tree: '
        'repo_etl scan, meaning_zoom / meaning_impact to read, edit_symbol '
        'to act on code, write_review for non-code files (the human '
        'consents). Never touch files directly.',
      );
      expect(m, isA<TaskGrammarMatch>());
      expect((m as TaskGrammarMatch).target, 'product');
    });
    test('fix <Symbol>: <prose tail> — the target is complete after the id',
        () {
      final m = parseTaskSentence('Fix area: it must return w*h.');
      expect(m, isA<TaskGrammarMatch>());
      expect((m as TaskGrammarMatch).target, 'area');
    });
    test('rename <A> to <B> [in <file>]', () {
      final m = parseTaskSentence('rename area to square in lib/geometry.dart');
      expect(m, isA<TaskGrammarMatch>());
      final match = m as TaskGrammarMatch;
      expect(match.verbClass, 'rename');
      expect(match.target, 'area');
      expect(match.params['newName'], 'square');
      expect(match.params['file'], 'lib/geometry.dart');
    });
    test('run <check>', () {
      final m = parseTaskSentence('run dart test');
      expect(m, isA<TaskGrammarMatch>());
      final match = m as TaskGrammarMatch;
      expect(match.verbClass, 'run');
      expect(match.target, 'dart test');
      expect(match.targetKind, 'check');
    });
    test('apply <executableId> [to <Symbol>]', () {
      final m = parseTaskSentence('apply dart/fix_loop_bound to product');
      expect(m, isA<TaskGrammarMatch>());
      final match = m as TaskGrammarMatch;
      expect(match.verbClass, 'apply');
      expect(match.target, 'dart/fix_loop_bound');
      expect(match.params['symbol'], 'product');
    });
    test('directive-only prompts strip clean before parsing', () {
      final m = parseTaskSentence(
        '[scan] harness_edit {"action":"apply_executable",'
        '"executableId":"x","symbolId":"sym_a"}',
      );
      expect(m, isA<TaskGrammarNoParse>());
      expect((m as TaskGrammarNoParse).failureClass, 'no_sentence');
    });
  });

  group('parseTaskSentence — HONEST failure (named classes, never a guess)',
      () {
    test('no_verb: does not start with a known imperative', () {
      final m = parseTaskSentence(
        'somehow make the geometry thing nicer please',
      );
      expect(m, isA<TaskGrammarNoParse>());
      expect((m as TaskGrammarNoParse).failureClass, 'no_verb');
    });
    test('unstructured_prose: a known verb whose rest does not fit', () {
      final m = parseTaskSentence('rename area into product');
      expect(m, isA<TaskGrammarNoParse>());
      expect((m as TaskGrammarNoParse).failureClass, 'unstructured_prose');
    });
    test('missing_target: the verb alone', () {
      final m = parseTaskSentence('fix');
      expect(m, isA<TaskGrammarNoParse>());
      expect((m as TaskGrammarNoParse).failureClass, 'missing_target');
    });
  });

  group('executableDecisionForTask — repair-class lookup', () {
    late World world;
    setUp(() {
      world = World()..addPlugin(AgentPlugin());
      // The tree: two symbols + a scanned-in pack inventory.
      addMeaningNode(
        world,
        kind: 'symbol',
        label: 'product',
        id: 'sym_lib_geometry.dart_product',
      );
      addMeaningNode(
        world,
        kind: 'symbol',
        label: 'area',
        id: 'sym_lib_geometry.dart_area',
      );
      addMeaningNode(
        world,
        kind: 'symbol',
        label: 'area',
        id: 'sym_lib_other.dart_area',
      ); // ambiguous on purpose
      reconcileCapabilityNodes(world, const [
        CapabilityEntry(
          executableId: 'dart/fix_loop_bound',
          kind: 'replace_member_body',
          params: ['symbolId'],
        ),
        CapabilityEntry(
          executableId: 'project/rename_field',
          kind: 'rename_symbol',
          params: ['symbolId', 'newName'],
        ),
      ]);
    });

    test('fix → replace_member_body executable + resolved symbolId', () {
      final m = parseTaskSentence('fix product in lib/geometry.dart')
          as TaskGrammarMatch;
      final r = executableDecisionForTask(world, m);
      expect(r.matched, isTrue, reason: r.reason);
      expect(r.decision!['action'], 'apply_executable');
      expect(r.decision!['executableId'], 'dart/fix_loop_bound');
      expect(r.decision!['symbolId'], 'sym_lib_geometry.dart_product');
      expect(r.decision!['source'], 'task_grammar');
    });

    test('apply <id> to <Symbol> → that executable + resolved symbolId', () {
      final m = parseTaskSentence('apply dart/fix_loop_bound to product')
          as TaskGrammarMatch;
      final r = executableDecisionForTask(world, m);
      expect(r.matched, isTrue, reason: r.reason);
      expect(r.decision!['executableId'], 'dart/fix_loop_bound');
    });

    test('rename → rename_symbol + executableParams.newName', () {
      addMeaningNode(world, kind: 'symbol', label: 'square', id: 'sym_sq');
      final m = parseTaskSentence('rename area to square')
          as TaskGrammarMatch;
      final r = executableDecisionForTask(world, m);
      // 'area' is ambiguous in this tree — the lookup must say so, not
      // guess.
      expect(r.matched, isFalse);
      expect(r.reason, 'ambiguous_target');
      // Unambiguous target carries the rename params through.
      final m2 = parseTaskSentence('rename product to item')
          as TaskGrammarMatch;
      final r2 = executableDecisionForTask(world, m2);
      expect(r2.matched, isTrue, reason: r2.reason);
      expect(r2.decision!['executableId'], 'project/rename_field');
      expect((r2.decision!['executableParams'] as Map)['newName'], 'item');
    });

    test('named misses: no executables, wrong target, run, missing symbol',
        () {
      final empty = World()..addPlugin(AgentPlugin());
      final m = parseTaskSentence('fix product') as TaskGrammarMatch;
      expect(executableDecisionForTask(empty, m).reason,
          'no_executables_in_tree');
      expect(
        executableDecisionForTask(
          world,
          parseTaskSentence('fix missingThing') as TaskGrammarMatch,
        ).reason,
        'target_not_in_tree',
      );
      expect(
        executableDecisionForTask(
          world,
          parseTaskSentence('run dart test') as TaskGrammarMatch,
        ).reason,
        'run_is_host_verb',
      );
      expect(
        executableDecisionForTask(
          world,
          parseTaskSentence('apply dart/fix_loop_bound')
              as TaskGrammarMatch,
        ).reason,
        'target_symbol_missing',
      );
      final noClass = World()..addPlugin(AgentPlugin());
      addMeaningNode(noClass, kind: 'symbol', label: 'product', id: 'sym_p');
      reconcileCapabilityNodes(noClass, const [
        CapabilityEntry(executableId: 'x/other', kind: 'insert_member'),
      ]);
      expect(
        executableDecisionForTask(noClass, m).reason,
        'no_executable_for_class',
      );
    });
  });
}
