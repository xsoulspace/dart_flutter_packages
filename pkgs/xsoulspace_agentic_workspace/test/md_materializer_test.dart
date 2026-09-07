// ignore_for_file: lines_longer_as_80_chars

/// MD MATERIALIZER GATE (ADR 0024 §2 — the md spec realized; PLAN §NOW P1
/// "Docs oracle for md"). LLM-free e2e on a temp jail with a real doc:
///
/// - scan → the md file maps to `section` anchors (the FIRST non-dart
///   class registered — the file node carries `edit_actions` (ADR 0034));
/// - zoom serves section anchors (point cut = budgeted span text);
/// - ONE decision's edit through the uniform verb (`edit_section` — the
///   model supplies {anchor, op, body-as-data}; the HOST splices);
/// - spliced bytes are byte-precise (heading preserved, nothing reflows);
/// - the named oracle (`zero_broken_links`) is GREEN after a good edit;
/// - a broken-link edit AUTO-REVERTS with the named failure class
///   (`broken_relative_link` / `broken_heading_anchor`);
/// - anchor-not-found / ambiguity bounces carry navigable hints — the
///   exact repair move;
/// - code fences are inert in map AND oracle (ADR 0019).
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart'
    show FsToolsRoot;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'package:xsoulspace_agentic_workspace/xsoulspace_agentic_workspace.dart';

/// ToolDef.encode serializes execute results to JSON strings — decode at
/// the boundary (the measured landmine).
Map<String, dynamic> _decoded(Object? raw) => raw is String
    ? jsonDecode(raw) as Map<String, dynamic>
    : raw! as Map<String, dynamic>;

const guideRel = 'docs/guide.md';

/// A real doc: five sections, in-doc + relative links (all resolvable),
/// a code fence containing a heading and a BROKEN link (inert — the doc
/// is oracle-green AS WRITTEN), and two same-labeled sections (ambiguity
/// is data, never a guess).
const guideOriginal = '''
# Guide

Welcome to the [project](../README.md).

## Usage

Run the tool. See the [config](config.md) for details, or [jump](#api).

```sh
# not a heading — fences are inert
see [fake](missing-file.md)
```

## API

The [API reference](./api.md) lists endpoints.

## Notes

First notes block.

## Notes

Second notes block.
''';

Future<Directory> _jail() async {
  final dir = await Directory.systemTemp.createTemp('md_mat_jail_');
  File('${dir.path}/pubspec.yaml')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('name: md_jail\nenvironment:\n  sdk: ^3.0.0\n');
  File('${dir.path}/README.md').writeAsStringSync('# md_jail\n\nThe readme.\n');
  File('${dir.path}/docs/guide.md')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(guideOriginal);
  File('${dir.path}/docs/api.md')
      .writeAsStringSync('# API\n\nEndpoints live here.\n');
  File('${dir.path}/docs/config.md')
      .writeAsStringSync('# Config\n\nKeys and values.\n');
  return dir;
}

World _world() {
  final world = World()..addPlugin(AgentPlugin());
  world.upsertResource(ToolRegistryResource());
  return world;
}

/// Scan + refresh through the ONE tick tool (mechanical, zero model
/// tokens); returns the tool for reuse by refresh assertions.
ToolDef _etl(World world, Directory jail) => repoEtlTool(world, jail);

Future<Map<String, dynamic>> _scan(World world, Directory jail) async =>
    _decoded(await _etl(world, jail).execute({'action': 'scan'}));

Future<Map<String, dynamic>> _refresh(World world, Directory jail) async =>
    _decoded(await _etl(world, jail).execute({'action': 'refresh'}));

ToolDef _editVerb(FsToolsRoot root) => editMdTool(root);

Future<Map<String, dynamic>> _edit(
  FsToolsRoot root,
  Map<String, dynamic> args,
) async =>
    _decoded(await _editVerb(root).execute(args));

void main() {
  late Directory jail;
  late World world;
  late FsToolsRoot root;

  setUp(() async {
    jail = await _jail();
    world = _world();
    root = FsToolsRoot(jail.path);
  });
  tearDown(() {
    try {
      jail.deleteSync(recursive: true);
    } on Object {
      // best effort
    }
  });

  test('the md binding is registered DATA; the tick maps md sections and '
      'stamps the edit verb on the file node', () async {
    // The binding — data + the realizations (ADR 0035 §1), not code in a
    // switch.
    final spec = materializerBindings['md'];
    expect(spec, isNotNull, reason: 'md is the FIRST registered non-dart '
        'materializer binding');
    expect(spec!.fileClass, 'md');
    expect(spec.spanCurrency, 'section');
    expect(spec.mapFormat, 'heading_tree');
    expect(spec.emitter, 'section_splice');
    expect(spec.oracle, 'zero_broken_links');
    expect(spec.anchors, 'heading_path');
    expect(spec.actions, ['replace_section', 'insert_section', 'append_to_section']);
    expect(specForRel(guideRel).fileClass, 'md');

    final scan = await _scan(world, jail);
    expect(scan['ok'], true);
    final index = world.getResource<MeaningIndex>();
    final fileEntity = index.byId['f_docs_guide.md']!;
    final props =
        meaningComponentOf<MeaningProps>(world, fileEntity)?.props ?? {};
    expect(props['class'], 'md');
    expect(props['has_map'], true);
    expect(props['edit_actions'], 'replace_section,insert_section,append_to_section',
        reason: 'the tick itself surfaces what the class can do');
    // Five section anchors over the SAME contains relation as code.
    const sectionIds = [
      'sec_f_docs_guide.md_1',
      'sec_f_docs_guide.md_2',
      'sec_f_docs_guide.md_3',
      'sec_f_docs_guide.md_4',
      'sec_f_docs_guide.md_5',
    ];
    for (final id in sectionIds) {
      expect(index.byId[id], isNotNull, reason: 'missing $id');
      expect(
        index.triples.contains(('f_docs_guide.md', 'contains', id)),
        isTrue,
      );
    }
    expect(
      meaningComponentOf<MeaningNode>(world, index.byId['sec_f_docs_guide.md_2']!)
          ?.label,
      'Usage',
    );
    // Fences are INERT (ADR 0019): the `#` line inside the fence is not a
    // section — five headings, not six.
    final sectionNodes = [
      for (final id in index.byId.keys) if (id.startsWith('sec_f_docs_guide.md_')) id,
    ];
    expect(sectionNodes.length, 5);
  });

  test('zoom serves section anchors: a point cut is the budgeted span '
      'text of ONE section — never the file', () async {
    await _scan(world, jail);
    final zoom =
        meaningZoomTool(world, spanReader: meaningSpanReader(root));
    final cut = _decoded(await zoom.execute({
      'focusId': 'sec_f_docs_guide.md_2',
      'zoom': 'point',
      'budget': 1024,
    }));
    expect(cut['ok'], true);
    final span = cut['span'] as Map;
    expect(span['ok'], true);
    expect(span['text'], contains('Run the tool. See the [config]'));
    expect(span['text'], isNot(contains('# Guide')),
        reason: 'ONE section span, not the file');
  });

  test('one decision: replace_section through the verb — byte-precise '
      'splice, heading preserved, oracle green, tree re-derives',
      () async {
    await _scan(world, jail);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final body = 'Run the tool.\n\nUpdated prose keeps the '
        '[index](../README.md) and [jump](#api) links.\n';
    final r = await _edit(root, {
      'path': guideRel,
      'op': 'replace_section',
      'anchor': 'Usage',
      'body': body,
    });
    expect(r['ok'], true, reason: '$r');
    expect(r['reverted'], false);
    expect(r['failureClass'], isNull,
        reason: 'a clean move names no failure');

    // BYTE-PRECISE: the heading line survives byte-for-byte, the content
    // lines between heading anchors are replaced, nothing else reflows.
    final bytes = File('${jail.path}/$guideRel').readAsStringSync();
    final headingIdx = guideOriginal.indexOf('## Usage');
    final prefix = guideOriginal.substring(0, headingIdx + '## Usage\n'.length);
    final nextIdx = guideOriginal.indexOf('## API');
    final suffix = guideOriginal.substring(nextIdx);
    expect(bytes, prefix + body + suffix);

    // The tree re-derives on the tick: the same section anchor now serves
    // the NEW text (map rebuilt through the registered md spec).
    final refresh = await _refresh(world, jail);
    expect(refresh['ok'], true, reason: '$refresh');
    final zoom =
        meaningZoomTool(world, spanReader: meaningSpanReader(root));
    final cut = _decoded(await zoom.execute({
      'focusId': 'sec_f_docs_guide.md_2',
      'zoom': 'point',
      'budget': 1024,
    }));
    expect((cut['span'] as Map)['text'], contains('Updated prose'));
  });

  test('zoom staleness: WITHOUT a scan/refresh, a point zoom after a '
      'materializer edit serves the POST-edit span (refreshed: true)',
      () async {
    await _scan(world, jail);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final body = 'Zoom-stale prose served fresh from disk.\n';
    final r = await _edit(root, {
      'path': guideRel,
      'op': 'replace_section',
      'anchor': 'Usage',
      'body': body,
    });
    expect(r['ok'], true, reason: '$r');
    // NO refresh tick — the POINT zoom itself re-stats the focus node's
    // file (one stat + one bounded re-read) and re-derives that ONE node
    // before serving the cut (PLAN §NOW "Zoom staleness").
    final zoom = meaningZoomTool(world, spanReader: meaningSpanReader(root));
    final cut = _decoded(await zoom.execute({
      'focusId': 'sec_f_docs_guide.md_2',
      'zoom': 'point',
      'budget': 1024,
    }));
    expect(cut['refreshed'], true, reason: '$cut');
    expect(cut['refreshed_path'], guideRel);
    expect((cut['span'] as Map)['text'], contains('Zoom-stale prose'),
        reason: 'a just-edited file must never serve pre-edit text');
  });

  test('a broken relative link AUTO-REVERTS with the named failure class '
      '(zero_broken_links)', () async {
    await _scan(world, jail);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final r = await _edit(root, {
      'path': guideRel,
      'op': 'replace_section',
      'anchor': 'API',
      'body': 'The [bad](./missing.md) reference.\n',
    });
    expect(r['ok'], false, reason: '$r');
    expect(r['reverted'], true, reason: 'a broken-link edit never lands');
    expect(r['failureClass'], 'broken_relative_link');
    expect((r['problems'] as List).first, contains('./missing.md'));
    // Bytes restored — the doc is exactly what it was.
    expect(File('${jail.path}/$guideRel').readAsStringSync(), guideOriginal);
  });

  test('a broken heading anchor AUTO-REVERTS with the named failure class',
      () async {
    await _scan(world, jail);
    final r = await _edit(root, {
      'path': guideRel,
      'op': 'replace_section',
      'anchor': 'API',
      'body': 'Jump to [nothing](#no-such-anchor) here.\n',
    });
    expect(r['ok'], false, reason: '$r');
    expect(r['reverted'], true);
    expect(r['failureClass'], 'broken_heading_anchor');
    expect(File('${jail.path}/$guideRel').readAsStringSync(), guideOriginal);
  });

  test('insert_section lands a NEW section between heading anchors; '
      'append_to_section extends the anchored section (node-id anchor)',
      () async {
    await _scan(world, jail);
    final r = await _edit(root, {
      'path': guideRel,
      'op': 'insert_section',
      'anchor': 'API',
      'body': '## Changelog\n\n- 2026-09-06: md materializer landed.\n',
    });
    expect(r['ok'], true, reason: '$r');
    final bytes = File('${jail.path}/$guideRel').readAsStringSync();
    final apiIdx = guideOriginal.indexOf('## Notes');
    final expected = guideOriginal.substring(0, apiIdx) +
        '## Changelog\n\n- 2026-09-06: md materializer landed.\n' +
        guideOriginal.substring(apiIdx);
    expect(bytes, expected);

    // The insert SHIFTS the ordinals — the mechanical contract is fresh
    // ids from the refreshed tree, so the model re-zooms (never guesses).
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await _refresh(world, jail);
    final index = world.getResource<MeaningIndex>();
    final notesIds = [
      for (final entry in index.byId.entries)
        if (entry.key.startsWith('sec_f_docs_guide.md_') &&
            meaningComponentOf<MeaningNode>(world, entry.value)?.label ==
                'Notes')
          entry.key,
    ]..sort();
    expect(notesIds.length, 2);
    final secondNotesId = notesIds.last;

    // Node-id anchor (from the refreshed tree) resolves mechanically —
    // used to append to the SECOND 'Notes' (a bare label would bounce).
    final r2 = await _edit(root, {
      'path': guideRel,
      'op': 'append_to_section',
      'anchor': secondNotesId,
      'body': '- appended note.\n',
    });
    expect(r2['ok'], true, reason: '$r2');
    expect(File('${jail.path}/$guideRel').readAsStringSync(),
        '$expected- appended note.\n');

    // The tick maps the new section (first non-dart class through the
    // mtime tick).
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await _refresh(world, jail);
    final labels = [
      for (final entry in index.byId.entries)
        if (entry.key.startsWith('sec_f_docs_guide.md_'))
          meaningComponentOf<MeaningNode>(world, entry.value)?.label,
    ];
    expect(labels, contains('Changelog'));
    expect(labels.where((l) => l == 'Notes').length, 2);
  });

  test('anchor-not-found and ambiguity bounce as named data with the '
      'exact repair move (never a guess)', () async {
    await _scan(world, jail);
    final miss = await _edit(root, {
      'path': guideRel,
      'op': 'replace_section',
      'anchor': 'Nonexistent',
      'body': 'x\n',
    });
    expect(miss['ok'], false, reason: '$miss');
    expect(miss['failureClass'], 'anchor_not_found');
    expect(miss['bounce'], true);
    expect(miss['repair'], contains('zoom the file node'));
    final hints = (miss['hints'] as List).cast<String>().join('\n');
    expect(hints, contains('Usage'));
    expect(hints, contains('sec_f_docs_guide.md_2'));
    // Nothing was touched.
    expect(File('${jail.path}/$guideRel').readAsStringSync(), guideOriginal);

    final ambiguous = await _edit(root, {
      'path': guideRel,
      'op': 'replace_section',
      'anchor': 'Notes',
      'body': 'x\n',
    });
    expect(ambiguous['ok'], false, reason: '$ambiguous');
    expect(ambiguous['failureClass'], 'ambiguous_anchor');
    final ahints = (ambiguous['hints'] as List).cast<String>();
    expect(ahints, contains('sec_f_docs_guide.md_4: Notes'));
    expect(ahints, contains('sec_f_docs_guide.md_5: Notes'));
    expect(ambiguous['repair'], contains('NODE ID'));
  });

  test('the mechanical fences: wrong class, wrong shape, over-budget body, '
      'escaping path — all bounce BEFORE any byte', () async {
    final wrongClass = await _edit(root, {
      'path': 'pubspec.yaml',
      'op': 'replace_section',
      'anchor': 'name',
      'body': 'x\n',
    });
    expect(wrongClass['failureClass'], 'not_md_class', reason: '$wrongClass');

    final badInsert = await _edit(root, {
      'path': guideRel,
      'op': 'insert_section',
      'anchor': 'Usage',
      'body': 'plain prose without a heading',
    });
    expect(badInsert['failureClass'], 'insert_needs_heading',
        reason: '$badInsert');

    final overBudget = await _edit(root, {
      'path': guideRel,
      'op': 'replace_section',
      'anchor': 'Usage',
      'body': 'x' * (MdMaterializer.maxMdBodyChars + 1),
    });
    expect(overBudget['failureClass'], 'body_over_budget',
        reason: '$overBudget');

    final escape = await _edit(root, {
      'path': '../outside.md',
      'op': 'replace_section',
      'anchor': 'Usage',
      'body': 'x\n',
    });
    expect(escape['failureClass'], 'path_escapes_workspace',
        reason: '$escape');

    final unknownOp = await _edit(root, {
      'path': guideRel,
      'op': 'delete_file',
      'anchor': 'Usage',
      'body': 'x\n',
    });
    expect(unknownOp['failureClass'], 'unknown_op', reason: '$unknownOp');

    expect(File('${jail.path}/$guideRel').readAsStringSync(), guideOriginal);
  });
}
