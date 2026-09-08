// ignore_for_file: lines_longer_than_80_chars

/// ADR 0035 §3 — REGISTRATION-TIME HONESTY: the registry linter's named
/// errors, each machine-checked and unit-tested (one violation = one
/// named error). A wiring error is a startup failure, never a silent
/// misattribution ("class has no actions").
///
/// ADR 0035 §5 — the mechanism-first gate: NO format name may appear in
/// the router or its bounce strings (the registry teaches vocabulary
/// through the node's own props, never through prose).
library;

import 'dart:io';

import 'package:test/test.dart';

import 'package:xsoulspace_agentic_workspace/xsoulspace_agentic_workspace.dart';

/// A minimal legal perform fn (the validator never calls it).
Map<String, dynamic> _fakePerform(NodeEditRequest r) => const {'ok': true};

MaterializerBinding _binding({
  String fileClass = 'md',
  Set<String> extensions = const {'.md', '.mdx'},
  List<String> actions = const ['replace_section'],
  String oracle = 'zero_broken_links',
  String anchors = 'heading_path',
  MapParser? mapParser,
  String? subNodePrefix = 'sec_',
}) => MaterializerBinding(
      fileClass: fileClass,
      extensions: extensions,
      actions: actions,
      materializer: _fakePerform,
      oracle: oracle,
      anchors: anchors,
      spanCurrency: 'section',
      mapFormat: 'heading_tree',
      emitter: 'section_splice',
      mapParser: mapParser,
      subNodePrefix: subNodePrefix,
    );

String _codes(List<String> errors) => errors
    .map((e) => e.split(':').first.trim())
    .toSet()
    .join(', ');

void main() {
  test('binding_without_file_class: a binding for an unregistered class '
      'is a named registration error (no dead bindings)', () {
    final errors = validateMaterializerBindings([
      _binding(fileClass: 'xml', extensions: {'.xml'}),
    ]);
    expect(errors, hasLength(1), reason: '$errors');
    expect(errors.single, startsWith('binding_without_file_class'));
  });

  test('binding_extensions_mismatch: a binding disagreeing with its '
      'file-class spec is a named registration error', () {
    // The real md spec declares {.md, .mdx}; this binding drops .mdx.
    final errors = validateMaterializerBindings([
      _binding(extensions: const {'.md'}),
    ]);
    expect(errors, hasLength(1), reason: '$errors');
    expect(errors.single, startsWith('binding_extensions_mismatch'));
  });

  test('extension_collision: one extension claimed by two bindings is a '
      'named registration error (path → class must resolve once)', () {
    final errors = validateMaterializerBindings(
      [
        _binding(fileClass: 'xml', extensions: {'.xml'}, actions: const []),
        _binding(
          fileClass: 'toml',
          extensions: {'.xml', '.toml'},
          actions: const [],
        ),
      ],
      classes: const [
        FileClassSpec(fileClass: 'xml', extensions: {'.xml'}),
        FileClassSpec(fileClass: 'toml', extensions: {'.toml'}),
      ],
    );
    expect(errors, hasLength(2), reason: '$errors'); // mismatch + collision
    expect(_codes(errors), contains('extension_collision'));
  });

  test('actions_without_oracle: actions without a named oracle is a '
      'named registration error (the honesty law, asserted)', () {
    final errors = validateMaterializerBindings([
      _binding(oracle: ''),
    ]);
    expect(errors, hasLength(1), reason: '$errors');
    expect(errors.single, startsWith('actions_without_oracle'));
  });

  test('anchor_currency_undeclared: actions without a declared anchor '
      'currency is a named registration error', () {
    final errors = validateMaterializerBindings([
      _binding(anchors: ''),
    ]);
    expect(errors, hasLength(1), reason: '$errors');
    expect(errors.single, startsWith('anchor_currency_undeclared'));
  });

  test('map_without_sub_node_prefix: a map parser without a sub-node id '
      'prefix is a named registration error (stale-map drop ownership)',
      () {
    final errors = validateMaterializerBindings([
      _binding(mapParser: mdMapParser, subNodePrefix: null),
    ]);
    expect(errors, hasLength(1), reason: '$errors');
    expect(errors.single, startsWith('map_without_sub_node_prefix'));
  });

  test('the REAL registry validates CLEAN: every binding agrees with its '
      'file-class spec, extension sets are disjoint, every action union '
      'has a named oracle and a declared anchor currency', () {
    expect(validateMaterializerBindings(materializerBindings.values.toList()),
        isEmpty);
    // Touching the registry view runs the same validation at init —
    // must not throw.
    expect(materializerRegistry.bindingFor('md'), isNotNull);
    expect(materializerRegistry.bindingFor('yaml'), isNotNull);
    expect(materializerRegistry.bindingFor('json'), isNotNull);
    expect(materializerRegistry.bindingFor('ts'), isNotNull,
        reason: 'the ts family is registered (ADR 0035 §6 Tier C v1)');
    final ts = materializerRegistry.bindingFor('ts')!;
    expect(ts.oracle, 'tsc_no_emit');
    expect(ts.anchors, 'node_id');
    expect(ts.actions, ['insert_member', 'remove_member', 'apply_executable'],
        reason: 'replace_member_body is deliberately OMITTED — the v1 '
            'limitation IS registry data (§5)');
    expect(ts.subNodePrefix, 'tsym_');
    expect(ts.mapParser, isNotNull);
    expect(materializerRegistry.bindingFor('cs'), isNotNull,
        reason: 'the cs family is registered (ADR 0035 §6 Tier C v1)');
    final cs = materializerRegistry.bindingFor('cs')!;
    expect(cs.oracle, 'dotnet_build');
    expect(cs.anchors, 'node_id');
    expect(cs.actions, ['insert_member', 'remove_member', 'apply_executable'],
        reason: 'replace_member_body is deliberately OMITTED — the v1 '
            'limitation IS registry data (§5)');
    expect(cs.subNodePrefix, 'csym_');
    expect(cs.mapParser, isNotNull);
    expect(cs.extensions, {'.cs'});
    expect(materializerRegistry.bindingFor('dart'), isNull,
        reason: 'dart moves stay on the span path — never routed through '
            'a node binding');
    expect(materializerRegistry.mapSubNodePrefixes.toSet(),
        unorderedEquals(['sec_', 'key_', 'tsym_', 'csym_']));
  });

  test('zero-arg-delta is a hard gate: every binding answers the SAME '
      'request envelope (the ONE verb arg shape)', () {
    for (final b in materializerBindings.values) {
      expect(b.actions, isNotEmpty, reason: b.fileClass);
      // The anchor resolver is a pure (nodeId, props, literal) → String
      // fn and the materializer a pure NodeEditRequest → map fn — the
      // arg shape {action, symbolId, body?, anchor?} is untouched.
      expect(b.resolveAnchor('n', const {}, null), 'n');
      expect(b.materializer, isA<NodeMaterializer>());
    }
  });

  test('§5 GATE: no format name appears anywhere in the router source '
      '(bounces included) — mechanism-first, bounded for every future '
      'class', () {
    final routerFile = File('lib/src/edit_node_router.dart');
    expect(routerFile.existsSync(), isTrue,
        reason: 'run from the package root');
    final src = routerFile.readAsStringSync();
    final leak = RegExp(r'\b(md|mdx|yaml|yml|json|ts|c#)\b');
    final hits = leak.allMatches(src)
        .map((m) => '${m.group(0)} @${src.substring(0, m.start).split('\n').length}')
        .toList();
    expect(hits, isEmpty, reason: 'format literals in the router: $hits');
  });
}
