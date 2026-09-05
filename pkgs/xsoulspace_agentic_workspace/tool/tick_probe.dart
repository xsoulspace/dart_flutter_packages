import 'dart:io';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_agentic_workspace/xsoulspace_agentic_workspace.dart';

Future<void> main() async {
  final ws = Directory(Platform.environment['SCAN_WS']!);
  final world = World()..addPlugin(AgentPlugin());
  world..upsertResource(ToolRegistryResource());
  final state = RepoEtlState();
  final etl = repoEtlTool(world, ws, state: state);
  await etl.execute({'action': 'scan'});
  // ignore: avoid_print
  print('st.dartFiles (stored): ${state.dartFiles}');
  // ignore: avoid_print
  print('dartFiles() count (refresh base): ${dartFiles(ws).length}');
  // ignore: avoid_print
  print('st.lastScan: ${state.lastScan}');
  // Sample mtimes vs cutoff.
  var after = 0;
  for (final f in dartFiles(ws)) {
    if (f.statSync().modified.isAfter(state.lastScan!)) after++;
  }
  // ignore: avoid_print
  print('files with mtime after cutoff: $after');
}
