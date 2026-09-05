// ignore_for_file: lines_longer_as_80_chars

/// ADR 0027 dogfood gate — the mechanical tick is actually incremental.
///
/// Measured failure this locks out: `scan` stored the TREE-NODE count as
/// the tick's comparison base while `refresh` re-enumerates dart files —
/// the mismatch made every no-op tick a FULL pass (5.8 s per prompt on the
/// monorepo, 1,121 files re-parsed with zero changes).
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'package:xsoulspace_agentic_workspace/xsoulspace_agentic_workspace.dart';

Future<Map<String, dynamic>> _execute(
  ToolDef etl,
  Map<String, dynamic> args,
) async =>
    jsonDecode(await etl.execute(args) ?? '{}') as Map<String, dynamic>;

void main() {
  late Directory jail;

  setUp(() async {
    jail = await Directory.systemTemp.createTemp('etl_tick_');
    File('${jail.path}/pubspec.yaml').writeAsStringSync('name: tick\n');
    File('${jail.path}/lib/a.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('int a() => 1;\n');
    File('${jail.path}/lib/b.dart').writeAsStringSync('int b() => 2;\n');
  });
  tearDown(() {
    try {
      jail.deleteSync(recursive: true);
    } on Object {
      // best effort
    }
  });

  test('no-op refresh parses NOTHING (the tick is mtime-gated per file)',
      () async {
    final world = World()..addPlugin(AgentPlugin());
    world..upsertResource(ToolRegistryResource());
    final state = RepoEtlState();
    final etl = repoEtlTool(world, jail, state: state);
    await _execute(etl, {'action': 'scan'});
    final r = await _execute(etl, {'action': 'refresh'});
    expect(
      r['refreshed_files'],
      0,
      reason: 'a no-change tick must not re-parse the workspace: $r',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('one changed file → exactly that file re-parsed', () async {
    final world = World()..addPlugin(AgentPlugin());
    world..upsertResource(ToolRegistryResource());
    final state = RepoEtlState();
    final etl = repoEtlTool(world, jail, state: state);
    await _execute(etl, {'action': 'scan'});
    // Guarantee an mtime strictly after the scan window.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    File('${jail.path}/lib/b.dart').writeAsStringSync('int b() => 3;\n');
    final r = await _execute(etl, {'action': 'refresh'});
    expect(r['refreshed_files'], 1, reason: '$r');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
