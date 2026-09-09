// ignore_for_file: lines_longer_than_80_chars

/// FILE-CREATION BINDING GATE (build order item 7 — file creation is a
/// BINDING property, never a raw file_bootstrap verb): whole-FILE
/// creation through the ONE edit verb, addressed at a DIR node, routed
/// by the binding's DECLARED `fileCreation` capability.
///
/// LLM-free e2e on a temp jail — real tree (repo_etl scan), the ONE verb
/// (`edit_symbol`), real materializers, real oracles:
///
/// - the binding declares WHETHER the class supports creation + the
///   creation anchor currency (`new_file_path` / `new_file_path#keypath`)
///   — data in MaterializerBinding, never a per-format verb;
/// - a heading class creates a file with its initial heading structure
///   (heading-bearing body — the same anchor currency as its sections);
/// - a keypath class creates the EMPTY MAP DOCUMENT + the first key at
///   the anchor keypath;
/// - byte-precision: create → map → re-emit == created content (the
///   map⇄emitter agreement law) — the created bytes ARE the emitter's
///   exact output and the map's spans tile them exactly;
/// - tree reconcile: after creation the file node + content sub-nodes
///   appear in the map-graph through the existing buildFsTier path;
/// - a binding WITHOUT the capability bounces NAMING the binding and the
///   field to register — never a silent fallback to a raw write; no
///   jail escape; creation never overwrites (revert to absence).
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
const settingsRel = 'config/settings.yaml';

const guideOriginal = '''
# Guide

Welcome.
''';

const settingsOriginal = '''
service:
  port: 8080
''';

Future<Directory> _jail() async {
  final dir = await Directory.systemTemp.createTemp('file_creation_jail_');
  File('${dir.path}/pubspec.yaml')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('name: file_creation_jail\nenvironment:\n  sdk: ^3.0.0\n');
  // Empty dirs matter: a dir NODE is the creation address, so the jail
  // has indexed directories with no files yet.
  Directory('${dir.path}/docs').createSync();
  Directory('${dir.path}/config').createSync();
  File('${dir.path}/$guideRel').writeAsStringSync(guideOriginal);
  File('${dir.path}/$settingsRel').writeAsStringSync(settingsOriginal);
  return dir;
}

World _world() {
  final world = World()..addPlugin(AgentPlugin());
  world.upsertResource(ToolRegistryResource());
  return world;
}

/// Finds the FIRST node id of [kind] whose node label contains
/// [labelPart] (exact label for dir/file nodes).
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

  group('creation capability is binding data', () {
    test('the capability is DECLARED data: action + anchor currency per '
        'binding; code families declare none', () {
      final mdB = materializerBindings['md']!;
      expect(mdB.fileCreation, isNotNull);
      expect(mdB.fileCreation!.action, fileCreationAction);
      expect(mdB.fileCreation!.anchorCurrency, 'new_file_path');
      for (final fc in ['yaml', 'json']) {
        final b = materializerBindings[fc]!;
        expect(b.fileCreation, isNotNull, reason: fc);
        expect(b.fileCreation!.action, fileCreationAction);
        expect(b.fileCreation!.anchorCurrency, 'new_file_path#keypath');
        // The capability must NOT jam into the section/key action union —
        // the existing gates pin that union byte-exact.
        expect(b.actions.contains(fileCreationAction), isFalse, reason: fc);
      }
      // Code families: creation routes through the trusted-author tier —
      // their bindings declare NO creation capability.
      expect(materializerBindings['ts']!.fileCreation, isNull);
      expect(materializerBindings['cs']!.fileCreation, isNull);
    });

    test('registry linter: creation without a map is a NAMED registration '
        'error (creation promises the file node + content sub-nodes)', () {
      final errors = validateMaterializerBindings([
        MaterializerBinding(
          fileClass: 'md',
          extensions: const {'.md', '.mdx'},
          actions: const ['replace_section'],
          materializer: (r) => const {'ok': true},
          oracle: 'zero_broken_links',
          anchors: 'heading_path',
          spanCurrency: 'section',
          mapFormat: 'heading_tree',
          emitter: 'section_splice',
          fileCreation: const FileCreation(
            action: fileCreationAction,
            anchorCurrency: 'new_file_path',
          ),
          // mapParser deliberately omitted → the named error.
        ),
      ]);
      expect(errors, hasLength(1), reason: '$errors');
      expect(errors.single, startsWith('creation_without_map'));
    });

    test('registry linter: a creation capability without its declared '
        'action/currency is a NAMED registration error', () {
      final errors = validateMaterializerBindings([
        MaterializerBinding(
          fileClass: 'md',
          extensions: const {'.md', '.mdx'},
          actions: const ['replace_section'],
          materializer: (r) => const {'ok': true},
          oracle: 'zero_broken_links',
          anchors: 'heading_path',
          spanCurrency: 'section',
          mapFormat: 'heading_tree',
          emitter: 'section_splice',
          mapParser: mdMapParser,
          subNodePrefix: 'sec_',
          fileCreation: const FileCreation(action: '', anchorCurrency: ''),
        ),
      ]);
      expect(errors, hasLength(1), reason: '$errors');
      expect(errors.single, startsWith('creation_declaration_incomplete'));
    });

    test('the REAL registry validates clean with the creation '
        'capabilities registered', () {
      expect(
        validateMaterializerBindings(materializerBindings.values.toList()),
        isEmpty,
      );
      expect(
          materializerRegistry.bindingFor('md')!.fileCreation, isNotNull);
    });
  });

  group('heading-class creation through the ONE verb', () {
    test('create_document addresses the DIR node; the file node + section '
        'sub-nodes project from the binding (tree reconcile)', () async {
      final dirId = _nodeId(world, 'dir', 'docs');
      final body = const ['# Setup\n\nRun the bootstrap.\n'].single;
      final out = _decoded(await edit.execute({
        'action': fileCreationAction,
        'symbolId': dirId,
        'anchor': 'docs/setup.md',
        'body': body,
      }));
      expect(out['ok'], isTrue, reason: '$out');
      expect(out['created'], isTrue, reason: '$out');
      // BYTE-PRECISE: the file is the body, exactly (already
      // newline-terminated — the emitter adds nothing).
      final created = File('${jail.path}/docs/setup.md').readAsStringSync();
      expect(created, body);
      // TREE RECONCILE: the file node + content sub-nodes appeared in the
      // map-graph (the router ran the existing buildFsTier path).
      expect(out['file_node'], 'f_docs_setup.md');
      final index = world.getResource<MeaningIndex>();
      final fileEntity = index.byId['f_docs_setup.md'];
      expect(fileEntity, isNotNull, reason: 'the file node must exist');
      final props =
          meaningComponentOf<MeaningProps>(world, fileEntity!)?.props ?? {};
      expect(props['class'], 'md');
      expect(props['has_map'], isTrue);
      expect(props['edit_actions'],
          'replace_section,insert_section,append_to_section',
          reason: 'the fs-stamped union stays the edit actions; creation '
              'is the declared capability, not a jammed action');
      expect(
        index.triples.contains(('f_docs_setup.md', 'contains',
            'sec_f_docs_setup.md_1')),
        isTrue,
        reason: 'the section sub-node contains under the file node',
      );
      final secProps = meaningComponentOf<MeaningProps>(
        world,
        index.byId['sec_f_docs_setup.md_1']!,
      )?.props;
      expect(secProps?['span_start'], 0);
      expect(secProps?['span_end'], created.length);
    });

    test('BYTE-PRECISION ROUND TRIP: create → map → re-emit == created '
        'content (the map⇄emitter agreement law)', () async {
      final dirId = _nodeId(world, 'dir', 'docs');
      final out = _decoded(await edit.execute({
        'action': fileCreationAction,
        'symbolId': dirId,
        'anchor': 'docs/manual.md',
        'body': '# Manual\n\nIntro prose.\n\n## Steps\n\nOne, two.\n',
      }));
      expect(out['ok'], isTrue, reason: '$out');
      final created = File('${jail.path}/docs/manual.md').readAsStringSync();
      // MAP: the ONE heading parser (the same parser the emitter anchors
      // with) parses the created bytes…
      final sections = parseMdSections(created);
      expect(sections, hasLength(2));
      // …and the map's spans RE-EMIT the file exactly: the sections tile
      // the document from the first heading to EOF, so slicing the spans
      // out reproduces the created content byte-for-byte.
      expect(sections.first.start, 0, reason: 'heading-initial document');
      expect(sections.last.end, created.length);
      final reemitted = sections
          .map((s) => created.substring(s.start, s.end))
          .join();
      expect(reemitted, created);
      // TREE agreement: the stamped sub-node spans equal the fresh parse
      // (one parser serves the zoom anchors AND the splice anchors).
      final index = world.getResource<MeaningIndex>();
      final stamped = [
        for (var i = 1; i <= 2; i++)
          meaningComponentOf<MeaningProps>(
            world,
            index.byId['sec_f_docs_manual.md_$i']!,
          )!.props,
      ];
      expect(stamped[0]['span_start'], sections[0].start);
      expect(stamped[0]['span_end'], sections[0].end);
      expect(stamped[1]['span_start'], sections[1].start);
      expect(stamped[1]['span_end'], sections[1].end);
    });

    test('a heading-less body bounces NAMED before any byte', () async {
      final dirId = _nodeId(world, 'dir', 'docs');
      final out = _decoded(await edit.execute({
        'action': fileCreationAction,
        'symbolId': dirId,
        'anchor': 'docs/prose.md',
        'body': 'plain prose without a heading',
      }));
      expect(out['ok'], isFalse);
      expect(out['failureClass'], 'create_needs_heading');
      expect(File('${jail.path}/docs/prose.md').existsSync(), isFalse,
          reason: 'bounces never touch bytes');
    });

    test('a broken link in the created doc AUTO-REVERTS TO ABSENCE (the '
        'file is removed, never half-landed)', () async {
      final dirId = _nodeId(world, 'dir', 'docs');
      final out = _decoded(await edit.execute({
        'action': fileCreationAction,
        'symbolId': dirId,
        'anchor': 'docs/linked.md',
        'body': '# Linked\n\nSee [missing](nope.md).\n',
      }));
      expect(out['ok'], isFalse, reason: '$out');
      expect(out['reverted'], isTrue);
      expect(out['failureClass'], 'broken_relative_link');
      expect(File('${jail.path}/docs/linked.md').existsSync(), isFalse,
          reason: 'a violating creation reverts to absence');
    });
  });

  group('keypath-class creation through the ONE verb', () {
    test('yaml: the empty map document + the first key at the anchor '
        'keypath; tree reconciles file node + key sub-nodes', () async {
      final dirId = _nodeId(world, 'dir', 'config');
      final out = _decoded(await edit.execute({
        'action': fileCreationAction,
        'symbolId': dirId,
        'anchor': 'config/database.yaml#credentials.host',
        'body': 'localhost',
      }));
      expect(out['ok'], isTrue, reason: '$out');
      expect(out['created'], isTrue);
      expect(out['file_node'], 'f_config_database.yaml');
      final created =
          File('${jail.path}/config/database.yaml').readAsStringSync();
      expect(created, 'credentials:\n  host: localhost\n');
      // The semantic map is EXACTLY the intended first document.
      expect(
        keypathParse(created, isJson: false),
        {
          'credentials': {'host': 'localhost'},
        },
      );
      // TREE RECONCILE: file node + key sub-nodes (binding-declared
      // prefix) are in the map-graph under the dir node.
      final index = world.getResource<MeaningIndex>();
      final keyIds = [
        for (final id in index.byId.keys)
          if (id.startsWith('key_f_config_database.yaml')) id,
      ]..sort();
      expect(keyIds, hasLength(2), reason: '$keyIds');
      expect(
        index.triples.contains(('f_config_database.yaml', 'contains',
            'key_f_config_database.yaml_credentials_host')),
        isTrue,
      );
      // The tick is idempotent over the created file (no dupes, no
      // drops — the same reconcile path the refresh runs).
      final refresh =
          _decoded(await repoEtlTool(world, jail).execute({'action': 'refresh'}));
      expect(refresh['ok'], isTrue, reason: '$refresh');
      final keyIdsAfter = [
        for (final id in index.byId.keys)
          if (id.startsWith('key_f_config_database.yaml')) id,
      ]..sort();
      expect(keyIdsAfter, keyIds);
    });

    test('json: the empty map document + the first key at the anchor '
        'keypath (nested render, oracle green)', () async {
      final dirId = _nodeId(world, 'dir', 'config');
      final out = _decoded(await edit.execute({
        'action': fileCreationAction,
        'symbolId': dirId,
        'anchor': 'config/features.json#server.port',
        'body': '8080',
      }));
      expect(out['ok'], isTrue, reason: '$out');
      final created =
          File('${jail.path}/config/features.json').readAsStringSync();
      expect(created, '{\n  "server": {\n    "port": 8080\n  }\n}\n');
      expect(
        keypathParse(created, isJson: true),
        {
          'server': {'port': 8080},
        },
      );
    });

    test('no keypath → the EMPTY map document (json {} / empty yaml doc)',
        () async {
      final dirId = _nodeId(world, 'dir', 'config');
      final jsonOut = _decoded(await edit.execute({
        'action': fileCreationAction,
        'symbolId': dirId,
        'anchor': 'config/empty.json',
        'body': '',
      }));
      expect(jsonOut['ok'], isTrue, reason: '$jsonOut');
      expect(File('${jail.path}/config/empty.json').readAsStringSync(),
          '{}\n');
      final yamlOut = _decoded(await edit.execute({
        'action': fileCreationAction,
        'symbolId': dirId,
        'anchor': 'config/empty.yaml',
        'body': '',
      }));
      expect(yamlOut['ok'], isTrue, reason: '$yamlOut');
      expect(File('${jail.path}/config/empty.yaml').readAsStringSync(), '');
      expect(keypathParse('', isJson: false), isNull,
          reason: 'an empty yaml document parses to the empty document');
    });

    test('BYTE-PRECISION ROUND TRIP: create → map → re-emit == created '
        'content for BOTH keypath classes (a value re-spliced through '
        "the map's own anchor reproduces the created bytes)", () async {
      final dirId = _nodeId(world, 'dir', 'config');
      final yamlCreate = _decoded(await edit.execute({
        'action': fileCreationAction,
        'symbolId': dirId,
        'anchor': 'config/database.yaml#credentials.host',
        'body': 'localhost',
      }));
      expect(yamlCreate['ok'], isTrue, reason: '$yamlCreate');
      final yamlBytes =
          File('${jail.path}/config/database.yaml').readAsStringSync();
      // MAP: the ONE keypath parser parses the created bytes…
      final entries = parseKeypathTree(yamlBytes, isJson: false);
      expect(entries.map((e) => e.keypath),
          ['credentials', 'credentials.host']);
      final host = entries.lastWhere((e) => e.keypath == 'credentials.host');
      // The v1 block-span behavior (the SAME parser the tree stamps): a
      // keypath entry's span extends to the file end when nothing closes
      // it — the slice carries the trailing newline.
      expect(
        yamlBytes.substring(host.start, host.end),
        '  host: localhost\n',
      );
      // …RE-EMIT: the same materializer splices through the map's own
      // anchor — value away and value back — and the final bytes equal
      // the created content EXACTLY (the emitter re-derives the created
      // bytes through the map; a same-value splice is honestly 0 changes
      // and bounces, so the round trip is away-and-back).
      final yamlAway = _decoded(
        await editKeyTool(root).execute({
          'path': 'config/database.yaml',
          'op': 'replace_value',
          'anchor': 'credentials.host',
          'body': 'db.internal.lan',
        }),
      );
      expect(yamlAway['ok'], isTrue, reason: '$yamlAway');
      final yamlBack = _decoded(
        await editKeyTool(root).execute({
          'path': 'config/database.yaml',
          'op': 'replace_value',
          'anchor': 'credentials.host',
          'body': 'localhost',
        }),
      );
      expect(yamlBack['ok'], isTrue, reason: '$yamlBack');
      expect(File('${jail.path}/config/database.yaml').readAsStringSync(),
          yamlBytes);

      final jsonCreate = _decoded(await edit.execute({
        'action': fileCreationAction,
        'symbolId': dirId,
        'anchor': 'config/features.json#server.port',
        'body': '8080',
      }));
      expect(jsonCreate['ok'], isTrue, reason: '$jsonCreate');
      final jsonBytes =
          File('${jail.path}/config/features.json').readAsStringSync();
      final jsonEntries = parseKeypathTree(jsonBytes, isJson: true);
      expect(jsonEntries.map((e) => e.keypath), ['server', 'server.port']);
      final port = jsonEntries.lastWhere((e) => e.keypath == 'server.port');
      expect(jsonBytes.substring(port.start, port.end), '    "port": 8080');
      final jsonAway = _decoded(
        await editKeyTool(root).execute({
          'path': 'config/features.json',
          'op': 'replace_value',
          'anchor': 'server.port',
          'body': '9090',
        }),
      );
      expect(jsonAway['ok'], isTrue, reason: '$jsonAway');
      final jsonBack = _decoded(
        await editKeyTool(root).execute({
          'path': 'config/features.json',
          'op': 'replace_value',
          'anchor': 'server.port',
          'body': '8080',
        }),
      );
      expect(jsonBack['ok'], isTrue, reason: '$jsonBack');
      expect(File('${jail.path}/config/features.json').readAsStringSync(),
          jsonBytes);
    });

    test('a bracket/foreign keypath shape bounces NAMED (not creation '
        'currency — create, then the key actions)', () async {
      final dirId = _nodeId(world, 'dir', 'config');
      final out = _decoded(await edit.execute({
        'action': fileCreationAction,
        'symbolId': dirId,
        'anchor': 'config/lists.yaml#items[0]',
        'body': 'x',
      }));
      expect(out['ok'], isFalse);
      expect(out['failureClass'], 'invalid_anchor');
      expect(File('${jail.path}/config/lists.yaml').existsSync(), isFalse);
    });
  });

  group('the honesty law — named bounces, never a raw-write fallback', () {
    test('a binding WITHOUT the creation capability bounces NAMING the '
        'binding and the field to register (code family → trusted-author '
        'tier)', () async {
      final dirId = _nodeId(world, 'dir', '/');
      final out = _decoded(await edit.execute({
        'action': fileCreationAction,
        'symbolId': dirId,
        'anchor': 'tool.ts',
        'body': 'export const x = 1;',
      }));
      expect(out['ok'], isFalse);
      expect(out['bounce'], isTrue);
      expect('${out['error']}', contains('"ts"'),
          reason: 'the bounce names WHICH binding lacks the capability');
      expect('${out['hint']}', contains('fileCreation'),
          reason: 'the bounce names WHICH field to register');
      expect('${out['hint']}', contains(fileCreationAction));
      expect(File('${jail.path}/tool.ts').existsSync(), isFalse,
          reason: 'never a silent raw-write fallback');
    });

    test('an UNREGISTERED class bounces NAMED (register spec + binding — '
        'no raw write)', () async {
      final dirId = _nodeId(world, 'dir', '/');
      final out = _decoded(await edit.execute({
        'action': fileCreationAction,
        'symbolId': dirId,
        'anchor': 'NOTES.txt',
        'body': 'x',
      }));
      expect(out['ok'], isFalse);
      expect(out['bounce'], isTrue);
      expect('${out['error']}', contains('"other"'));
      expect('${out['hint']}', contains('MaterializerBinding'));
      expect(File('${jail.path}/NOTES.txt').existsSync(), isFalse);
    });

    test('creation never overwrites: an existing file bounces (edit it '
        'through its class actions)', () async {
      final dirId = _nodeId(world, 'dir', 'docs');
      final out = _decoded(await edit.execute({
        'action': fileCreationAction,
        'symbolId': dirId,
        'anchor': 'docs/guide.md',
        'body': '# Overwrite?\n',
      }));
      expect(out['ok'], isFalse);
      expect(out['bounce'], isTrue);
      expect('${out['error']}', contains('already exists'));
      expect(File('${jail.path}/$guideRel').readAsStringSync(),
          guideOriginal, reason: 'bounces never touch bytes');
    });

    test('a jail escape bounces (the path projects from the addressed dir '
        'node — never a model-named absolute path)', () async {
      final dirId = _nodeId(world, 'dir', '/');
      final out = _decoded(await edit.execute({
        'action': fileCreationAction,
        'symbolId': dirId,
        'anchor': '../evil.md',
        'body': '# nope\n',
      }));
      expect(out['ok'], isFalse);
      expect(out['bounce'], isTrue);
      expect('${out['error']}', contains('escapes the workspace jail'));
      expect(
          File('${jail.parent.path}/evil.md').existsSync(), isFalse);
    });

    test('the dir node scopes the anchor: a mismatch bounces NAMED', () async {
      final dirId = _nodeId(world, 'dir', 'docs');
      final out = _decoded(await edit.execute({
        'action': fileCreationAction,
        'symbolId': dirId,
        'anchor': 'config/other.yaml#k.v',
        'body': '1',
      }));
      expect(out['ok'], isFalse);
      expect(out['bounce'], isTrue);
      expect('${out['error']}', contains('scopes'));
      expect(File('${jail.path}/config/other.yaml').existsSync(), isFalse);
    });

    test('creation addresses the DIR node: a file/section node bounces '
        'with the dir repair', () async {
      final secId = _nodeId(world, 'section', 'Guide');
      final out = _decoded(await edit.execute({
        'action': fileCreationAction,
        'symbolId': secId,
        'anchor': 'docs/sibling.md',
        'body': '# Sibling\n',
      }));
      expect(out['ok'], isFalse);
      expect(out['bounce'], isTrue);
      expect('${out['error']}', contains('DIR node'));
      expect(File('${jail.path}/docs/sibling.md').existsSync(), isFalse);
    });

    test('a dir node is not editable: a non-creation action on a dir '
        'bounces with the creation repair (mechanism-first)', () async {
      final dirId = _nodeId(world, 'dir', 'docs');
      final out = _decoded(await edit.execute({
        'action': 'replace_section',
        'symbolId': dirId,
        'body': 'x',
      }));
      expect(out['ok'], isFalse);
      expect(out['bounce'], isTrue);
      expect('${out['hint']}', contains(fileCreationAction),
          reason: 'the bounce teaches the creation move');
    });

    test('a missing anchor bounces (the new file path IS the creation '
        'anchor)', () async {
      final dirId = _nodeId(world, 'dir', '/');
      final out = _decoded(await edit.execute({
        'action': fileCreationAction,
        'symbolId': dirId,
      }));
      expect(out['ok'], isFalse);
      expect(out['bounce'], isTrue);
      expect('${out['error']}', contains('missing creation anchor'));
    });
  });
}
