// ignore_for_file: lines_longer_than_80_chars

/// Meaning-executor experiment (PLAN Stage I, decision D3 evidence gate):
/// the model shapes executor LOGIC through meaning moves over a CLOSED op
/// vocabulary. Pins:
/// 1. interpreter semantics (bookmark-manager chain built purely via moves);
/// 2. in-process parity with the materialized Dart (via the real `intents`
///    checker on a real `dart` subprocess);
/// 3. closed-vocabulary + malformed-chain failures-as-data;
/// 4. `intent_call` falls back to the meaning-program and threads state.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:xsoulspace_agentic_harness/src/benchmark/coding_suite/checkers.dart';
import 'package:xsoulspace_agentic_harness/src/benchmark/coding_suite/task_spec.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

World _world() => World()..addPlugin(AgentPlugin());

/// Builds the bookmark-manager executor purely through meaning moves
/// (what a scripted/real model would emit via act_with_project).
void _buildBookmarkExecutor(World world) {
  defineIntent(
    world,
    name: 'save_url',
    params: ['url:string'],
    description: 'Saves a URL if it starts with http.',
  );
  defineIntent(world, name: 'list_saved', description: 'Counts bookmarks.');
  // ops (per-kind ids: op_1..op_9)
  addMeaningNode(world, kind: 'op', label: 'load_arg', props: {'a': 'url'});
  addMeaningNode(world, kind: 'op', label: 'starts_with', props: {'b': 'http'});
  addMeaningNode(world, kind: 'op', label: 'jump_if_false', props: {'b': 'op_6'});
  addMeaningNode(world, kind: 'op', label: 'push_state', props: {'a': 'bookmarks'});
  addMeaningNode(world, kind: 'op', label: 'literal', props: {'b': '{"saved": true}'});
  addMeaningNode(
    world,
    kind: 'op',
    label: 'literal',
    props: {'b': '{"saved": false, "reason": "invalid url"}'},
  );
  addMeaningNode(world, kind: 'op', label: 'load_state', props: {'a': 'bookmarks'});
  addMeaningNode(world, kind: 'op', label: 'list_len');
  addMeaningNode(world, kind: 'op', label: 'return');
  // wiring
  linkMeaning(world, from: 'save_url', relation: 'impl', to: 'op_1');
  linkMeaning(world, from: 'list_saved', relation: 'impl', to: 'op_7');
  for (final pair in [
    ['op_1', 'op_2'], ['op_2', 'op_3'], ['op_3', 'op_4'], ['op_4', 'op_5'],
    ['op_5', 'op_9'], ['op_6', 'op_9'], ['op_7', 'op_8'], ['op_8', 'op_9'],
  ]) {
    linkMeaning(world, from: pair[0], relation: 'then', to: pair[1]);
  }
}

void main() {
  test('interpreter: bookmark chain behaves correctly over threaded state', () {
    final world = _world();
    _buildBookmarkExecutor(world);
    var state = <String, dynamic>{};

    final save1 = interpretMeaningProgram(world, 'save_url', state, {
      'url': 'https://example.dev',
    });
    expect((save1['_result'] as Map)['saved'], true);
    state = save1['_state'] as Map<String, dynamic>;

    final save2 = interpretMeaningProgram(world, 'save_url', state, {
      'url': 'https://second.dev',
    });
    state = save2['_state'] as Map<String, dynamic>;

    final saveBad = interpretMeaningProgram(world, 'save_url', state, {
      'url': 'not-a-url',
    });
    expect((saveBad['_result'] as Map)['saved'], false);
    state = saveBad['_state'] as Map<String, dynamic>;

    final listed = interpretMeaningProgram(world, 'list_saved', state, {});
    expect(listed['_result'], {'value': 2}); // two saves, bad one rejected
  });

  test('intent_call falls back to the meaning program and threads state', () async {
    final world = _world();
    _buildBookmarkExecutor(world);
    final r1 = await callIntent(world, name: 'save_url', args: {'url': 'https://a.dev'});
    expect(r1['ok'], true);
    final r2 = await callIntent(world, name: 'list_saved');
    expect((r2['result'] as Map)['value'], 1); // state persisted in-world
  });

  test('closed vocabulary: an op outside the set fails as data', () {
    final world = _world();
    defineIntent(world, name: 'x');
    addMeaningNode(world, kind: 'op', label: 'reformat_disk');
    linkMeaning(world, from: 'x', relation: 'impl', to: 'op_1');
    final out = interpretMeaningProgram(world, 'x', {}, {});
    expect((out['_result'] as Map)['error'], contains('closed vocabulary'));
  });

  test('malformed chain (no impl edge) fails as data, no throw', () {
    final world = _world();
    defineIntent(world, name: 'lonely');
    final out = interpretMeaningProgram(world, 'lonely', {}, {});
    expect((out['_result'] as Map)['error'], contains('no meaning executor'));
  });

  test('PARITY: materialized Dart behaves like the interpreter (real dart)', () async {
    final world = _world();
    _buildBookmarkExecutor(world);
    final jail = await Directory.systemTemp.createTemp('meaning_parity_');
    addTearDown(() => jail.delete(recursive: true).catchError((_) {}));

    File('${jail.path}/program.dart')
        .writeAsStringSync(materializeMeaningProgram(world));
    final spec = CheckerSpec(
      type: 'intents',
      value: jsonEncode({
        'calls': [
          {
            'intent': 'save_url',
            'args': {'url': 'https://example.dev'},
            'expect': {'saved': true},
          },
          {'intent': 'list_saved', 'expect': {'value': 1}},
          {
            'intent': 'save_url',
            'args': {'url': 'nope'},
            'expect': {'saved': false},
          },
          {'intent': 'list_saved', 'expect': {'value': 1}},
        ],
      }),
    );
    final result = evaluateChecker(spec, jail.path);
    expect(result.passed, isTrue, reason: result.detail);
  });

  test('validateMeaningProgram: valid chain → no problems; broken chain → '
      'actionable problem with intent name', () {
    final world = _world();
    _buildBookmarkExecutor(world);
    expect(validateMeaningProgram(world), isEmpty);

    final broken = _world();
    defineIntent(broken, name: 'dangling');
    addMeaningNode(broken, kind: 'op', label: 'load_state', props: {'a': 'x'});
    // impl edge exists but NO then edge to a return op — the AFM run's
    // exact failure mode ('chain ended without return').
    linkMeaning(broken, from: 'dangling', relation: 'impl', to: 'op_1');
    final problems = validateMeaningProgram(broken);
    expect(problems, hasLength(1));
    expect(problems.first, contains('dangling: chain ended without return'));
  });

  test('stewardship probe: the op vocabulary is closed + countable', () {
    expect(meaningExecutorOps.toSet().length, meaningExecutorOps.length);
    expect(meaningExecutorOps.length, 14);
  });

  test(
      'FAILURE-PATH PARITY: interpreter and materialized Dart agree on '
      'malformed chains (the AFM run caught this divergence)',
      () async {
    final jail = await Directory.systemTemp.createTemp('meaning_parity_bad_');
    addTearDown(() => jail.delete(recursive: true).catchError((_) {}));

    // Chains that exercised every edge the AFM bookmark run hit:
    // load_arg without prop a, unknown op target, empty-stack ops.
    final world = _world();
    defineIntent(world, name: 'no_arg');
    addMeaningNode(world, kind: 'op', label: 'load_arg'); // no a → args itself
    addMeaningNode(world, kind: 'op', label: 'starts_with'); // no b → error
    linkMeaning(world, from: 'no_arg', relation: 'impl', to: 'op_1');
    linkMeaning(world, from: 'op_1', relation: 'then', to: 'op_2');

    final inProcess = interpretMeaningProgram(
      world,
      'no_arg',
      <String, dynamic>{},
      <String, dynamic>{},
    );

    File('${jail.path}/program.dart')
        .writeAsStringSync(materializeMeaningProgram(world));
    final spec = CheckerSpec(
      type: 'intents',
      value: jsonEncode({
        'calls': [
          {'intent': 'no_arg'},
        ],
      }),
    );
    final materialized = evaluateChecker(spec, jail.path);

    // BOTH must return errors-as-data (no throw) with the same shape.
    final interpResult = inProcess['_result'] as Map;
    expect(interpResult, contains('error'),
        reason: 'starts_with without prefix must be errors-as-data');
    // The materialized run must fail the checker by comparing the SAME
    // expected shape — i.e. the result IS an error result, identically.
    final checkerDetail = materialized.detail;
    expect(checkerDetail,
        contains('{error: starts_with without prefix (op op_2)}'),
        reason: 'materialized VM must agree with the interpreter AND carry '
            'the op id so the model can repair with set_prop: '
            '$checkerDetail');
  });
}
