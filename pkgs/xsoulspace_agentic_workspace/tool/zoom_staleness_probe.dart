// ignore_for_file: avoid_print, lines_longer_than_80_chars

/// Throwaway probe (lane B′): point-zoom wall time with the staleness
/// re-stat wired — no-op (one stat) vs drift (one stat + one re-read).
import 'dart:convert';
import 'dart:io';

import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_agentic_workspace/xsoulspace_agentic_workspace.dart';

Map<String, dynamic> _decoded(Object? raw) => raw is String
    ? jsonDecode(raw) as Map<String, dynamic>
    : raw! as Map<String, dynamic>;

Future<void> main() async {
  final jail = await Directory.systemTemp.createTemp('zoom_probe_');
  File('${jail.path}/docs/guide.md')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('# Guide\n\nintro\n\n## Usage\n\nRun the tool.\n');
  final world = World()..addPlugin(AgentPlugin());
  world.upsertResource(ToolRegistryResource());
  final root = FsToolsRoot(jail.path);
  await repoEtlTool(world, jail).execute({'action': 'scan'});
  final zoom = meaningZoomTool(world, spanReader: meaningSpanReader(root));
  const args = {
    'focusId': 'sec_f_docs_guide.md_2',
    'zoom': 'point',
    'budget': 1024,
  };
  // warm + no-op drift: 200 point zooms, all hitting only the one stat.
  final sw = Stopwatch()..start();
  for (var i = 0; i < 200; i++) {
    await zoom.execute(Map.of(args));
  }
  final noopUs = sw.elapsedMicroseconds ~/ 200;
  // drift: one edit, then the FIRST zoom pays the re-read.
  await Future<void>.delayed(const Duration(milliseconds: 20));
  File('${jail.path}/docs/guide.md').writeAsStringSync(
      '# Guide\n\nintro\n\n## Usage\n\nRun the tool. Edited prose here.\n');
  sw..reset()..start();
  final cut = _decoded(await zoom.execute(Map.of(args)));
  final driftUs = sw.elapsedMicroseconds;
  jail.deleteSync(recursive: true);
  print('noop point zoom: ${noopUs}us avg (n=200) | drift zoom: '
      '${driftUs}us (incl. one re-read + map rebuild) | refreshed: '
      '${cut['refreshed']} | post-edit span served: '
      "${((cut['span'] as Map)['text'] as String).contains('Edited prose')}");
}
