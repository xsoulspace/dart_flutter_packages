// ignore_for_file: lines_longer_than_80_chars

/// PLAN Stage H4 — the `intents` suite checker: a real `dart` subprocess
/// replays scripted intent calls against the materialized program. exit 0
/// iff every call compiles, runs, and matches expectations. The strongest
/// deterministic behavior oracle in the suite.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:xsoulspace_agentic_harness/src/benchmark/coding_suite/checkers.dart';
import 'package:xsoulspace_agentic_harness/src/benchmark/coding_suite/task_spec.dart';

const _programSource = r'''
// The host materializer's output (hand-written fixture standing in for it):
// pure intent functions over a JSON state map — no I/O.
Map<String, dynamic> initialState() => {'bookmarks': <String>[]};

Map<String, dynamic> runIntent(
  String name,
  Map<String, dynamic> state,
  Map<String, dynamic> args,
) {
  switch (name) {
    case 'save_url':
      final url = args['url'] as String?;
      if (url == null || !url.startsWith('http')) {
        return {'saved': false, 'reason': 'invalid url'};
      }
      final bookmarks = [...(state['bookmarks'] as List).cast<String>(), url];
      return {'_state': {'bookmarks': bookmarks}, '_result': {'saved': true}};
    case 'list_saved':
      return {'count': (state['bookmarks'] as List).length};
    default:
      throw ArgumentError('unknown intent: $name');
  }
}
''';

void main() {
  late Directory jail;
  setUp(() async {
    jail = await Directory.systemTemp.createTemp('intent_checker_');
    File('${jail.path}/program.dart').writeAsStringSync(_programSource);
  });
  tearDown(() => jail.delete(recursive: true));

  test('all scripted intent calls verified → pass', () {
    final spec = CheckerSpec(
      type: 'intents',
      value: jsonEncode({
        'calls': [
          {
            'intent': 'save_url',
            'args': {'url': 'https://example.dev'},
            'expect': {'saved': true},
          },
          {
            'intent': 'save_url',
            'args': {'url': 'https://second.dev'},
          },
          {
            'intent': 'list_saved',
            'expect': {'count': 2},
          },
        ],
      }),
    );
    final result = evaluateChecker(spec, jail.path);
    expect(result.passed, isTrue, reason: result.detail);
    expect(result.detail, contains('all 3 calls verified'));
  });

  test('a wrong expected result → fail (behavior, not compilation)', () {
    final spec = CheckerSpec(
      type: 'intents',
      value: jsonEncode({
        'calls': [
          {'intent': 'list_saved', 'expect': {'count': 99}},
        ],
      }),
    );
    final result = evaluateChecker(spec, jail.path);
    expect(result.passed, isFalse);
  });

  test('an unimplemented intent → fail with the error surfaced', () {
    final spec = CheckerSpec(
      type: 'intents',
      value: jsonEncode({
        'calls': [
          {'intent': 'delete_url', 'args': {'url': 'https://x.dev'}},
        ],
      }),
    );
    final result = evaluateChecker(spec, jail.path);
    expect(result.passed, isFalse);
    expect(result.detail, contains('unknown intent'));
  });

  test('a missing materialized program → fail without spawning', () {
    jail.deleteSync(recursive: true);
    jail.createSync();
    final spec = CheckerSpec(type: 'intents', value: '{"calls": []}');
    final result = evaluateChecker(spec, jail.path);
    expect(result.passed, isFalse);
    expect(result.detail, contains('materialized program missing'));
  });
}
