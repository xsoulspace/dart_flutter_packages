// ignore_for_file: lines_longer_than_80_chars

/// ADR 0034 — ONE edit verb, class-routed: the model edits an md section
/// and a yaml key through `edit_symbol` with `{action, symbolId, body}` —
/// never a path, never a format. The node's class routes the materializer
/// (splice + oracle + auto-revert); a wrong action for a class is a named
/// bounce listing THAT node's legal actions.
///
/// LLM-free e2e on a temp jail: real tree (repo_etl scan), real
/// materializers, real oracles.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart'
    show FsToolsRoot;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'package:xsoulspace_agentic_workspace/xsoulspace_agentic_workspace.dart';

Map<String, dynamic> _decoded(Object? raw) => raw is String
    ? jsonDecode(raw) as Map<String, dynamic>
    : raw! as Map<String, dynamic>;

const docRel = 'docs/guide.md';
const cfgRel = 'config.yaml';

const docOriginal = '''
# Guide

Welcome.

## Usage

Run the tool.
''';

const cfgOriginal = '''
name: demo
max_attempts: 3
server:
  port: 8080
''';

Future<Directory> _jail() async {
  final dir = await Directory.systemTemp.createTemp('edit_node_jail_');
  File('${dir.path}/pubspec.yaml')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('name: edit_node_jail\nenvironment:\n  sdk: ^3.0.0\n');
  File('${dir.path}/$docRel')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(docOriginal);
  File('${dir.path}/$cfgRel').writeAsStringSync(cfgOriginal);
  return dir;
}

World _world() {
  final world = World()..addPlugin(AgentPlugin());
  world.upsertResource(ToolRegistryResource());
  return world;
}

/// Finds the FIRST node id of [kind] whose node label contains [labelPart].
String _nodeId(World world, String kind, String labelPart) {
  final index = world.getResource<MeaningIndex>();
  for (final entry in index.byId.entries) {
    final node = meaningComponentOf<MeaningNode>(world, entry.value);
    if (node != null && node.kind == kind && node.label.contains(labelPart)) {
      return entry.key;
    }
  }
  fail('no $kind node matching "$labelPart" — scan the tree first');
}

void main() {
  late Directory jail;
  late World world;
  late FsToolsRoot root;
  late ToolDef edit;

  setUp(() async {
    jail = await _jail();
    world = _world();
    root = FsToolsRoot(jail.path);
    edit = editSymbolTool(world, jail);
    // The tree — mechanical, zero model tokens.
    await repoEtlTool(world, jail).execute({'action': 'scan'});
  });
  tearDown(() {
    try {
      jail.deleteSync(recursive: true);
    } on Object {
      // best effort
    }
  });

  test('an md section edits through the ONE verb — path comes from the '
      'node, splice is byte-precise', () async {
    final symbolId = _nodeId(world, 'section', 'Usage');
    final out = _decoded(
      await edit.execute({
        'action': 'replace_section',
        'symbolId': symbolId,
        'body': 'Run the tool with --serve.',
      }),
    );
    expect(out['ok'], isTrue, reason: '$out');
    final spliced = File('${jail.path}/$docRel').readAsStringSync();
    expect(spliced, contains('Run the tool with --serve.'));
    expect(spliced, contains('## Usage'), reason: 'heading preserved');
    expect(spliced, contains('# Guide'), reason: 'nothing reflows');
  });

  test('a yaml key edits through the ONE verb — keypath from the node',
      () async {
    final symbolId = _nodeId(world, 'key', 'max_attempts');
    final out = _decoded(
      await edit.execute({
        'action': 'replace_value',
        'symbolId': symbolId,
        'body': '5',
      }),
    );
    expect(out['ok'], isTrue, reason: '$out');
    expect(
      File('${jail.path}/$cfgRel').readAsStringSync(),
      contains('max_attempts: 5'),
    );
  });

  test('a wrong action for the class is a NAMED bounce listing the '
      'node\'s legal actions', () async {
    final symbolId = _nodeId(world, 'section', 'Usage');
    final out = _decoded(
      await edit.execute({
        'action': 'set_key',
        'symbolId': symbolId,
        'body': 'x',
      }),
    );
    expect(out['ok'], isFalse);
    expect(out['bounce'], isTrue);
    expect(
      '${out['hint']}',
      contains('replace_section'),
      reason: 'the bounce teaches the CLASS vocabulary, not the format',
    );
    // Nothing moved.
    expect(File('${jail.path}/$docRel').readAsStringSync(), docOriginal);
  });

  test('a dart action on a sec_ node bounces; the node id space is one',
      () async {
    final symbolId = _nodeId(world, 'key', 'max_attempts');
    final out = _decoded(
      await edit.execute({
        'action': 'replace_member_body',
        'symbolId': symbolId,
        'opChain': const [],
      }),
    );
    expect(out['ok'], isFalse);
    final teach = '${out['repair'] ?? out['hint']}';
    expect(
      teach,
      contains('set_key'),
      reason: 'a key node answers key actions, never dart actions — the '
          'bounce teaches the class vocabulary',
    );
  });


  test('CREATION: set_key with a literal keypath anchor creates a key '
      'that has no node — symbolId scopes the file', () async {
    final parentNode = _nodeId(world, 'key', 'server');
    final out = _decoded(
      await edit.execute({
        'action': 'set_key',
        'symbolId': parentNode,
        'anchor': 'server.feature_flags',
        'body': 'true',
      }),
    );
    expect(out['ok'], isTrue, reason: '$out');
    final text = File('${jail.path}/$cfgRel').readAsStringSync();
    expect(text, contains('feature_flags: true'));
    expect(text, contains('port: 8080'), reason: 'siblings untouched');
  });

  test('CREATION: insert_section through the router adds a new section '
      'after the anchor node (body carries the new heading)', () async {
    final symbolId = _nodeId(world, 'section', 'Usage');
    final out = _decoded(
      await edit.execute({
        'action': 'insert_section',
        'symbolId': symbolId,
        'body': '## Configuration\n\nFlags live here.',
      }),
    );
    expect(out['ok'], isTrue, reason: '\$out');
    final text = File('${jail.path}/$docRel').readAsStringSync();
    expect(text, contains('## Configuration'));
    expect(text, contains('Flags live here.'));
    expect(text.indexOf('## Usage'), lessThan(text.indexOf('## Configuration')),
        reason: 'inserted AFTER the anchor');
  });

  test('an unknown node id bounces with the locate/zoom repair hint',
      () async {
    final out = _decoded(
      await edit.execute({
        'action': 'replace_section',
        'symbolId': 'sec_does_not_exist',
        'body': 'x',
      }),
    );
    expect(out['ok'], isFalse);
    expect('${out['hint']}', contains('locate'));
  });
}
