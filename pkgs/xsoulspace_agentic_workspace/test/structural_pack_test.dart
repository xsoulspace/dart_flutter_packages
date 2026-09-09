// ignore_for_file: lines_longer_than_80_chars

/// STRUCTURAL PACK GATE (trusted-author tier — build order item 8): the
/// class-shape pack kinds `add_constructor_param` and `add_enum_case`,
/// applied through `apply_executable` with the spec AS DATA. The host
/// splices the constructor signature + backing field (+ the initializer
/// when required) — or the enum case — byte-precisely, with adjacent-line
/// punctuation repair (missing trailing commas at the splice point).
///
/// Gate cases:
/// - add param to a fixture class byte-precise (+ tool-surface move, and
///   the collision fence on a second application);
/// - add enum case byte-precise (constants terminator `;`, args form,
///   single-line inline form);
/// - oracle failure → AUTO-REVERT leaves the file byte-identical;
/// - missing consent REFUSES the move (consent is separate from the pack);
/// - approver denial touches no bytes;
/// - unknown symbol bounces as named data.
///
/// NON-CLAIM (v1): the coverage fence (b) is deliberately not required
/// for structural kinds — they ADD shape, they never replace tested
/// behavior; the analyzer + workspace-convention oracles still gate the
/// result and auto-revert on failure.
library;

import 'dart:convert';
import 'dart:io';

import 'package:agentic_executables_wire/agentic_executables_wire.dart'
    show EditExecutableKind, EditExecutableWire;
import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'package:xsoulspace_agentic_workspace/xsoulspace_agentic_workspace.dart';

/// The structural pack entries AS DATA (what a trusted-author pack
/// ships). Registration is free; application is consent-gated.
const _addCtorParamPackJson = {
  'id': 'dart/add_constructor_param',
  'kind': 'add_constructor_param',
  'params': [
    'symbolId',
    'paramName',
    'paramType',
    'required',
    'defaultValue',
    'constructor',
    'field',
    'initializer',
  ],
  'verification': ['analyze', 'test'],
  'scope': 'lexical',
  'description':
      'Splice a constructor param + backing field (+ initializer when '
      'required) — host-realized, consent-gated at apply time.',
};

const _addEnumCasePackJson = {
  'id': 'dart/add_enum_case',
  'kind': 'add_enum_case',
  'params': ['symbolId', 'caseName', 'args'],
  'verification': ['analyze', 'test'],
  'scope': 'lexical',
  'description':
      'Splice an enum case (optional const args) before the constants '
      'terminator — host-realized, consent-gated at apply time.',
};

Future<Directory> _jail() async {
  final dir = await Directory.systemTemp.createTemp('structural_pack_jail_');
  File('${dir.path}/pubspec.yaml')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      'name: structural_jail\nenvironment:\n  sdk: ^3.0.0\n'
      'dev_dependencies:\n  test: any\n',
    );
  File('${dir.path}/lib/counter.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
class Counter {
  final int start;

  Counter({this.start = 0});

  int next(int by) {
    return start + by;
  }
}
''');
  File('${dir.path}/lib/status.dart').writeAsStringSync('''
enum Status {
  idle,
  running;

  bool get isBusy => this == Status.running;
}
''');
  File('${dir.path}/lib/http.dart').writeAsStringSync('''
enum HttpStatus {
  ok(200),
  notFound(404);

  const HttpStatus(this.code);

  final int code;
}
''');
  File('${dir.path}/lib/color.dart').writeAsStringSync(
    'enum Color { red, green }\n',
  );
  File('${dir.path}/lib/point.dart').writeAsStringSync('''
class Point {
  final int x;

  const Point(this.x);
}
''');
  File('${dir.path}/test/structural_test.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
import 'package:test/test.dart';
import 'package:structural_jail/http.dart';
import 'package:structural_jail/point.dart';

void main() {
  test('point x', () {
    expect(const Point(1).x, 1);
  });

  test('http codes', () {
    expect(HttpStatus.notFound.code, 404);
  });
}
''');
  return dir;
}

Future<World> _scannedWorld(Directory jail) async {
  final world = World()..addPlugin(AgentPlugin());
  world
    ..upsertResource(ToolRegistryResource())
    ..upsertResource(FlightRecorder())
    ..upsertResource(GenerationHandlerResource())
    ..upsertResource(ModelRouterResource(ModelRouter()))
    ..flush();
  await repoEtlTool(world, jail).execute({'action': 'scan'});
  return world;
}

SpanEditMaterializer _mat(
  World world,
  Directory jail, {
  required bool consent,
}) => SpanEditMaterializer(
  world: world,
  workspace: jail,
  approver: consent ? (plan) async => true : null,
);

Future<void> _pubGet(Directory jail) async {
  await Process.run('dart', ['pub', 'get'], workingDirectory: jail.path);
}

void main() {
  test(
    'add_constructor_param: signature + backing field spliced '
    'byte-precisely; second application bounces on the collision fence; '
    'the tool surface exposes the same move',
    () async {
      final wire = EditExecutableWire.fromJson(_addCtorParamPackJson);
      expect(wire.kind.wire, 'add_constructor_param');
      expect(wire.kind, EditExecutableKind.addConstructorParam);

      final jail = await _jail();
      addTearDown(() => jail.delete(recursive: true));
      await _pubGet(jail);
      final world = await _scannedWorld(jail);
      final index = world.getResource<MeaningIndex>();
      final counterId = index.byId.keys
          .where((id) => id.endsWith('_Counter'))
          .single;

      final approved = <String>[];
      final mat = SpanEditMaterializer(
        world: world,
        workspace: jail,
        approver: (plan) async {
          approved.add(plan.description);
          return true;
        },
      )..registerPackExecutable(wire);

      final out = await mat.perform(
        action: 'apply_executable',
        executableId: 'dart/add_constructor_param',
        symbolId: counterId,
        executableParams: {'paramName': 'step', 'paramType': 'int', 'required': true},
      );
      expect(out.ok, isTrue, reason: out.detail);
      expect(out.reverted, isFalse);
      expect(out.patchesApplied, 2, reason: 'signature + backing field');
      expect(approved.single, contains('add_constructor_param'));

      // BYTE-PRECISE: the file is exactly the expected splice.
      expect(
        File('${jail.path}/lib/counter.dart').readAsStringSync(),
        '''
class Counter {
  final int step;
  final int start;

  Counter({this.start = 0, required this.step});

  int next(int by) {
    return start + by;
  }
}
''',
      );

      // The workspace oracle grades the structural move.
      final testRun = await Process.run(
        'dart',
        ['test'],
        workingDirectory: jail.path,
      );
      expect(testRun.exitCode, 0, reason: '${testRun.stdout}${testRun.stderr}');

      // Second application: the collision fence bounces BEFORE any write
      // (ambiguity is data, never a silent overwrite).
      final second = await mat.perform(
        action: 'apply_executable',
        executableId: 'dart/add_constructor_param',
        symbolId: counterId,
        executableParams: {'paramName': 'step', 'paramType': 'int', 'required': true},
      );
      expect(second.ok, isFalse);
      expect(
        second.detail,
        contains('the constructor already has a parameter named step'),
      );
      expect(
        File('${jail.path}/lib/counter.dart').readAsStringSync(),
        contains('Counter({this.start = 0, required this.step});'),
        reason: 'the bounce touched no bytes',
      );

      // The tool surface exposes the same move (registry discipline): the
      // bounced second application travels as structured data.
      final registry = ToolRegistry();
      registry.register(editSymbolTool(world, jail, materializer: mat));
      world.getResource<ToolRegistryResource>().register('default', registry);
      final raw = await world
          .getResource<ToolRegistryResource>()
          .get('default')!
          .execute(const ToolName('edit_symbol'), {
        'action': 'apply_executable',
        'executableId': 'dart/add_constructor_param',
        'symbolId': counterId,
        'executableParams': {
          'paramName': 'step',
          'paramType': 'int',
          'required': true,
        },
      });
      final bounced = jsonDecode(raw ?? '{}') as Map;
      expect(bounced['bounce'], isTrue, reason: '$bounced');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'add_enum_case: the case splices before the constants terminator, '
    'with args, and inline for a single-line enum',
    () async {
      final wire = EditExecutableWire.fromJson(_addEnumCasePackJson);
      expect(wire.kind.wire, 'add_enum_case');
      expect(wire.kind, EditExecutableKind.addEnumCase);

      final jail = await _jail();
      addTearDown(() => jail.delete(recursive: true));
      await _pubGet(jail);
      final world = await _scannedWorld(jail);
      final index = world.getResource<MeaningIndex>();
      String idOf(String name) =>
          index.byId.keys.where((id) => id.endsWith('_$name')).single;
      final mat = _mat(world, jail, consent: true)
        ..registerPackExecutable(wire);

      // (1) constants terminator `;` on the last constant's own line: the
      // adjacent line gains the trailing comma (adjacent-line repair).
      final out = await mat.perform(
        action: 'apply_executable',
        executableId: 'dart/add_enum_case',
        symbolId: idOf('Status'),
        executableParams: {'caseName': 'done'},
      );
      expect(out.ok, isTrue, reason: out.detail);
      expect(
        File('${jail.path}/lib/status.dart').readAsStringSync(),
        '''
enum Status {
  idle,
  running,
  done;

  bool get isBusy => this == Status.running;
}
''',
      );

      // (2) const args: the case splices as `created(201),`.
      final out2 = await mat.perform(
        action: 'apply_executable',
        executableId: 'dart/add_enum_case',
        symbolId: idOf('HttpStatus'),
        executableParams: {'caseName': 'created', 'args': '201'},
      );
      expect(out2.ok, isTrue, reason: out2.detail);
      expect(
        File('${jail.path}/lib/http.dart').readAsStringSync(),
        '''
enum HttpStatus {
  ok(200),
  notFound(404),
  created(201);

  const HttpStatus(this.code);

  final int code;
}
''',
      );

      // (3) single-line enum, no members: inline splice before the brace.
      final out3 = await mat.perform(
        action: 'apply_executable',
        executableId: 'dart/add_enum_case',
        symbolId: idOf('Color'),
        executableParams: {'caseName': 'blue'},
      );
      expect(out3.ok, isTrue, reason: out3.detail);
      expect(
        File('${jail.path}/lib/color.dart').readAsStringSync(),
        'enum Color { red, green, blue }\n',
      );

      final testRun = await Process.run(
        'dart',
        ['test'],
        workingDirectory: jail.path,
      );
      expect(testRun.exitCode, 0, reason: '${testRun.stdout}${testRun.stderr}');

      // Collision fence: an existing case name bounces as named data.
      final dup = await mat.perform(
        action: 'apply_executable',
        executableId: 'dart/add_enum_case',
        symbolId: idOf('Status'),
        executableParams: {'caseName': 'done'},
      );
      expect(dup.ok, isFalse);
      expect(dup.detail, contains('already has a case named done'));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'oracle failure AUTO-REVERTS: a param the analyzer rejects restores '
    'the file byte-identically',
    () async {
      final jail = await _jail();
      addTearDown(() => jail.delete(recursive: true));
      await _pubGet(jail);
      final world = await _scannedWorld(jail);
      final index = world.getResource<MeaningIndex>();
      final pointId =
          index.byId.keys.where((id) => id.endsWith('_Point')).single;
      final before = File('${jail.path}/lib/point.dart').readAsStringSync();

      final mat = _mat(world, jail, consent: true)
        ..registerPackExecutable(
          EditExecutableWire.fromJson(_addCtorParamPackJson),
        );
      final out = await mat.perform(
        action: 'apply_executable',
        executableId: 'dart/add_constructor_param',
        symbolId: pointId,
        executableParams: {
          'paramName': 'bad',
          'paramType': 'NoSuchType',
          'required': true,
        },
      );
      expect(out.ok, isFalse);
      expect(out.reverted, isTrue, reason: out.detail);
      expect(out.failureClass, 'analyze_failed');
      expect(
        File('${jail.path}/lib/point.dart').readAsStringSync(),
        before,
        reason: 'auto-revert restores the exact pre-move bytes',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'missing consent REFUSES the structural move (consent is separate '
    'from the pack; deny-by-default)',
    () async {
      final jail = await _jail();
      addTearDown(() => jail.delete(recursive: true));
      await _pubGet(jail);
      final world = await _scannedWorld(jail);
      final index = world.getResource<MeaningIndex>();
      final counterId = index.byId.keys
          .where((id) => id.endsWith('_Counter'))
          .single;
      final before = File('${jail.path}/lib/counter.dart')
          .readAsStringSync();

      // Registration is free — the pack lands, the APPLICATION refuses.
      final mat = _mat(world, jail, consent: false)
        ..registerPackExecutable(
          EditExecutableWire.fromJson(_addCtorParamPackJson),
        );
      final out = await mat.perform(
        action: 'apply_executable',
        executableId: 'dart/add_constructor_param',
        symbolId: counterId,
        executableParams: {'paramName': 'step', 'paramType': 'int', 'required': true},
      );
      expect(out.ok, isFalse);
      expect(out.failureClass, 'bounce:consent', reason: out.detail);
      expect(out.detail, contains('no consent approver is wired'));
      expect(
        File('${jail.path}/lib/counter.dart').readAsStringSync(),
        before,
        reason: 'a refused move touches no bytes',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'consent DENIAL applies nothing; unknown symbol bounces as named data',
    () async {
      final jail = await _jail();
      addTearDown(() => jail.delete(recursive: true));
      await _pubGet(jail);
      final world = await _scannedWorld(jail);
      final index = world.getResource<MeaningIndex>();
      final counterId = index.byId.keys
          .where((id) => id.endsWith('_Counter'))
          .single;
      final before = File('${jail.path}/lib/counter.dart')
          .readAsStringSync();

      final mat = SpanEditMaterializer(
        world: world,
        workspace: jail,
        approver: (plan) async => false,
      )..registerPackExecutable(
          EditExecutableWire.fromJson(_addCtorParamPackJson),
        );
      final denied = await mat.perform(
        action: 'apply_executable',
        executableId: 'dart/add_constructor_param',
        symbolId: counterId,
        executableParams: {'paramName': 'step', 'paramType': 'int', 'required': true},
      );
      expect(denied.ok, isFalse);
      expect(denied.failureClass, 'permission_denied');
      expect(
        File('${jail.path}/lib/counter.dart').readAsStringSync(),
        before,
      );

      final unknown = await mat.perform(
        action: 'apply_executable',
        executableId: 'dart/add_constructor_param',
        symbolId: 'sym_missing_symbol',
        executableParams: {'paramName': 'step', 'paramType': 'int', 'required': true},
      );
      expect(unknown.ok, isFalse);
      expect(unknown.detail, contains('unknown symbol id'));
      expect(unknown.repair, isNotEmpty, reason: 'the exact repair move');
      expect(
        File('${jail.path}/lib/counter.dart').readAsStringSync(),
        before,
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
