// ignore_for_file: lines_longer_than_80_chars

/// The mechanical-read dialect asserted against the LIVE one-truth
/// registry (the surface_gaps 2026-09-08 row's closure gate).
///
/// The drift this test kills: the pi extension wrapped the LEGACY per-verb
/// read tools (`harness_locate` / `harness_zoom` / `harness_impact`) while
/// the ADR 0030 graduation replaced them with the ONE `harness_meaning_program`
/// directive — so every interactive session read DELEGATED TO THE MOVER
/// (measured ~140 s wall + `mover_refusal`), the exact stale-teaching class
/// the wave rows measured, reproduced by the session itself.
///
/// The law: the classifier's mechanical read forms bind to the LIVE
/// registry BOTH ways —
/// 1. every recognized read form is served by a registry tool that EXISTS;
/// 2. the program op set is derived from the LIVE tool's own closed-set
///    contract (the halt bounce), never from a name list;
/// 3. the legacy wrapper names are NOT mechanically recognized and NOT in
///    the registry — re-adding a wrapper without registry support fails here.
///
/// Also meters the mechanical read wall over a REAL scanned tree (<100 ms —
/// the 2026-09-06 rows measured 34–54 ms warm).
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart'
    show FsToolsRoot;
import 'package:xsoulspace_agentic_host/xsoulspace_agentic_host.dart';
import 'package:xsoulspace_agentic_host/src/harness_acp_backend.dart'
    show classifyReasoning, isReadOnlyDirectivePrompt;
import 'package:xsoulspace_agentic_host/src/meaning_profile_surface.dart'
    show buildMeaningProfileSurface;

void main() {
  test('the mechanical-read set binds to the LIVE registry (both ways)',
      () async {
    final world = World()..addPlugin(AgentPlugin());
    world.upsertResource(ToolRegistryResource());
    final jail = Directory.systemTemp.createTempSync('read_dialect_');
    addTearDown(() => jail.deleteSync(recursive: true));
    final surface = await buildMeaningProfileSurface(
      world: world,
      workspace: jail,
      fsRoot: FsToolsRoot(jail.path),
      refreshTree: false,
    );
    final toolNames = surface.registry.tools.keys
        .map((n) => n.value)
        .toSet();

    // 1. Every classifier-recognized read form is SERVED by the registry.
    expect(toolNames, contains('repo_etl'),
        reason: '[scan] is mechanical, so the tree-ingestion tool must exist');
    expect(toolNames, contains('meaning_program'),
        reason: 'harness_meaning_program is mechanical, so the read-program '
            'tool must exist');

    // 2. The program op set derived LIVE from the tool's own contract: an
    //    unknown op halts with the closed-set bounce.
    final program = surface.registry.tools.values
        .firstWhere((t) => t.name.value == 'meaning_program');
    final probe = await program.execute({
      'ops': [
        {'op': '__probe__'},
      ],
    });
    final probeMap =
        probe is String ? _decode(probe) : (probe as Map).cast<String, Object?>();
    final halt = probeMap!['program_halt'] as Map?;
    expect(halt, isNotNull, reason: 'the closed-set bounce is the contract');
    final closedSetText = '${halt!['error']}';
    final opsMatch = RegExp(r'\[(.*?)\]').firstMatch(closedSetText);
    expect(opsMatch, isNotNull,
        reason: 'the halt names the closed set: $closedSetText');
    final liveOps = opsMatch!
        .group(1)!
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    expect(liveOps, isNotEmpty);
    for (final op in liveOps) {
      final payload = 'harness_meaning_program '
          '{"ops":[{"op":"$op","query":"x"}]}';
      expect(isReadOnlyDirectivePrompt(payload), isTrue,
          reason: 'the live op "$op" must travel as a MECHANICAL read '
              'directive (never a mover task)');
    }

    // 3. The legacy wrapper names: NOT in the registry, NOT mechanically
    //    recognized — the exact 2026-09-08 drift, pinned as a named class.
    for (final legacy in const ['harness_locate', 'harness_zoom', 'harness_impact']) {
      expect(toolNames, isNot(contains(legacy)),
          reason: '$legacy was graduated OUT of the registry (ADR 0030 §3)');
      expect(isReadOnlyDirectivePrompt('$legacy {"query":"x"}'), isFalse,
          reason: '$legacy payloads must never masquerade as mechanical '
              'reads — the wrapper belongs in the extension, translated to '
              'harness_meaning_program ops');
    }

    // 4. The classifier serves reads at reasoning 'none' (the mover never
    //    wakes for a read).
    expect(
      classifyReasoning(
        'harness_meaning_program {"ops":[{"op":"locate","query":"area"}]}',
      ),
      'none',
    );
  });

  test('the mechanical read path is FAST over a real scanned tree (<100 ms)',
      () async {
    final world = World()..addPlugin(AgentPlugin());
    world.upsertResource(ToolRegistryResource());
    final jail = await Directory.systemTemp.createTemp('read_wall_');
    addTearDown(() => jail.deleteSync(recursive: true));
    File('${jail.path}/lib/geometry.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('''
int area(int w, int h) {
  return w * h;
}
''');
    File('${jail.path}/docs/README.md')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('# Doc\n\n## Usage\n\nRun it.\n');

    final surface = await buildMeaningProfileSurface(
      world: world,
      workspace: jail,
      fsRoot: FsToolsRoot(jail.path),
      refreshTree: false,
    );
    final etl = surface.etl;
    final scan = await etl.execute({'action': 'scan'});
    final scanMap = scan is String ? _decode(scan) : scan as Map;
    expect(scanMap!['ok'], isTrue, reason: '$scan');

    final program = surface.registry.tools.values
        .firstWhere((t) => t.name.value == 'meaning_program');
    // Warm the interpreter once (first-call allocations are not the read
    // wall — the warm tick + read path is the measured surface).
    await program.execute({
      'ops': [
        {'op': 'locate', 'query': 'area'},
      ],
    });
    final sw = Stopwatch()..start();
    final read = await program.execute({
      'ops': [
        {'op': 'locate', 'query': 'area'},
        {'op': 'read', 'budget': 256},
      ],
    });
    sw.stop();
    final readMap = read is String ? _decode(read) : read as Map;
    expect(readMap!['ok'], isTrue, reason: '$read');
    // The cursor law: locate SETS the cursor; read consumes cursor.first.
    expect(readMap['results'], isA<List>());
    // THE GATE: mechanical reads are sub-100 ms (2026-09-06 rows: 34–54 ms
    // warm). A miss here means the read path regressed into composition.
    expect(sw.elapsedMilliseconds, lessThan(100),
        reason: 'mechanical read wall ${sw.elapsedMilliseconds} ms — the '
            'mover path measured ~140,000 ms');
  });
}

Map<String, Object?>? _decode(String s) {
  final decoded = jsonDecode(s);
  return decoded is Map ? decoded.cast<String, Object?>() : null;
}
