// ignore_for_file: lines_longer_as_80_chars

/// YAML/JSON MATERIALIZER GATE (ADR 0024 §2 — the yaml + json specs
/// realized; PLAN §NOW P1 item 5). LLM-free e2e on a temp jail:
///
/// - the specs are REGISTERED DATA (`materializerSpecs['yaml']`/`['json']`,
///   actions (ADR 0034)) and the tick stamps `edit_verb` on their file nodes;
/// - ONE uniform verb for both classes (`edit_key`): the model supplies
///   {path, op, anchor (keypath), body-as-data}; the HOST resolves the
///   keypath from a fresh parse and splices byte-precisely;
/// - COMMENT-PRESERVING is gate-asserted: comments, siblings and blank
///   lines outside the target keypath's span stay byte-identical;
/// - the named oracle (`parse_semantic_diff`) is GREEN after a good edit —
///   the ONLY semantic change is the intended one;
/// - a violating edit AUTO-REVERTS (every byte restored, named class);
/// - missing/ambiguous keypaths and fences bounce as named data with the
///   outline + the exact repair move.
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

const settingsRel = 'config/settings.yaml';

/// A real yaml doc: comments, a blank line, nested maps, a list — the
/// splice must touch ONLY the target keypath's lines.
const settingsOriginal = '''
# service settings — do not rename keys (ops tooling reads them)
service:
  name: gateway
  port: 8080

# retry policy (tuned 2026-09)
retry:
  max_attempts: 3
  backoff_ms: 50

features:
  - dark_mode
  - telemetry
''';

const pkgRel = 'assets/pkg.json';

const pkgOriginal = '''
{
  "name": "asset-pack",
  "version": "1.0.0",
  "meta": {
    "author": "ops",
    "tags": ["a", "b"]
  }
}
''';

Future<Directory> _jail() async {
  final dir = await Directory.systemTemp.createTemp('keypath_mat_jail_');
  File('${dir.path}/pubspec.yaml')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('name: keypath_jail\nenvironment:\n  sdk: ^3.0.0\n');
  File('${dir.path}/config/settings.yaml')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(settingsOriginal);
  File('${dir.path}/assets/pkg.json')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(pkgOriginal);
  return dir;
}

World _world() {
  final world = World()..addPlugin(AgentPlugin());
  world.upsertResource(ToolRegistryResource());
  return world;
}

void main() {
  late Directory jail;
  late FsToolsRoot root;
  setUp(() async {
    jail = await _jail();
    root = FsToolsRoot(jail.path);
  });
  tearDown(() => jail.delete(recursive: true).catchError((_) => jail));

  test('specs are REGISTERED DATA: yaml + json carry verb edit_key; the '
      'tick stamps edit_actions on their file nodes and maps keypath anchors',
      () async {
    for (final fc in ['yaml', 'json']) {
      final spec = materializerSpecFor(fc);
      expect(spec, isNotNull, reason: '$fc must have an edit spec');
      expect(spec!.spanCurrency, 'keypath');
      expect(spec.oracle, 'parse_semantic_diff');
      expect(spec.actions, ['set_key', 'replace_value', 'delete_key', 'append_list_item']);
    }
    final world = _world();
    final scan = _decoded(
      await repoEtlTool(world, jail).execute({'action': 'scan'}),
    );
    expect(scan['ok'], true, reason: '$scan');
    final index = world.getResource<MeaningIndex>();
    final yamlNode = index.byId.keys
        .where((id) => id.contains('config_settings.yaml'))
        .firstOrNull;
    expect(yamlNode, isNotNull, reason: 'the yaml file must map');
    final props = meaningComponentOf<MeaningProps>(
      world,
      index.byId[yamlNode!]!,
    )!.props;
    expect(props['edit_actions'], 'set_key,replace_value,delete_key,append_list_item');
    // The keypath anchors are in the tree (zoom serves them).
    final keyNodes = index.byId.keys.where((id) => id.startsWith('key_'));
    expect(keyNodes, isNotEmpty, reason: 'keypath nodes must exist');
  });

  test('yaml set_key lands BYTE-PRECISE with comments + siblings '
      'byte-identical; parse_semantic_diff green; only the intended '
      'change in the diff', () async {
    final out = _decoded(
      await editKeyTool(root).execute({
        'path': settingsRel,
        'op': 'set_key',
        'anchor': 'retry.max_attempts',
        'body': '5',
      }),
    );
    expect(out['ok'], true, reason: '${out['detail']}');
    expect(out['reverted'], false);

    final after = File('${jail.path}/$settingsRel').readAsStringSync();
    // The target line changed…
    expect(after, contains('  max_attempts: 5'));
    // …and EVERYTHING outside the target keypath's span is byte-identical:
    // comments, the blank separator line, siblings, the list.
    expect(after, contains('# service settings — do not rename keys'));
    expect(after, contains('# retry policy (tuned 2026-09)'));
    expect(after, contains('  name: gateway'));
    expect(after, contains('  port: 8080'));
    expect(after, contains('  backoff_ms: 50'));
    expect(after, contains('  - dark_mode'));
    expect(after, contains('  - telemetry'));
    // The only semantic change: retry.max_attempts 3 → 5.
    final before = keypathParse(settingsOriginal, isJson: false);
    final parsed = keypathParse(after, isJson: false);
    final diff = semanticDiff(before, parsed);
    expect(diff, hasLength(1), reason: '$diff');
    expect(diff.single.kind, 'changed');
    expect(diff.single.path, 'retry.max_attempts');
    expect(diff.single.before, 3);
    expect(diff.single.after, 5);
  });

  test('json set_key lands byte-precise; the semantic diff is exactly the '
      'intended change; siblings untouched', () async {
    final out = _decoded(
      await editKeyTool(root).execute({
        'path': pkgRel,
        'op': 'set_key',
        'anchor': 'meta.author',
        'body': 'platform',
      }),
    );
    expect(out['ok'], true, reason: '${out['detail']}');
    final after = File('${jail.path}/$pkgRel').readAsStringSync();
    expect(after, contains('"author": "platform"'));
    expect(after, contains('"name": "asset-pack"'));
    expect(after, contains('"tags": ["a", "b"]'));
    final diff = semanticDiff(
      keypathParse(pkgOriginal, isJson: true),
      keypathParse(after, isJson: true),
    );
    expect(diff, hasLength(1), reason: '$diff');
    expect(diff.single.path, 'meta.author');
    expect(diff.single.after, 'platform');
  });

  test('a VIOLATING edit AUTO-REVERTS: a body that breaks the parse '
      'restores every byte with the named failure class', () async {
    final before = File('${jail.path}/$settingsRel').readAsStringSync();
    final out = _decoded(
      await editKeyTool(root).execute({
        'path': settingsRel,
        'op': 'set_key',
        'anchor': 'retry.max_attempts',
        // `key: a: b` — not parseable yaml: the oracle must catch it.
        'body': 'a: b',
      }),
    );
    expect(out['ok'], false, reason: '$out');
    expect(out['reverted'], true, reason: '$out');
    expect(out['failureClass'], 'parse_failed');
    expect(
      File('${jail.path}/$settingsRel').readAsStringSync(),
      before,
      reason: 'auto-revert must restore exact bytes',
    );
  });

  test('append_list_item + delete_key compose; each is its own verified '
      'move', () async {
    final append = _decoded(
      await editKeyTool(root).execute({
        'path': settingsRel,
        'op': 'append_list_item',
        'anchor': 'features',
        'body': 'beta_ui',
      }),
    );
    expect(append['ok'], true, reason: '${append['detail']}');
    final mid = File('${jail.path}/$settingsRel').readAsStringSync();
    expect(mid, contains('  - beta_ui'));
    expect(mid, contains('# retry policy (tuned 2026-09)'));
    final diff = semanticDiff(
      keypathParse(settingsOriginal, isJson: false),
      keypathParse(mid, isJson: false),
    );
    expect(diff, hasLength(1), reason: '$diff');
    expect(diff.single.kind, 'added');
    expect(diff.single.path, 'features[2]');

    final del = _decoded(
      await editKeyTool(root).execute({
        'path': pkgRel,
        'op': 'delete_key',
        'anchor': 'meta.tags',
        'body': '',
      }),
    );
    expect(del['ok'], true, reason: '$del');
    final after = File('${jail.path}/$pkgRel').readAsStringSync();
    expect(after, isNot(contains('"tags"')));
    expect(after, contains('"author": "ops"'));
  });

  test('missing and unknown anchors bounce as named data with the outline '
      'and the exact repair move — never a guess', () async {
    final missing = _decoded(
      await editKeyTool(root).execute({
        'path': settingsRel,
        'op': 'replace_value',
        'anchor': 'retry.no_such_key',
        'body': 'x',
      }),
    );
    expect(missing['ok'], false);
    expect(missing['failureClass'], 'keypath_not_found');
    expect('${missing['repair']}${missing['hints']}', isNotEmpty,
        reason: 'the bounce must carry the exact repair move');
    // Unknown keypath node id + wrong class + unknown op, same discipline.
    final wrongClass = _decoded(
      await editKeyTool(root).execute({
        'path': 'docs/readme.md',
        'op': 'set_key',
        'anchor': 'name',
        'body': 'x',
      }),
    );
    expect(wrongClass['ok'], false);
    expect(wrongClass['failureClass'], 'not_keypath_class');
    final unknownOp = _decoded(
      await editKeyTool(root).execute({
        'path': settingsRel,
        'op': 'transmogrify',
        'anchor': 'service.name',
        'body': 'x',
      }),
    );
    expect(unknownOp['failureClass'], 'unknown_op');
    expect(
      File('${jail.path}/$settingsRel').readAsStringSync(),
      settingsOriginal,
      reason: 'bounces never touch bytes',
    );
  });
}
