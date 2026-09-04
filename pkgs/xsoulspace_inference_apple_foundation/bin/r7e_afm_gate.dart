// ignore_for_file: lines_longer_than_80_chars

/// R7 PRODUCTION #6 — R7e, THE GATE: one real AFM edit through the daemon
/// surface, pass@3 (ADR 0023; PLAN production #6).
///
/// In-process (not stdio) from the AFM app: the REAL Apple Foundation
/// Model drives the meaning-profile surface (repo_etl / meaning_zoom /
/// meaning_impact / edit_symbol / run — zero read, zero write) through the
/// SAME `runCodingAgentOnce` the daemon uses. The edit travels the PACK
/// PATH from production #3: the model supplies ONLY the executable id
/// (`dart/fix_loop_bound`) + the symbol id — the op-chain rides on the
/// project pack (zero authored op tokens). The free oracles grade:
/// scoped analyze in-move, `dart test` (the workspace convention) at the
/// goal gate.
///
/// ```sh
/// dart run bin/r7e_afm_gate.dart            # pass@3 against real AFM
/// dart run bin/r7e_afm_gate.dart --runs 1   # single probe
/// ```
///
/// Standing rule: the row is PUBLISHED even on FAIL, with the failure
/// class (context_window_exceeded? slot ambiguity? engine_unavailable?).
/// Exit code: 0 = all runs passed, 1 = any failure, 2 = AFM unavailable.
library;

import 'dart:convert';
import 'dart:io';

import 'package:xsoulspace_agentic_harness/benchmark_api.dart' show CheckerSpec;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_inference_apple_foundation/src/coding_agent_runner.dart';
import 'package:xsoulspace_inference_apple_foundation/src/intent_closure_runner.dart'
    show wireSigintDump;
import 'package:xsoulspace_inference_apple_foundation/src/native_bridge/native_client.dart';

const _packId = 'dart/fix_loop_bound';

/// The project pack entry as DATA (what production #3 captures/persists).
/// The model never sees this file — it picks the id.
const _packJson = {
  'packId': 'edit_capture',
  'executables': [
    {
      'id': _packId,
      'kind': 'replace_member_body',
      'params': ['symbolId'],
      'verification': ['analyze', 'test'],
      'scope': 'lexical',
      'description':
          'Fix an off-by-one inclusive bound: the member body becomes the '
          'inclusive form (i <= n, i.e. !(i > n)) over its declared '
          'params (i, n).',
      'opChain': [
        {'label': 'load_arg', 'a': 'i'},
        {'label': 'load_arg', 'a': 'n'},
        {'label': 'gt'},
        {'label': 'not'},
        {'label': 'return'},
      ],
    },
  ],
};

const _taskPrompt =
    'lib/loop.dart has an off-by-one bug: inBounds must be the INCLUSIVE '
    'bound (inBounds(3, 3) is true). The project pack carries the repair '
    'executable `$_packId`. Fix it with ONE edit_symbol call of EXACTLY '
    'this shape: {"action": "apply_executable", "executableId": '
    '"$_packId", "symbolId": <the TOP-LEVEL symbol id of inBounds, '
    'from the meaning_zoom cut>, "executableParams": {}} — this '
    'executable takes NO slots, so executableParams is EMPTY; symbolId '
    'is a top-level arg, never inside executableParams. Flow: repo_etl '
    'action scan (once) → meaning_zoom query inBounds → the edit_symbol '
    'call above → run dart analyze. Never read or write files. Do not '
    'rename anything and do not re-scan.';

Future<Directory> _seedJail(int run) async {
  final jail = await Directory.systemTemp.createTemp('r7e_afm_$run\_');
  File('${jail.path}/pubspec.yaml')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      'name: r7e_pack\nenvironment:\n  sdk: ^3.0.0\ndev_dependencies:\n  test: any\n',
    );
  File('${jail.path}/lib/loop.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
bool inBounds(int i, int n) {
  return i < n;
}
''');
  File('${jail.path}/test/loop_test.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
import 'package:test/test.dart';
import 'package:r7e_pack/loop.dart';

void main() {
  test('inBounds is inclusive', () {
    expect(inBounds(3, 3), isTrue);
  });
  test('inBounds rejects beyond', () {
    expect(inBounds(5, 4), isFalse);
  });
}
''');
  // The PACK PATH (production #3): the repair class lives in the project
  // pack; the model picks the id, never the chain.
  File('${jail.path}/.dart_tool/harnessd/edit_pack.json')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_packJson));
  await Process.run('dart', ['pub', 'get'], workingDirectory: jail.path);
  return jail;
}

CodingAgentTask _task() => CodingAgentTask(
  id: 'r7e_pack_edit',
  prompt: _taskPrompt,
  meaningProfile: true,
  systemPrompt: meaningProfileSystemPrompt,
  runCommand: const ['dart', 'test'],
  checkers: [CheckerSpec(type: 'runs', path: 'test', value: 'dart test')],
  repairHint:
      'The exact move that fixes this task: edit_symbol with '
      '{"action": "apply_executable", "executableId": "$_packId", '
      '"symbolId": <TOP-LEVEL id of inBounds from meaning_zoom>, '
      '"executableParams": {}}. If a move bounced, the bounce text names '
      'the exact repair — symbolId goes at the TOP LEVEL of the call, '
      'executableParams stays EMPTY for this executable. Do not rename '
      'and do not re-scan; the tree is already built.',
);

Future<void> main(List<String> args) async {
  final runs = args.contains('--runs')
      ? int.tryParse(args[args.indexOf('--runs') + 1]) ?? 3
      : 3;
  final client = AppleFoundationNativeClient();
  await client.load();
  if (!await client.refreshAvailability()) {
    stderr.writeln(
      'Apple Foundation Model unavailable — R7e stays UNTESTED, never '
      'PASS. (Classified failure: engine_unavailable.)',
    );
    exit(2);
  }
  stderr.writeln(
    '[r7e] AFM available — pass@$runs against the real '
    'on-device model through the meaning-profile surface.',
  );

  final router = ModelRouter(
    inferenceClientsBuilders: {
      DefaultModelNames.appleFoundation: () => AppleFoundationNativeClient(),
    },
  );
  final modelId = ModelId('r7e_afm_gate');
  router.models[modelId] = Model(
    id: modelId,
    name: DefaultModelNames.appleFoundation,
  );

  final runsDir = resolveRunsDirectory();
  final results = <CodingAgentRunResult>[];
  for (var i = 1; i <= runs; i++) {
    final jail = await _seedJail(i);
    stderr.writeln('[r7e] run $i/$runs — jail ${jail.path}');
    final sw = Stopwatch()..start();
    final result = await runCodingAgentOnce(
      task: _task(),
      jail: jail,
      handler: DefaultGenerationHandler(router: router),
      backend: 'apple_foundation_afm',
      onRecorder: wireSigintDump,
      router: router,
      actorModelId: modelId,
      leanContextProfile: true,
      maxGoalAttempts: 3,
    );
    sw.stop();
    final logFile = writeRunLog(
      runsDir,
      'r7e_afm_run$i.log',
      formatRunLog(result),
    );
    stdout.writeln(
      '[r7e] run $i/$runs: ${result.passed ? "PASS" : "FAIL"} '
      '(decisions ${result.decisions}, rounds ${result.toolRounds}, '
      'tokens ${result.projectionTokens}, '
      'moves ${result.moves}, wall ${sw.elapsed.inSeconds}s) '
      'failureClass: ${result.failureClass.isEmpty ? "-" : result.failureClass}\n'
      '  → ${logFile.path}',
    );
    if (!result.passed) {
      for (final c in result.finalGate) {
        if (!c.passed) stdout.writeln('  gate: ${c.detail.split('\n').first}');
      }
    }
    results.add(result);
    jail.deleteSync(recursive: true);
  }

  final passed = results.where((r) => r.passed).length;
  final failureClasses = {
    for (final r in results)
      if (!r.passed) r.failureClass.isEmpty ? 'unclassified' : r.failureClass,
  };
  final summary =
      'R7e (production #6) — task: r7e_pack_edit (pack-fed apply_executable '
      'via $_packId) | backend: apple_foundation_afm (REAL on-device model) '
      '| decision path: meaning-profile surface (repo_etl/meaning_zoom/'
      'meaning_impact/edit_symbol/run) | tokens source: '
      'Situation.tokensUsed (projection) | composition: coderLean (lean '
      'context profile) | n: $runs | pass@$runs: $passed/$runs | '
      'failure classes: ${failureClasses.isEmpty ? "-" : failureClasses.join(", ")}';
  writeRunLog(runsDir, 'r7e_afm_summary.log', '$summary\n');
  stdout.writeln('\n$summary');
  exit(passed == runs ? 0 : 1);
}
