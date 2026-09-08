// ignore_for_file: lines_longer_as_80_chars

/// TS MATERIALIZER GATE (ADR 0035 §6 — the ts family, Tier C v1). LLM-free
/// e2e on a temp jail with a real .ts tree:
///
/// - the map half: repo_etl scan stamps `sym`/`member` sub-nodes
///   (`tsym_` prefix, binding-declared) with BYTE-precise spans (the
///   UTF-8 discipline — the substring at the span offsets IS the
///   declaration, emoji/CJK included);
/// - `insert_member` through the binding perform: byte-precise splice
///   (everything outside the touched span identical);
/// - `remove_member`: clean removal, no orphan lines;
/// - `apply_executable` through the PACK path (apply-mode consent);
/// - THE LIMITATION: `replace_member_body` bounces with the
///   class-scoped legal action list (the v1 limitation IS registry
///   data, ADR 0035 §5) — and the bounce carries no format literals;
/// - `oracle_unavailable`: no tsc anywhere → the move bounces BEFORE
///   bytes land (file unchanged); a failing oracle AUTO-REVERTS;
/// - the scanner↔tree-sitter conformance delta over the 4 annotated
///   fixtures (expected-node derivation replicated as TEST DATA — the
///   workspace never imports the FFI leaf, ADR 0035 §8).
library;

import 'dart:convert';
import 'dart:io';

import 'package:agentic_executables_wire/agentic_executables_wire.dart'
    show EditExecutableKind, EditExecutableWire, EditVerification;
import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart'
    show FileLockTable, FsToolsRoot;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'package:xsoulspace_agentic_workspace/xsoulspace_agentic_workspace.dart';

/// ToolDef.encode serializes execute results to JSON strings — decode at
/// the boundary (the measured landmine).
Map<String, dynamic> _decoded(Object? raw) => raw is String
    ? jsonDecode(raw) as Map<String, dynamic>
    : raw! as Map<String, dynamic>;

const petsRel = 'src/pets.ts';

/// A real ts file: class + methods + top-level function + arrow const
/// (the map-half shapes the v1 scanner must index).
const petsOriginal = '''
export class Calculator {
  private base = 10;

  greet(): string {
    return 'hello';
  }

  add(a: number, b: number): number {
    return this.base + a;
  }
}

export function topAdd(a: number, b: number): number {
  return a + b;
}

export const scale = (x: number): number => x * 2;
''';

const counterRel = 'src/counter.ts';

const counterOriginal = '''
export class Counter {
  count = 0;
  bump(): number {
    this.count += 1;
    return this.count;
  }
  reset(): void {
    this.count = 0;
  }
}
''';

/// A jail with a FAKE analyzer: `node_modules/.bin/tsc` is an exit-[code]
/// shell script — the named oracle (tsc_no_emit) runs mechanically
/// without network or a real toolchain; [fakeTscExit] = 0 → green
/// oracle, 1 → every apply auto-reverts. [fakeTsc] = false → a bare jail
/// (no node_modules) for the oracle_unavailable staging.
Future<Directory> _jail({int fakeTscExit = 0, bool fakeTsc = true}) async {
  final dir = await Directory.systemTemp.createTemp('ts_mat_jail_');
  File('${dir.path}/pubspec.yaml')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('name: ts_jail\nenvironment:\n  sdk: ^3.0.0\n');
  File('${dir.path}/$petsRel')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(petsOriginal);
  File('${dir.path}/$counterRel').writeAsStringSync(counterOriginal);
  if (fakeTsc) {
    final bin = File('${dir.path}/node_modules/.bin/tsc');
    bin.parent.createSync(recursive: true);
    bin.writeAsStringSync('#!/bin/sh\nexit $fakeTscExit\n');
    final chmod = Process.runSync('chmod', ['+x', bin.path]);
    if (chmod.exitCode != 0) {
      fail('cannot stage the fake analyzer: ${chmod.stderr}');
    }
  }
  return dir;
}

World _world() {
  final world = World()..addPlugin(AgentPlugin());
  world.upsertResource(ToolRegistryResource());
  return world;
}

Future<Map<String, dynamic>> _scan(World world, Directory jail) async {
  final out = await repoEtlTool(world, jail).execute({'action': 'scan'});
  return _decoded(out);
}

/// ONE edit through the REGISTERED binding (ADR 0035 §1 — the registry IS
/// the seam; the router reaches exactly this perform fn).
Map<String, dynamic> _tsEdit(
  FsToolsRoot root, {
  required String path,
  required String action,
  required String anchor,
  String? body,
}) {
  final binding = materializerRegistry.bindingFor('ts')!;
  return binding.materializer(
    NodeEditRequest(
      root: root,
      locks: FileLockTable(),
      path: path,
      action: action,
      anchor: anchor,
      body: body,
    ),
  );
}

Map<String, dynamic> _propsOf(World world, String id) {
  final entity = world.getResource<MeaningIndex>().byId[id];
  expect(entity, isNotNull, reason: 'missing node $id');
  return meaningComponentOf<MeaningProps>(world, entity!)?.props ?? {};
}

/// The UTF-8 substring AT the byte span offsets (the span reader's
/// currency — a code-unit/byte mixup corrupts the slice visibly).
String _byteSlice(String source, int startByte, int endByte) {
  final bytes = utf8.encode(source);
  final end = endByte.clamp(startByte, bytes.length);
  return utf8.decode(bytes.sublist(startByte, end));
}

// ---------------------------------------------------------------------------
// ADR 0035 §8 item 5 — the scanner↔tree-sitter conformance DELTA over the
// annotated fixtures. The workspace MAY NOT import the FFI leaf — the
// expected-node derivation (treesitter_raw's fixture_annotation marker
// grammar) is replicated here as TEST DATA; the fixture IS the truth,
// never a hand-authored parallel table (ADR 0022 invariant).
// ---------------------------------------------------------------------------

/// One expectation derived from a `// @map` marker.
class _FixExpectation {
  const _FixExpectation(
    this.kind,
    this.grammarType,
    this.name,
    this.parentName,
  );
  final String kind;
  final String grammarType;
  final String name;
  final String? parentName;

  String get key => '$kind|$grammarType|${parentName ?? ''}|$name';
}

List<_FixExpectation> _parseMarkers(String source) {
  final out = <_FixExpectation>[];
  final markerRe = RegExp(
    r'^\s*//\s*@map\s+(file|sym|member)\s+([A-Za-z_][\w]*)\s+([^\s]+)\s*$',
  );
  for (final line in source.split('\n')) {
    final m = markerRe.firstMatch(line);
    if (m == null) continue;
    final kind = m.group(1)!;
    final target = m.group(3)!;
    String? parent;
    var name = target;
    if (kind == 'member') {
      // Members read `<Parent>.<name>`; a bare name attaches to the file
      // (the spike's memberOf: file semantics).
      final dot = target.indexOf('.');
      if (dot > 0) {
        parent = target.substring(0, dot);
        name = target.substring(dot + 1);
      }
    }
    if (kind == 'file') continue; // engine-stamped (fs tier), not scanner
    out.add(_FixExpectation(kind, m.group(2)!, name, parent));
  }
  return out;
}

const calculatorFixture = '''
// @map file program calculator.ts
// Fixture: class with a field, a member arrow const, a decorated method
// (decorators must parse without producing phantom symbols).
export class Calculator {
  private base = 10;

  private scale = (x: number): number => x * 2;

  @logged()
  greet(name: string): string {
    return `hello \${name}`;
  }

  add(a: number, b: number): number {
    return this.base + a + b;
  }
}
// @map sym class_declaration Calculator
// @map member public_field_definition Calculator.base
// @map member public_field_definition Calculator.scale
// @map member method_definition Calculator.greet
// @map member method_definition Calculator.add
''';

const functionsFixture = '''
// @map file program functions.ts
// Fixture: top-level functions, arrow consts, a generator — member
// symbols included from day one (decision 2026-09-07).
export function add(a: number, b: number): number {
  return a + b;
}

export const multiply = (a: number, b: number): number => a * b;

const LIMIT = 99;

function* countdown(from: number): Generator<number> {
  yield from;
}
// @map sym function_declaration add
// @map member lexical_declaration multiply
// @map member lexical_declaration LIMIT
// @map sym generator_function_declaration countdown
''';

const genericsFixture = '''
// @map file program generics.ts
// Fixture: generics + an interface with signatures (members without
// bodies — the v1 boundary where body-composing actions are omitted).
export interface Repository<T> {
  size: number;
  findById(id: string): T;
}

export class MemoryRepo<T> implements Repository<T> {
  size = 0;

  findById(id: string): T {
    throw new Error(`not found: \${id}`);
  }
}
// @map sym interface_declaration Repository
// @map member property_signature Repository.size
// @map member method_signature Repository.findById
// @map sym class_declaration MemoryRepo
// @map member public_field_definition MemoryRepo.size
// @map member method_definition MemoryRepo.findById
''';

const multibyteFixture = '''
// @map file program multibyte.ts
// Fixture: emoji + CJK identifiers — byte offsets ≠ code-unit offsets is
// the classic silent corruption; the span bridge must survive it.
export function 縮める(テキスト: string): string {
  // 🚀 multibyte lives in comments, strings and identifiers alike.
  const ラベル = `🚀 \${テキスト}`;
  return ラベル;
}

export const 単語 = ['日本語', '🚀🎉'];
// @map sym function_declaration 縮める
// @map member lexical_declaration 縮める.ラベル
// @map member lexical_declaration 単語
''';

/// Precondition probe: when tsc IS on PATH, the runner cannot stage the
/// oracle_unavailable case in a bare jail — the test skips (named reason,
/// never a silent pass).
final bool _tscOnPath = () {
  try {
    return Process.runSync('tsc', const ['--version']).exitCode == 0;
    // ignore: avoid_catching_errors
  } on ProcessException {
    return false;
  }
}();

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

  test('a: repo_etl scan maps the ts file through the registered binding '
      '(sym + member nodes, memberOf spans, edit_actions stamped) and the '
      'spans are BYTE-precise', () async {
    final scan = await _scan(world, jail);
    expect(scan['ok'], true, reason: '$scan');
    final fileProps = _propsOf(world, 'f_src_pets.ts');
    expect(fileProps['class'], 'ts');
    expect(fileProps['has_map'], true);
    expect(fileProps['edit_actions'],
        'insert_member,remove_member,apply_executable',
        reason: 'the tick itself surfaces what the class can do');

    // The mapped outline — sym + member nodes, ids
    // `tsym_<fileNodeId>_<tail>` (binding-declared prefix, engine-stamped
    // id shape — the SAME scheme the splice anchor resolution recomputes).
    const fileNodeId = 'f_src_pets.ts';
    final expected = <String, ({String kind, String grammarType})>{
      'tsym_${fileNodeId}_Calculator': (
        kind: 'sym',
        grammarType: 'class_declaration',
      ),
      'tsym_${fileNodeId}_Calculator_base': (
        kind: 'member',
        grammarType: 'public_field_definition',
      ),
      'tsym_${fileNodeId}_Calculator_greet': (
        kind: 'member',
        grammarType: 'method_definition',
      ),
      'tsym_${fileNodeId}_Calculator_add': (
        kind: 'member',
        grammarType: 'method_definition',
      ),
      'tsym_${fileNodeId}_topAdd': (
        kind: 'sym',
        grammarType: 'function_declaration',
      ),
      'tsym_${fileNodeId}_scale': (
        kind: 'member',
        grammarType: 'lexical_declaration',
      ),
    };
    for (final entry in expected.entries) {
      final props = _propsOf(world, entry.key);
      expect(props['class'], 'ts', reason: entry.key);
      expect(props['grammar_type'], entry.value.grammarType,
          reason: entry.key);
      // The `contains` edge over the ONE relation.
      expect(
        world
            .getResource<MeaningIndex>()
            .triples
            .contains((fileNodeId, 'contains', entry.key)),
        isTrue,
        reason: 'file → ${entry.key}',
      );
    }
    // memberOf: members under their declaring parent; file-attached
    // members carry no member_of.
    expect(
      _propsOf(world, 'tsym_${fileNodeId}_Calculator_greet')['member_of'],
      'Calculator',
    );
    expect(
      _propsOf(world, 'tsym_${fileNodeId}_Calculator_base')['member_of'],
      'Calculator',
    );
    expect(
      _propsOf(world, 'tsym_${fileNodeId}_scale').containsKey('member_of'),
      isFalse,
      reason: 'top-level const attaches to the file',
    );

    // BYTE-PRECISE spans: the substring AT the span offsets IS the
    // declaration.
    expect(
      _byteSlice(
        petsOriginal,
        _propsOf(world, 'tsym_${fileNodeId}_Calculator_base')['span_start']
            as int,
        _propsOf(world, 'tsym_${fileNodeId}_Calculator_base')['span_end']
            as int,
      ),
      'private base = 10;',
    );
    final greetProps = _propsOf(world, 'tsym_${fileNodeId}_Calculator_greet');
    final greetText = _byteSlice(
      petsOriginal,
      greetProps['span_start'] as int,
      greetProps['span_end'] as int,
    );
    expect(greetText, startsWith('greet(): string {'));
    expect(greetText, endsWith('}'));
    final topAddProps = _propsOf(world, 'tsym_${fileNodeId}_topAdd');
    final topAddText = _byteSlice(
      petsOriginal,
      topAddProps['span_start'] as int,
      topAddProps['span_end'] as int,
    );
    expect(topAddText, startsWith('export function topAdd'));
    expect(topAddText, endsWith('}'));
    expect(
      _byteSlice(
        petsOriginal,
        _propsOf(world, 'tsym_${fileNodeId}_scale')['span_start'] as int,
        _propsOf(world, 'tsym_${fileNodeId}_scale')['span_end'] as int,
      ),
      'export const scale = (x: number): number => x * 2;',
    );
  });

  test('b: insert_member through the binding perform lands byte-precise '
      '(everything outside the touched span identical)', () async {
    final r = _tsEdit(
      root,
      path: petsRel,
      action: 'insert_member',
      anchor: 'tsym_f_src_pets.ts_Calculator',
      body: 'greet2(): number {\n  return 1;\n}',
    );
    expect(r['ok'], true, reason: '$r');
    expect(r['reverted'], false);
    expect(r['failureClass'], isNull, reason: '$r');

    const expected = '''
export class Calculator {
  private base = 10;

  greet(): string {
    return 'hello';
  }

  add(a: number, b: number): number {
    return this.base + a;
  }
  greet2(): number {
    return 1;
  }
}

export function topAdd(a: number, b: number): number {
  return a + b;
}

export const scale = (x: number): number => x * 2;
''';
    final bytes = File('${jail.path}/$petsRel').readAsStringSync();
    expect(bytes, expected, reason: 'byte-precise splice');
  });

  test('c: remove_member removes the member cleanly — no orphan lines, '
      'everything outside the touched span identical', () async {
    final r = _tsEdit(
      root,
      path: counterRel,
      action: 'remove_member',
      anchor: 'tsym_f_src_counter.ts_Counter_bump',
    );
    expect(r['ok'], true, reason: '$r');
    expect(r['reverted'], false);
    expect(r['failureClass'], isNull, reason: '$r');

    const expected = '''
export class Counter {
  count = 0;
  reset(): void {
    this.count = 0;
  }
}
''';
    final bytes = File('${jail.path}/$counterRel').readAsStringSync();
    expect(bytes, expected, reason: 'clean full-line removal');
  });

  test('d: apply_executable through the PACK path (apply-mode consent) '
      'lands the authored body', () async {
    const body = 'this.count += 1;\nreturn this.count;';
    const wire = EditExecutableWire(
      id: 'ts/fill_bump',
      kind: EditExecutableKind.authoredBody,
      params: ['symbolId'],
      verification: [EditVerification.analyze],
      description: 'trusted-author bump body (consented at pack-write)',
    );
    final packs = EditPackRegistry(consent: (w, diff) => true);
    packs.register(wire, authoredBody: body);
    final saved = tsEditPacks;
    tsEditPacks = packs;
    try {
      final r = _tsEdit(
        root,
        path: counterRel,
        action: 'apply_executable',
        anchor: 'tsym_f_src_counter.ts_Counter_bump',
        body: 'ts/fill_bump',
      );
      expect(r['ok'], true, reason: '$r');
      expect(r['reverted'], false, reason: '$r');

      const expected = '''
export class Counter {
  count = 0;
  bump(): number {
    this.count += 1;
    return this.count;
  }
  reset(): void {
    this.count = 0;
  }
}
''';
      final bytes = File('${jail.path}/$counterRel').readAsStringSync();
      expect(bytes, expected, reason: 'pack body spliced into the member');
    } finally {
      tsEditPacks = saved;
    }
  });

  test('e: THE LIMITATION — replace_member_body bounces with the '
      'class-scoped legal action list and NO format literals (§5)',
      () async {
    final r = _tsEdit(
      root,
      path: counterRel,
      action: 'replace_member_body',
      anchor: 'tsym_f_src_counter.ts_Counter_bump',
      body: 'this.count = 9;',
    );
    expect(r['ok'], false, reason: '$r');
    expect(r['bounce'], true, reason: 'a mechanical pre-apply bounce');
    expect(r['failureClass'], 'unknown_action');
    expect(r['reverted'], false, reason: 'no bytes were ever touched');
    final repair = '${r['repair']}';
    expect(repair, contains('insert_member'));
    expect(repair, contains('remove_member'));
    expect(repair, contains('apply_executable'));
    // The class-scoped list, EXACTLY the declared union (the v1
    // limitation is registry data — §5): nothing more, nothing invented.
    expect(
      RegExp(r'\[apply_executable, insert_member, remove_member\]')
          .hasMatch(repair),
      isTrue,
      reason: repair,
    );
    // No format name anywhere in the bounce (the §5 gate, at the bounce
    // level): the registry teaches vocabulary through the node's props.
    final bounceText = '${r['error']} $repair '
        '${(r['hints'] as List?)?.join(' ') ?? ''}';
    final formatLeak = RegExp(
      r'(?<![A-Za-z0-9_])(ts|tsx|typescript)(?![A-Za-z0-9_])',
    ).allMatches(bounceText).map((m) => m.group(0)).toList();
    expect(formatLeak, isEmpty, reason: 'format literal in bounce');
    // Nothing was touched.
    expect(File('${jail.path}/$counterRel').readAsStringSync(),
        counterOriginal);
  });

  test(
      'f: oracle_unavailable — with no tsc in the jail and none on PATH, '
      'the move bounces BEFORE bytes land (file unchanged)',
      skip: _tscOnPath
          ? 'tsc is on PATH — the oracle_unavailable precondition cannot '
              'be staged in a bare jail on this runner'
          : false, () async {
    final bareJail = await _jail(fakeTsc: false);
    try {
      final bareRoot = FsToolsRoot(bareJail.path);
      final r = _tsEdit(
        bareRoot,
        path: petsRel,
        action: 'insert_member',
        anchor: 'tsym_f_src_pets.ts_Calculator',
        body: 'extra(): void {}',
      );
      expect(r['ok'], false, reason: '$r');
      expect(r['bounce'], true, reason: 'a named PRE-apply bounce');
      expect(r['failureClass'], 'oracle_unavailable');
      expect(r['reverted'], false,
          reason: 'no byte was ever written — the oracle gate is BEFORE '
              'the splice lands');
      expect(r['repair'], contains('typescript'));
      // The file is EXACTLY what it was.
      expect(File('${bareJail.path}/$petsRel').readAsStringSync(),
          petsOriginal);
    } finally {
      try {
        bareJail.deleteSync(recursive: true);
      } on Object {
        // best effort
      }
    }
  });

  test('g: a failing analyzer AUTO-REVERTS (tsc_error) — a broken edit '
      'never lands', () async {
    final badJail = await _jail(fakeTscExit: 1);
    try {
      final badRoot = FsToolsRoot(badJail.path);
      final r = _tsEdit(
        badRoot,
        path: counterRel,
        action: 'remove_member',
        anchor: 'tsym_f_src_counter.ts_Counter_bump',
      );
      expect(r['ok'], false, reason: '$r');
      expect(r['reverted'], true, reason: 'ALL bytes reverted');
      expect(r['failureClass'], 'tsc_error');
      expect(
        File('${badJail.path}/$counterRel').readAsStringSync(),
        counterOriginal,
        reason: 'the file is exactly what it was',
      );
    } finally {
      try {
        badJail.deleteSync(recursive: true);
      } on Object {
        // best effort
      }
    }
  });

  test('conformance delta: the scanner matches the annotated fixtures '
      '(kinds, names, memberOf) — every mismatch is a named failure '
      'class', () {
    const fixtures = <String, String>{
      'calculator.ts': calculatorFixture,
      'functions.ts': functionsFixture,
      'generics.ts': genericsFixture,
      'multibyte.ts': multibyteFixture,
    };
    final namedFailures = <String>[];
    for (final entry in fixtures.entries) {
      final expected = _parseMarkers(entry.value);
      final actual = tsScanSymbols(entry.value);
      String actualKey(TsSymbol s) =>
          '${s.kind}|${s.grammarType}|${s.parentName ?? ''}|${s.name}';
      final expectedBag = <String, int>{};
      for (final e in expected) {
        expectedBag[e.key] = (expectedBag[e.key] ?? 0) + 1;
      }
      final actualBag = <String, int>{};
      for (final a in actual) {
        actualBag[actualKey(a)] = (actualBag[actualKey(a)] ?? 0) + 1;
      }
      // Named failure classes, both directions (the delta is measured as
      // data, never argued): a marker the scanner missed vs a node the
      // scanner indexed that no marker declares.
      for (final e in expectedBag.entries) {
        final delta = e.value - (actualBag[e.key] ?? 0);
        for (var i = 0; i < delta; i++) {
          namedFailures.add('${entry.key}: missing_node ${e.key}');
        }
      }
      for (final a in actualBag.entries) {
        final delta = a.value - (expectedBag[a.key] ?? 0);
        for (var i = 0; i < delta; i++) {
          namedFailures.add('${entry.key}: unexpected_node ${a.key}');
        }
      }
      // SPAN half — byte precision over the fixture source: the UTF-8
      // substring AT the span offsets must carry the symbol's own name.
      for (final s in actual) {
        final slice = _byteSlice(entry.value, s.startByte, s.endByte);
        if (!slice.contains(s.name)) {
          namedFailures.add('${entry.key}: span_not_byte_precise '
              '${s.grammarType} ${s.name} bytes '
              '${s.startByte}..${s.endByte} → "$slice"');
        }
      }
    }
    expect(namedFailures, isEmpty,
        reason: 'the scanner↔tree-sitter delta, as named data');
  });

  test('multibyte golden: emoji + CJK spans decode EXACTLY (byte offsets '
      '≠ code-unit offsets — the classic silent corruption)', () {
    final scanner = tsScanSymbols(multibyteFixture);
    String slice(int s, int e) => _byteSlice(multibyteFixture, s, e);
    final shorten = scanner.singleWhere((s) => s.name == '縮める');
    expect(slice(shorten.startByte, shorten.endByte),
        startsWith('export function 縮める'));
    final word = scanner.singleWhere((s) => s.name == '単語');
    expect(slice(word.startByte, word.endByte),
        "export const 単語 = ['日本語', '🚀🎉'];");
    final label = scanner.singleWhere(
      (s) => s.name == 'ラベル' && s.parentName == '縮める',
    );
    expect(
      slice(label.startByte, label.endByte),
      'const ラベル = `🚀 \${テキスト}`;',
    );
  });
}
