// Probe: perform the same rename apply through SpanEditMaterializer on a
// temp multi-file jail and print the edit outcome.
import 'dart:io';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:ecsly/ecsly.dart';
import 'package:xsoulspace_agentic_dart_meaning/xsoulspace_agentic_dart_meaning.dart';

void main() async {
  final dir = await Directory.systemTemp.createTemp('span_probe_');
  final pubspec = File('${dir.path}/pubspec.yaml')..parent.createSync(recursive: true);
  pubspec.writeAsStringSync('name: span_jail\nenvironment:\n  sdk: ^3.0.0\ndev_dependencies:\n  test: any\n');
  Directory('${dir.path}/lib').createSync();
  File('${dir.path}/lib/geometry.dart').writeAsStringSync(
      'int area(int w, int h) {\n  return w * h;\n}\n');
  File('${dir.path}/lib/report.dart').writeAsStringSync(
      "import 'geometry.dart';\n\nString report() {\n  return 'area=' + area(2, 3);\n}\n");
  final world = World()..addPlugin(AgentPlugin());
  final sw = Stopwatch()..start();
  final tool = repoEtlTool(world, dir);
  await tool.execute({'action': 'scan'});
  final index = world.getResource<MeaningIndex>();
  final areaId = index.byId.keys.where((i) => i.endsWith('_area')).first;
  print('resolved id: $areaId');
  final mat = SpanEditMaterializer(world: world, workspace: dir);
  final plan = mat.plan(
    action: 'apply_executable',
    executableId: 'rename_symbol',
    symbolId: areaId,
    executableParams: {'newName': 'surfaceX'},
  );
  print('plan: ${plan.description}');
  final out = await mat.apply(plan);
  print('outcome: ${out.toJson()}');
  sw.stop();
  print('total wall: ${sw.elapsedMilliseconds}ms');
  await Directory(dir.path).delete(recursive: true);
}
