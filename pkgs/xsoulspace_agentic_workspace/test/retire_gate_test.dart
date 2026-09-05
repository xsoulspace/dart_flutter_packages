// ignore_for_file: lines_longer_as_80_chars

/// RETIRE gate — `remove_member` (ADR 0027 amendment): meaning-first
/// deletion. The model never addresses files; the host derives the fs
/// consequence (member + doc comment pruned, layout re-derives) and the
/// refs fence proves the referencers were retired first. LLM-free.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'package:xsoulspace_agentic_workspace/xsoulspace_agentic_workspace.dart';

Future<Directory> _jail() async {
  final dir = await Directory.systemTemp.createTemp('retire_jail_');
  File('${dir.path}/pubspec.yaml')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
name: retire_jail
environment:
  sdk: ^3.0.0
dev_dependencies:
  test: any
''');
  // `label` is unreferenced (clean retire; note the doc comment above it —
  // the materializer prunes it too). `area` is referenced by report.dart
  // (the refs-fence case).
  File('${dir.path}/lib/geometry.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
/// Shapes a name for display.
/// Second doc line.
String label(String name) {
  return 'shape: \$name';
}

int area(int w, int h) {
  return w * h;
}
''');
  File('${dir.path}/lib/report.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
import 'geometry.dart';

String report() {
  return 'area=\${area(2, 3)}';
}
''');
  await Process.run('dart', ['pub', 'get'], workingDirectory: dir.path);
  return dir;
}

World _world(Directory jail) {
  final world = World()..addPlugin(AgentPlugin());
  world
    ..upsertResource(ToolRegistryResource())
    ..upsertResource(FlightRecorder())
    ..flush();
  final registry = ToolRegistry();
  registry.register(repoEtlTool(world, jail));
  registry.register(editSymbolTool(world, jail));
  world.getResource<ToolRegistryResource>().register('default', registry);
  return world;
}

/// Executes a registered tool and decodes its JSON result.
Future<Map<String, dynamic>> runTool(
  World world,
  String name,
  Map<String, dynamic> args,
) async {
  final raw = await world
      .getResource<ToolRegistryResource>()
      .get('default')!
      .execute(ToolName(name), args);
  return (jsonDecode(raw ?? '{}') as Map).cast<String, dynamic>();
}

Future<String> _scan(World world, Directory jail) async {
  await repoEtlTool(world, jail).execute({'action': 'scan'});
  final index = world.getResource<MeaningIndex>();
  return index.byId.keys
      .where((id) => id.endsWith('_label') || id.endsWith('_label_1'))
      .first;
}

void main() {
  test('clean retire: member + doc comment pruned, layout re-derives', () async {
    final jail = await _jail();
    addTearDown(() => jail.deleteSync(recursive: true));
    final world = _world(jail);
    final labelId = await _scan(world, jail);

    final out = await runTool(world, 'edit_symbol', {
      'action': 'remove_member',
      'symbolId': labelId,
    });
    expect(out['ok'], true, reason: '${out}');
    final text = File('${jail.path}/lib/geometry.dart').readAsStringSync();
    expect(text, isNot(contains('String label(')));
    expect(text, isNot(contains('Shapes a name')), reason: 'doc comment pruned');
    expect(text, isNot(contains('Second doc line')));
    expect(text, contains('int area('), reason: 'siblings untouched');
    // No blank-line residue: exactly one newline separates the file top
    // from `area` after the prune (the materializer never leaves skeletons).
    expect(text, isNot(contains('\n\n\n')));
  });

  test('refs fence: a referenced member bounces with named locations', () async {
    final jail = await _jail();
    addTearDown(() => jail.deleteSync(recursive: true));
    final world = _world(jail);
    await repoEtlTool(world, jail).execute({'action': 'scan'});
    final index = world.getResource<MeaningIndex>();
    final areaId = index.byId.keys
        .where((id) => id.endsWith('_area') || id.endsWith('_area_1'))
        .first;

    final out = await runTool(world, 'edit_symbol', {
      'action': 'remove_member',
      'symbolId': areaId,
    });
    expect(out['ok'], false);
    expect(out['fence'], 'integration');
    expect('${out['error']}', contains('report.dart'));
    expect('${out['repair']}', contains('referencers first'));
    // Bytes untouched — a bounced move claims nothing.
    expect(File('${jail.path}/lib/report.dart').readAsStringSync(),
        contains('area(2, 3)'));
  });

  test('composable retire: after the referencer is retired, the move lands',
      () async {
    final jail = await _jail();
    addTearDown(() => jail.deleteSync(recursive: true));
    final world = _world(jail);
    await repoEtlTool(world, jail).execute({'action': 'scan'});
    final index = world.getResource<MeaningIndex>();
    final areaId = index.byId.keys
        .where((id) => id.endsWith('_area') || id.endsWith('_area_1'))
        .first;

    // Simulate the referencer's retirement (a prior move in the same
    // decision chain): report.dart no longer uses `area`.
    File('${jail.path}/lib/report.dart').writeAsStringSync(
      "import 'geometry.dart';\n\nString report() {\n  return 'report';\n}\n",
    );
    final out = await runTool(world, 'edit_symbol', {
      'action': 'remove_member',
      'symbolId': areaId,
    });
    expect(out['ok'], true, reason: '${out}');
    expect(
      File('${jail.path}/lib/geometry.dart').readAsStringSync(),
      isNot(contains('int area(')),
    );
  });
}
