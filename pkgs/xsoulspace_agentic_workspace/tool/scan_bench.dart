import 'dart:io';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_agentic_workspace/xsoulspace_agentic_workspace.dart';

Future<void> main() async {
  final ws = Directory(Platform.environment['SCAN_WS']!);
  final world = World()..addPlugin(AgentPlugin());
  world..upsertResource(ToolRegistryResource());
  final state = RepoEtlState();
  final etl = repoEtlTool(world, ws, state: state);
  var sw = Stopwatch()..start();
  await etl.execute({'action': 'scan'});
  sw.stop();
  // ignore: avoid_print
  print('cold scan: ${sw.elapsedMilliseconds} ms');
  sw = Stopwatch()..start();
  final r = await etl.execute({'action': 'refresh'});
  sw.stop();
  // ignore: avoid_print
  print('warm tick (no changes): ${sw.elapsedMilliseconds} ms');
  // ignore: avoid_print
  print(r.toString().length > 200 ? r.toString().substring(0, 200) : r);
  // Touch one file, tick again (the real maintenance case).
  File('${ws.path}/pkgs/xsoulspace_agentic_host/lib/src/harnessd_cli.dart')
      .writeAsStringSync(
    File('${ws.path}/pkgs/xsoulspace_agentic_host/lib/src/harnessd_cli.dart')
        .readAsStringSync(),
  );
  sw = Stopwatch()..start();
  await etl.execute({'action': 'refresh'});
  sw.stop();
  // ignore: avoid_print
  print('warm tick (1 file changed): ${sw.elapsedMilliseconds} ms');
}
