// ignore_for_file: lines_longer_than_80_chars

/// FS-TIER GATE (ADR 0024 §1) — the map-graph covers EVERY file:
/// one scan pass indexes dir/file nodes for every file class (mechanical,
/// zero model tokens, same mtime refresh tick as dart); zoom cuts and
/// zoom-to-file (small files, budgeted) read; NO file text lives in the
/// tree; the escape-hatch write (`write_review`) refuses non-review
/// gateways, refuses Dart, and never lands without consent.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart'
    show CapturedWrite, FsToolsRoot, JailWriteGateway, WriteGateMode;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'package:xsoulspace_agentic_dart_meaning/xsoulspace_agentic_dart_meaning.dart';

/// ToolDef.encode serializes execute results to JSON strings — decode at
/// the boundary (the measured landmine).
Map<String, dynamic> _decoded(Object? raw) =>
    raw is String ? jsonDecode(raw) as Map<String, dynamic> : raw! as Map<String, dynamic>;

Future<Directory> _fixture() async {
  final dir = await Directory.systemTemp.createTemp('fs_tier_');
  File('${dir.path}/pubspec.yaml')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('name: fs_tier\nenvironment:\n  sdk: ^3.0.0\n');
  File('${dir.path}/lib/greet.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync("String greet(String name) => 'hello ' + name;\n");
  File('${dir.path}/docs/guide.md')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('# Guide\n\nSee [pubspec](../pubspec.yaml).\n');
  File('${dir.path}/assets/config.json')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('{"theme": "dark"}\n');
  File('${dir.path}/notes.txt').writeAsStringSync('plain text\n');
  File('${dir.path}/.dart_tool/junk.txt')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('skipped\n');
  File('${dir.path}/.DS_Store').writeAsStringSync('noise\n');
  return dir;
}

void main() {
  late Directory ws;
  late World world;
  late FsToolsRoot root;

  setUp(() async {
    ws = await _fixture();
    world = World()..addPlugin(AgentPlugin());
    world.upsertResource(ToolRegistryResource());
    root = FsToolsRoot(ws.path);
  });
  tearDown(() {
    try {
      ws.deleteSync(recursive: true);
    } on Object {
      // best effort
    }
  });

  test('scan indexes dir/file nodes for EVERY file class in one pass; '
      'dart files keep symbol sub-nodes; no file text in the tree', () async {
    final map = _decoded(
      await repoEtlTool(world, ws).execute({'action': 'scan'}),
    );
    expect(map['ok'], true);
    // fs tier: 5 files (pubspec, greet.dart, guide.md, config.json,
    // notes.txt) — .dart_tool junk and .DS_Store are skipped.
    expect(map['files'], 5);
    expect(map['dart_files'], 1);
    expect(map['dirs'], greaterThanOrEqualTo(3)); // root, lib, docs, assets
    expect(map['symbols'], greaterThanOrEqualTo(1)); // greet

    final index = world.getResource<MeaningIndex>();
    // Every file class is a first-class node with structural props only.
    final nonDart = ['docs_guide.md', 'assets_config.json', 'notes.txt'];
    for (final id in nonDart) {
      final entity = index.byId['f_$id'];
      expect(entity, isNotNull, reason: 'missing fs node f_$id');
      final props =
          meaningComponentOf<MeaningProps>(world, entity!)?.props ?? {};
      expect(props['class'], isIn(['md', 'json', 'other']));
      expect(props['bytes'], greaterThan(0));
      expect(props.containsKey('text'), isFalse,
          reason: 'NO file text lives in the tree — zoom cuts are the read');
    }
    // Dart files carry the fs props too (kind props from the same pass).
    final dartProps = meaningComponentOf<MeaningProps>(
      world,
      index.byId['f_lib_greet.dart']!,
    )?.props;
    expect(dartProps?['class'], 'dart');
    // Dir nodes exist and contain their children over the SAME relation.
    expect(index.byId['dir_root'], isNotNull);
    expect(index.byId['dir_lib'], isNotNull);
    expect(
      index.triples.contains(('dir_lib', 'contains', 'f_lib_greet.dart')),
      isTrue,
    );
    expect(
      index.triples.contains(('dir_docs', 'contains', 'f_docs_guide.md')),
      isTrue,
    );
  });

  test('zoom cuts find fs nodes by query; the map is the search', () async {
    await repoEtlTool(world, ws).execute({'action': 'scan'});
    final zoom = meaningZoomTool(world, spanReader: meaningSpanReader(root));
    final cut = _decoded(
      await zoom.execute({'query': 'Guide', 'zoom': 'local', 'budget': 1024}),
    );
    expect(cut['ok'], true);
    final nodes = (cut['cut'] as Map)['nodes'] as List;
    expect(
      nodes.any((n) => n['id'] == 'f_docs_guide.md'),
      isTrue,
      reason: 'the md file node is reachable through the same zoom verb',
    );
    // MAP HALF (md): heading sections exist as meaning sub-nodes.
    final outline = _decoded(await zoom.execute({
      'focusId': 'f_docs_guide.md',
      'zoom': 'local',
      'budget': 1024,
    }));
    final outlineNodes = (outline['cut'] as Map)['nodes'] as List;
    final section = outlineNodes.where((n) => n['kind'] == 'section').toList();
    expect(section, isNotEmpty,
        reason: 'md files are ETL’d into section anchors (text as meaning)');
    final secProps = (section.first as Map)['props'] as Map;
    expect(secProps['span_start'], isA<int>());
    expect(secProps['span_end'], isA<int>());
  });

  test('span cut: point zoom on a section/keypath anchor serves its text '
      '(budgeted, any file size); file nodes carry NO text', () async {
    await repoEtlTool(world, ws).execute({'action': 'scan'});
    final zoom = meaningZoomTool(world, spanReader: meaningSpanReader(root));

    // The section anchor: point zoom attaches its span text.
    final cut = _decoded(await zoom.execute({
      'focusId': 'f_docs_guide.md',
      'zoom': 'local',
    }));
    final sections = ((cut['cut'] as Map)['nodes'] as List)
        .where((n) => n['kind'] == 'section')
        .toList();
    expect(sections, isNotEmpty);
    final secId = (sections.first as Map)['id'] as String;
    final span = _decoded(await zoom.execute({'focusId': secId, 'zoom': 'point'}));
    expect((span['span'] as Map)['ok'], true);
    expect(((span['span'] as Map)['text'] as String), contains('Guide'));

    // yaml keypath anchor: its block span reads with the key visible.
    final yamlCut = _decoded(await zoom.execute({
      'focusId': 'f_pubspec.yaml',
      'zoom': 'local',
    }));
    final keys = ((yamlCut['cut'] as Map)['nodes'] as List)
        .where((n) => n['kind'] == 'key')
        .toList();
    expect(keys, isNotEmpty, reason: 'yaml is mapped into keypath anchors');
    final keyId = (keys.first as Map)['id'] as String;
    final keySpan = _decoded(await zoom.execute({
      'focusId': keyId,
      'zoom': 'point',
    }));
    expect((keySpan['span'] as Map)['ok'], true);
    expect(((keySpan['span'] as Map)['text'] as String), contains(':'));

    // A file node is NOT an anchor: no text leaves without a meaning span.
    final fileZoom = _decoded(await zoom.execute({
      'focusId': 'f_notes.txt',
      'zoom': 'point',
    }));
    expect(fileZoom.containsKey('span'), isFalse,
        reason: 'class other has no map — no text read, only node facts');

    // No reader wired: NAMED degradation, never silent.
    final bare = _decoded(await meaningZoomTool(world).execute({
      'focusId': secId,
      'zoom': 'point',
    }));
    expect((bare['span'] as Map)['error'], 'span_reader_unavailable');

    // A big span is CLAMPED to the view budget with the green-screen fact —
    // never refused by size (budget the VIEW, never the FILE).
    final big = StringBuffer('# Big\n\n');
    for (var i = 0; i < 900; i++) {
      big.writeln('paragraph line $i with enough words to fill budget');
    }
    File('${ws.path}/docs/big.md').writeAsStringSync(big.toString());
    await repoEtlTool(world, ws).execute({'action': 'refresh'});
    final bigCut = _decoded(await zoom.execute({
      'focusId': 'f_docs_big.md',
      'zoom': 'local',
    }));
    final bigSections = ((bigCut['cut'] as Map)['nodes'] as List)
        .where((n) => n['kind'] == 'section')
        .toList();
    final bigId = (bigSections.first as Map)['id'] as String;
    final bigSpan = _decoded(await zoom.execute({
      'focusId': bigId,
      'zoom': 'point',
      'budget': 16,
    }));
    final sp = bigSpan['span'] as Map;
    expect(sp['ok'], true);
    expect(sp['truncated'], true);
    expect((sp['text'] as String).length, 16 * 4);
    expect(sp['hint'], isNotEmpty);
  });

  test('refresh tick: new files are added, deleted files are dropped, '
      'props refresh on mtime change, changed maps rebuild', () async {
    final etl = repoEtlTool(world, ws);
    await etl.execute({'action': 'scan'});
    File('${ws.path}/added.md').writeAsStringSync('# added\n');
    File('${ws.path}/notes.txt').writeAsStringSync('rewritten text\n');
    final refresh = _decoded(await etl.execute({'action': 'refresh'}));
    expect(refresh['ok'], true);
    expect(refresh['fs_added'], 1);
    final index = world.getResource<MeaningIndex>();
    expect(index.byId['f_added.md'], isNotNull);
    expect(index.byId['f_notes.txt'], isNotNull);

    // A changed mapped file rebuilds its section anchors (stale map gone).
    File('${ws.path}/docs/guide.md')
        .writeAsStringSync('# Guide v2\n\nrewritten\n\n## Extra\n\nbody\n');
    await etl.execute({'action': 'refresh'});
    final index2 = world.getResource<MeaningIndex>();
    expect(index2.byId['sec_f_docs_guide.md_1'], isNotNull);
    expect(index2.byId['sec_f_docs_guide.md_2'], isNotNull);
    final props =
        meaningComponentOf<MeaningProps>(world, index2.byId['sec_f_docs_guide.md_2']!)?.props;
    expect(props?['level'], 2);

    File('${ws.path}/added.md').deleteSync();
    final refresh2 = _decoded(await etl.execute({'action': 'refresh'}));
    expect(refresh2['fs_dropped'], 1);
    expect(world.getResource<MeaningIndex>().byId['f_added.md'], isNull,
        reason: 'a dropped file must not stay in the map-graph');
  });

  test('write_review: refuses apply-mode gateways and dart paths; the '
      'review gateway with an approver lands, a reject never lands',
      () async {
    final root = FsToolsRoot(ws.path);

    // Deny-by-default is structural: no review mode, no write.
    final applyGateway =
        JailWriteGateway(root, mode: WriteGateMode.apply);
    final tool = writeReviewTool(root, applyGateway);
    final refused = _decoded(await tool.execute({
      'path': 'docs/new.md',
      'content': '# hi\n',
    }));
    expect(refused['ok'], false);
    expect(refused['error'], 'review_mode_required');
    expect(File('${ws.path}/docs/new.md').existsSync(), isFalse);

    // Review gateway: consent lands the write…
    final review = JailWriteGateway(
      root,
      mode: WriteGateMode.review,
      approver: (CapturedWrite w) async => true,
    );
    final allowed = _decoded(await writeReviewTool(root, review).execute({
      'path': 'docs/new.md',
      'content': '# hi\n',
    }));
    expect(allowed['ok'], true, reason: '${allowed['ack']}');
    expect(File('${ws.path}/docs/new.md').readAsStringSync(), '# hi\n');
    expect(review.appliedCount, 1);

    // …a reject NEVER lands…
    final denied = JailWriteGateway(
      root,
      mode: WriteGateMode.review,
      approver: (CapturedWrite w) async => false,
    );
    final rejected = _decoded(await writeReviewTool(root, denied).execute({
      'path': 'docs/other.md',
      'content': '# no\n',
    }));
    expect(rejected['ok'], false);
    expect((rejected['ack'] as String), startsWith('REJECTED'));
    expect(File('${ws.path}/docs/other.md').existsSync(), isFalse);
    expect(denied.rejectedCount, 1);

    // …and Dart NEVER routes through the escape hatch (code law).
    final dartTry = _decoded(await writeReviewTool(root, review).execute({
      'path': 'lib/greet.dart',
      'content': 'String greet(String name) => "bye";\n',
    }));
    expect(dartTry['ok'], false);
    expect(dartTry['error'], 'dart_not_via_escape_hatch');
    expect(File('${ws.path}/lib/greet.dart').readAsStringSync(),
        contains('hello'));
  });
}
