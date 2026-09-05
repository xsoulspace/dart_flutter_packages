// ignore_for_file: lines_longer_than_80_chars

/// R7d GATE (ADR 0023 §3): a PACK-FED edit — the model supplies ONLY the
/// executable id and the symbol id; the op-chain travels with the pack as
/// data. Zero authored tokens for a known repair class.
///
/// The worked example is the loop-bound family: `inBounds` has the classic
/// `<` vs `<=` bug (the suite expects inBounds(3, 3) == true and FAILS);
/// the pack executable `dart/fix_loop_bound` (an [EditExecutableWire],
/// kind: replace_member_body) carries the corrected op-chain
/// (load i, load n, gt, not, return). The host compiles the body, applies
/// the span patch, verifies with the free oracles.
///
/// The wire shape is validated against the AE wire contract
/// (agentic_executables_wire) — syntax-only, hosts own realizations.
library;

import 'dart:convert';
import 'dart:io';

import 'package:agentic_executables_wire/agentic_executables_wire.dart'
    show EditExecutableWire;
import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'package:xsoulspace_agentic_workspace/xsoulspace_agentic_workspace.dart';

/// The pack entry AS DATA (what a know pack / project repair pack ships).
/// The model never sees or authors this — it picks the id.
const _fixLoopBoundPackJson = {
  'id': 'dart/fix_loop_bound',
  'kind': 'replace_member_body',
  'params': ['symbolId'],
  'verification': ['analyze', 'test'],
  'scope': 'lexical',
  'description':
      'Fix an off-by-one inclusive bound: the member body becomes the '
      'inclusive form (i <= n ⇔ !(i > n)) over its declared params.',
};

/// The pack's op-chain (data): NOT (i > n) — the inclusive-bound form.
const _fixLoopBoundChain = [
  {'label': 'load_arg', 'a': 'i'},
  {'label': 'load_arg', 'a': 'n'},
  {'label': 'gt'},
  {'label': 'not'},
  {'label': 'return'},
];

Future<Directory> _jail() async {
  final dir = await Directory.systemTemp.createTemp('pack_edit_jail_');
  File('${dir.path}/pubspec.yaml')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      'name: pack_jail\nenvironment:\n  sdk: ^3.0.0\ndev_dependencies:\n  test: any\n',
    );
  File('${dir.path}/lib/loop.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
bool inBounds(int i, int n) {
  return i < n;
}
''');
  File('${dir.path}/test/loop_test.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
import 'package:test/test.dart';
import 'package:pack_jail/loop.dart';

void main() {
  test('inBounds is inclusive at the bound', () {
    expect(inBounds(3, 3), isTrue);
  });
}
''');
  return dir;
}

void main() {
  test(
    'R7d: a pack-fed edit (fix_loop_bound) lands at zero authored tokens '
    '— the model supplies ids only; the chain travels with the pack',
    () async {
      // The wire validates the pack shape (fail loudly on unknown kinds).
      final wire = EditExecutableWire.fromJson(_fixLoopBoundPackJson);
      expect(wire.id, 'dart/fix_loop_bound');
      expect(wire.kind.wire, 'replace_member_body');
      expect(wire.verification.map((v) => v.wire), contains('test'));
      expect(wire.isApiBreaking, isFalse);

      final jail = await _jail();
      addTearDown(() => jail.delete(recursive: true).catchError((_) => jail));
      await Process.run('dart', ['pub', 'get'], workingDirectory: jail.path);

      final world = World()..addPlugin(AgentPlugin());
      world
        ..upsertResource(ToolRegistryResource())
        ..upsertResource(FlightRecorder())
        ..upsertResource(GenerationHandlerResource())
        ..upsertResource(ModelRouterResource(ModelRouter()))
        ..flush();
      await repoEtlTool(world, jail).execute({'action': 'scan'});
      final index = world.getResource<MeaningIndex>();
      final inBoundsId = index.byId.keys
          .where((id) => id.endsWith('_inBounds'))
          .first;

      // The materializer registers the pack entry + its op-chain (data).
      final mat = SpanEditMaterializer(world: world, workspace: jail)
        ..registerPackExecutable(wire, opChain: _fixLoopBoundChain);

      // THE MODEL MOVE: ids only. No op rows, no code, no patch text.
      final out = await mat.perform(
        action: 'apply_executable',
        executableId: 'dart/fix_loop_bound',
        symbolId: inBoundsId,
      );
      expect(out.ok, isTrue, reason: out.detail);
      expect(out.patchesApplied, 1);
      expect(out.analyzeMs, isNotNull, reason: 'per-phase timing ships');

      final body = File('${jail.path}/lib/loop.dart').readAsStringSync();
      // The compiled inclusive form: !(i > n) — paren placement follows
      // the expression-stack compiler; assert the semantics.
      expect(body, contains('i > n'));
      expect(body, contains('return !('));
      expect(body, isNot(contains('return i < n;')));

      // The workspace oracle grades the pack-fed edit.
      final testRun = await Process.run(
        'dart',
        ['test'],
        workingDirectory: jail.path,
      );
      expect(testRun.exitCode, 0, reason: '${testRun.stdout}${testRun.stderr}');

      // The tool surface exposes the same move (registry discipline).
      final registry = ToolRegistry();
      registry.register(
        editSymbolTool(world, jail, materializer: mat),
      );
      world.getResource<ToolRegistryResource>().register('default', registry);
      final raw = await world
          .getResource<ToolRegistryResource>()
          .get('default')!
          .execute(const ToolName('edit_symbol'), {
        'action': 'apply_executable',
        'executableId': 'dart/fix_loop_bound',
        'symbolId': inBoundsId,
      });
      final second = (jsonDecode(raw ?? '{}') as Map);
      // A second application: the fence (b) passes (coverage exists), the
      // body is idempotent-compiled and the suite stays green.
      expect(second['ok'], isTrue, reason: '$second');
      final afterSecond = await Process.run(
        'dart',
        ['test'],
        workingDirectory: jail.path,
      );
      expect(afterSecond.exitCode, 0);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'R7d: an unknown pack executable kind fails LOUDLY (AE wire rule)',
    () {
      expect(
        () => EditExecutableWire.fromJson({
          'id': 'x/y',
          'kind': 'transmogrify',
          'params': <String>[],
          'verification': <String>[],
        }),
        throwsArgumentError,
      );
    },
  );
}