// Probe: edit via SpanEditMaterializer in a temp multi-file jail.
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('span_probe');
  final pubspec = File('${dir.path}/pubspec.yaml')..createSync(recursive: true);
  pubspec.writeAsStringSync(
    'name: span_jail\nenvironment: {sdk: ^3.0.0}\ndev_dependencies:\n  test: any\n');
  Directory('${dir.path}/lib').createSync();
  File('${dir.path}/lib/geometry.dart')
      .writeAsStringSync('int area(int w, int h) {\n  return w * h;\n}\n');
  final world = World()..addPlugin(AgentPlugin());
  final tool = repoEtlTool(world, dir);
  await tool.execute({'action': 'scan'});
  print('scan ok');
}
