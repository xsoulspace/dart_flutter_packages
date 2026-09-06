// ignore_for_file: lines_longer_than_80_chars

/// FS CAPABILITY gate (effects-as-data): `fs_stat` is registered as DATA
/// on the world by `repoEtlTool` — jailed to the workspace, structured
/// errors on traversal, honest `{exists: false}` on missing paths. Intents
/// compose it like any op (interpreter tier; materialization bounces as a
/// named problem until the op's emitter lands).
library;

import 'dart:convert';
import 'dart:io';

import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/src/agent.dart' show AgentPlugin;
import 'package:xsoulspace_agentic_harness/src/meaning/intents.dart'
    show intentDefineTool;
import 'package:xsoulspace_agentic_harness/src/meaning/meaning_program.dart';
import 'package:xsoulspace_agentic_harness/src/meaning/meaning_tree.dart';

import 'package:xsoulspace_agentic_workspace/xsoulspace_agentic_workspace.dart';

void main() {
  late Directory jail;
  late World world;

  setUp(() {
    jail = Directory.systemTemp.createTempSync('fs_capability_');
    File('${jail.path}/notes.md').writeAsStringSync('# Notes\n\nhello\n');
    world = World()..addPlugin(AgentPlugin());
    repoEtlTool(world, jail); // registers the fs_stat capability on the world
  });
  tearDown(() {
    try {
      jail.deleteSync(recursive: true);
    } on Object {
      // best effort
    }
  });

  Future<Map<String, dynamic>> runIntent(
    String name,
    Map<String, dynamic> args,
  ) async {
    final out = interpretMeaningProgram(world, name, const {}, args);
    return out;
  }

  test('fs_stat answers a workspace-relative path', () async {
    final ids = addChainFromSpecs(world, [
      {'label': 'fs_stat', 'b': 'notes.md'},
      {'label': 'return'},
    ], effectOps: {'fs_stat'})!;
    addMeaningNode(world, kind: 'intent', label: 'stat_notes', id: 'i_stat');
    linkMeaning(world, from: 'i_stat', relation: 'impl', to: ids.first);
    final out = await runIntent('i_stat', const {});
    final result = out['_result'] as Map;
    expect(result['exists'], true, reason: '$result');
    expect(result['size'], greaterThan(0));
    expect(result['type'], 'file');
  });

  test('fs_stat on a missing path is honest data, not an error', () async {
    final ids = addChainFromSpecs(world, [
      {'label': 'fs_stat', 'b': 'nope.md'},
      {'label': 'return'},
    ], effectOps: {'fs_stat'})!;
    addMeaningNode(world, kind: 'intent', label: 'stat_missing', id: 'i_m');
    linkMeaning(world, from: 'i_m', relation: 'impl', to: ids.first);
    final out = await runIntent('i_m', const {});
    expect((out['_result'] as Map)['exists'], false);
  });

  test('fs_stat refuses traversal and absolute paths (the jail holds)',
      () async {
    File('${jail.parent.path}/outside.md').writeAsStringSync('secret');
    for (final (idx, bad) in ['../outside.md', '/etc/hosts'].indexed) {
      final ids = addChainFromSpecs(world, [
        {'label': 'fs_stat', 'b': bad},
        {'label': 'return'},
      ], effectOps: {'fs_stat'})!;
      addMeaningNode(
        world,
        kind: 'intent',
        label: 'stat_$idx',
        id: 'i_x$idx',
      );
      linkMeaning(world, from: 'i_x$idx', relation: 'impl', to: ids.first);
      final out = await runIntent('i_x', const {});
      expect(
        (out['_result'] as Map)['error'],
        contains('workspace-relative'),
        reason: '$bad must bounce: ${out['_result']}',
      );
    }
  });

  test('intent_define accepts fs_stat once the capability is registered',
      () async {
    final tool = intentDefineTool(world);
    final out = jsonDecode(
      await tool.execute({
        'action': 'define',
        'name': 'stat_it',
        'specs': [
          {'label': 'fs_stat', 'b': 'notes.md'},
          {'label': 'return'},
        ],
      }) ?? '{}',
    ) as Map<String, dynamic>;
    expect(out['ok'], true, reason: '$out');
  });
}
