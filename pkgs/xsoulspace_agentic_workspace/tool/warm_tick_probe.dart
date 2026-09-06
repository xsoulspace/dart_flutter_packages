// ignore_for_file: avoid_print, lines_longer_than_80_chars

/// ADR 0027 warm-tick floor probe — measures the tree-driven reconcile
/// (`reconcileFsTier` via `repo_etl action=refresh`) against a REAL
/// monorepo checkout:
///
///   dart run tool/warm_tick_probe.dart [workspaceRoot]
///
/// Budget (PLAN §Open issues): a no-op warm tick < 300 ms.
library;

import 'dart:convert';
import 'dart:io';

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_agentic_workspace/xsoulspace_agentic_workspace.dart';

Future<void> main(List<String> args) async {
  final toolDir = File.fromUri(Platform.script).parent.path;
  final root = args.isNotEmpty
      ? args.first
      : Directory('$toolDir/../../..').absolute.path;
  final workspace = Directory(root);
  final world = World()..addPlugin(AgentPlugin());
  world..upsertResource(ToolRegistryResource());
  final etl = repoEtlTool(world, workspace);
  Future<Map<String, dynamic>> call(String action) async =>
      jsonDecode(await etl.execute({'action': action}) ?? '{}')
          as Map<String, dynamic>;

  final sw = Stopwatch()..start();
  final scan = await call('scan');
  print('scan (cold): ${sw.elapsedMilliseconds} ms — '
      '${scan['files']} files, ${scan['symbols']} symbols');

  sw.reset();
  final warm = await call('refresh');
  final warmMs = sw.elapsedMilliseconds;
  print('refresh #1 (warm, NO changes): $warmMs ms — $warm');

  sw.reset();
  final warm2 = await call('refresh');
  print('refresh #2 (warm, NO changes): ${sw.elapsedMilliseconds} ms — $warm2');

  // One real change: touch THIS probe file, tick again (the change path).
  File('${workspace.path}/pkgs/xsoulspace_agentic_workspace/tool/warm_tick_probe.dart')
      .setLastModifiedSync(DateTime.now());
  sw.reset();
  final changed = await call('refresh');
  print('refresh #3 (1 changed file): ${sw.elapsedMilliseconds} ms — $changed');

  print(warmMs < 300
      ? 'BUDGET: warm tick $warmMs ms < 300 ms — PASS'
      : 'BUDGET: warm tick $warmMs ms >= 300 ms — MISS');
}
