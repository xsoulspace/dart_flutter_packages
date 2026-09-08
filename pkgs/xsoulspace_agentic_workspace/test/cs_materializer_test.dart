// ignore_for_file: lines_longer_as_80_chars

/// CS MATERIALIZER GATE (ADR 0035 §6 — the cs family, Tier C v1). LLM-free
/// e2e on a temp jail with a real .cs tree — mirrors ts_materializer_test:
///
/// - the map half: repo_etl scan stamps `sym`/`member` sub-nodes
///   (`csym_` prefix, binding-declared) with BYTE-precise spans (the
///   UTF-8 discipline — the substring at the span offsets IS the
///   declaration; attributes ride the member span);
/// - `insert_member` through the binding perform: byte-precise splice
///   (everything outside the touched span identical);
/// - `remove_member`: clean removal, no orphan lines;
/// - `apply_executable` through the PACK path (apply-mode consent);
/// - THE LIMITATION: `replace_member_body` bounces with the
///   class-scoped legal action list (the v1 limitation IS registry
///   data, ADR 0035 §5) — and the bounce carries no format literals;
/// - `oracle_unavailable`: no dotnet anywhere → the move bounces BEFORE
///   bytes land (file unchanged); a failing oracle AUTO-REVERTS
///   (`cs_error`);
/// - the scanner↔tree-sitter conformance delta over the 2 annotated
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

const petsRel = 'src/Pets.cs';

/// A real cs file: file-scoped namespace + class with a field, a
/// property and a method (the map-half shapes the v1 scanner indexes).
const petsOriginal = '''
namespace Kennel;

public class Dog
{
    private int _barkCount = 0;

    public string Name { get; set; }

    public int Bark(string name)
    {
        return _barkCount;
    }
}
''';

const counterRel = 'src/Counter.cs';

const counterOriginal = '''
namespace Kennel;

public class Counter
{
    private int count = 0;
    public void Bump()
    {
        count++;
    }
    public void Reset()
    {
        count = 0;
    }
}
''';

/// A jail with a FAKE analyzer: `.dotnet/dotnet` is an exit-[code] shell
/// script — the named oracle (dotnet_build) runs mechanically without
/// network or a real toolchain; [fakeDotnetExit] = 0 → green oracle,
/// 1 → every apply auto-reverts. [fakeDotnet] = false → a bare jail (no
/// `.dotnet/`, no project) for the oracle_unavailable staging.
Future<Directory> _jail({int fakeDotnetExit = 0, bool fakeDotnet = true}) async {
  final dir = await Directory.systemTemp.createTemp('cs_mat_jail_');
  File('${dir.path}/pubspec.yaml')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('name: cs_jail\nenvironment:\n  sdk: ^3.0.0\n');
  File('${dir.path}/$petsRel')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(petsOriginal);
  File('${dir.path}/$counterRel').writeAsStringSync(counterOriginal);
  if (fakeDotnet) {
    // A project file — the oracle's grading unit (the build grades the
    // jail; without it the move bounces oracle_unavailable).
    File('${dir.path}/Jail.csproj')
        .writeAsStringSync('<Project Sdk="Microsoft.NET.Sdk" />\n');
    final bin = File('${dir.path}/.dotnet/dotnet');
    bin.parent.createSync(recursive: true);
    bin.writeAsStringSync('#!/bin/sh\nexit $fakeDotnetExit\n');
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
Map<String, dynamic> _csEdit(
  FsToolsRoot root, {
  required String path,
  required String action,
  required String anchor,
  String? body,
}) {
  final binding = materializerRegistry.bindingFor('cs')!;
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
    if (kind == 'file') continue; // engine-stamped (fs tier), not scanner
    // Both syms and members read `<Parent>.<name>` in cs (namespaces
    // nest types; types nest members); a bare name attaches to the file.
    final dot = target.indexOf('.');
    String? parent;
    var name = target;
    if (dot > 0) {
      parent = target.substring(0, dot);
      name = target.substring(dot + 1);
    }
    out.add(_FixExpectation(kind, m.group(2)!, name, parent));
  }
  return out;
}

/// Fixture 1: file-scoped namespace + class with a field, a property and
/// an attribute riding the method span (no phantom attribute nodes).
const kennelFixture = '''
// @map file compilation_unit Kennel.cs
namespace Kennel;

public class Dog
{
    private int _barkCount = 0;

    public string Name { get; set; }

    [Fact]
    public void Bark()
    {
        _barkCount++;
    }
}
// @map sym file_scoped_namespace_declaration Kennel
// @map sym class_declaration Kennel.Dog
// @map member field_declaration Dog._barkCount
// @map member property_declaration Dog.Name
// @map member method_declaration Dog.Bark
''';

/// Fixture 2: block-scoped namespace + interface/struct/enum/class —
/// BOTH namespace forms map (tree-sitter-c-sharp's own kinds).
const shapesFixture = '''
// @map file compilation_unit Shapes.cs
using System;

namespace Geometry
{
    public interface IShape
    {
        double Area();
    }

    public struct Point
    {
        public double X;
    }

    public enum Kind
    {
        Circle,
        Square
    }

    public class Square : IShape
    {
        public double Area()
        {
            return 0;
        }
    }
}
// @map sym namespace_declaration Geometry
// @map sym interface_declaration Geometry.IShape
// @map member method_declaration IShape.Area
// @map sym struct_declaration Geometry.Point
// @map member field_declaration Point.X
// @map sym enum_declaration Geometry.Kind
// @map sym class_declaration Geometry.Square
// @map member method_declaration Square.Area
''';

/// The multibyte golden fixture: emoji live in comments and strings (C#
/// identifiers reject emoji but accept CJK letters) — byte offsets ≠
/// code-unit offsets is the classic silent corruption.
const multibyteFixture = '''
// Fixture: 🚀 emoji + CJK identifiers — the span bridge must survive.
public class 犬
{
    private string 名前 = "ポチ"; // 🎉 emoji comment

    public string 鳴く()
    {
        return "ワン";
    }
}
''';

/// Precondition probe: when dotnet IS on PATH, the runner cannot stage
/// the oracle_unavailable case in a bare jail — the test skips (named
/// reason, never a silent pass).
final bool _dotnetOnPath = () {
  try {
    return Process.runSync('dotnet', const ['--version']).exitCode == 0;
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

  test('a: repo_etl scan maps the cs file through the registered binding '
      '(sym + member nodes, memberOf spans, edit_actions stamped) and the '
      'spans are BYTE-precise', () async {
    final scan = await _scan(world, jail);
    expect(scan['ok'], true, reason: '$scan');
    final fileProps = _propsOf(world, 'f_src_Pets.cs');
    expect(fileProps['class'], 'cs');
    expect(fileProps['has_map'], true);
    expect(fileProps['edit_actions'],
        'insert_member,remove_member,apply_executable',
        reason: 'the tick itself surfaces what the class can do');

    // The mapped outline — sym + member nodes, ids
    // `csym_<fileNodeId>_<tail>` (binding-declared prefix, engine-stamped
    // id shape — the SAME scheme the splice anchor resolution recomputes).
    const fileNodeId = 'f_src_Pets.cs';
    final expected = <String, ({String kind, String grammarType})>{
      'csym_${fileNodeId}_Kennel': (
        kind: 'sym',
        grammarType: 'file_scoped_namespace_declaration',
      ),
      'csym_${fileNodeId}_Dog': (
        kind: 'sym',
        grammarType: 'class_declaration',
      ),
      'csym_${fileNodeId}_Dog__barkCount': (
        kind: 'member',
        grammarType: 'field_declaration',
      ),
      'csym_${fileNodeId}_Dog_Name': (
        kind: 'member',
        grammarType: 'property_declaration',
      ),
      'csym_${fileNodeId}_Dog_Bark': (
        kind: 'member',
        grammarType: 'method_declaration',
      ),
    };
    for (final entry in expected.entries) {
      final props = _propsOf(world, entry.key);
      expect(props['class'], 'cs', reason: entry.key);
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
    // memberOf: the class attaches to its namespace; members under their
    // declaring parent.
    expect(
      _propsOf(world, 'csym_${fileNodeId}_Dog')['member_of'],
      'Kennel',
    );
    expect(
      _propsOf(world, 'csym_${fileNodeId}_Dog_Bark')['member_of'],
      'Dog',
    );
    expect(
      _propsOf(world, 'csym_${fileNodeId}_Dog__barkCount')['member_of'],
      'Dog',
    );

    // BYTE-PRECISE spans: the substring AT the span offsets IS the
    // declaration.
    expect(
      _byteSlice(
        petsOriginal,
        _propsOf(world, 'csym_${fileNodeId}_Dog__barkCount')['span_start']
            as int,
        _propsOf(world, 'csym_${fileNodeId}_Dog__barkCount')['span_end']
            as int,
      ),
      'private int _barkCount = 0;',
    );
    expect(
      _byteSlice(
        petsOriginal,
        _propsOf(world, 'csym_${fileNodeId}_Dog_Name')['span_start'] as int,
        _propsOf(world, 'csym_${fileNodeId}_Dog_Name')['span_end'] as int,
      ),
      'public string Name { get; set; }',
    );
    final barkProps = _propsOf(world, 'csym_${fileNodeId}_Dog_Bark');
    final barkText = _byteSlice(
      petsOriginal,
      barkProps['span_start'] as int,
      barkProps['span_end'] as int,
    );
    expect(barkText, startsWith('public int Bark(string name)'));
    expect(barkText, endsWith('}'));
  });

  test('b: insert_member through the binding perform lands byte-precise '
      '(everything outside the touched span identical)', () async {
    final r = _csEdit(
      root,
      path: petsRel,
      action: 'insert_member',
      anchor: 'csym_f_src_Pets.cs_Dog',
      body: 'public string Wag()\n{\n    return "wag";\n}',
    );
    expect(r['ok'], true, reason: '$r');
    expect(r['reverted'], false);
    expect(r['failureClass'], isNull, reason: '$r');

    const expected = '''
namespace Kennel;

public class Dog
{
    private int _barkCount = 0;

    public string Name { get; set; }

    public int Bark(string name)
    {
        return _barkCount;
    }
    public string Wag()
    {
        return "wag";
    }
}
''';
    final bytes = File('${jail.path}/$petsRel').readAsStringSync();
    expect(bytes, expected, reason: 'byte-precise splice');
  });

  test('c: remove_member removes the member cleanly — no orphan lines, '
      'everything outside the touched span identical', () async {
    final r = _csEdit(
      root,
      path: counterRel,
      action: 'remove_member',
      anchor: 'csym_f_src_Counter.cs_Counter_Bump',
    );
    expect(r['ok'], true, reason: '$r');
    expect(r['reverted'], false);
    expect(r['failureClass'], isNull, reason: '$r');

    const expected = '''
namespace Kennel;

public class Counter
{
    private int count = 0;
    public void Reset()
    {
        count = 0;
    }
}
''';
    final bytes = File('${jail.path}/$counterRel').readAsStringSync();
    expect(bytes, expected, reason: 'clean full-line removal');
  });

  test('d: apply_executable through the PACK path (apply-mode consent) '
      'lands the authored body', () async {
    const body = 'count++;';
    const wire = EditExecutableWire(
      id: 'cs/fill_bump',
      kind: EditExecutableKind.authoredBody,
      params: ['symbolId'],
      verification: [EditVerification.analyze],
      description: 'trusted-author bump body (consented at pack-write)',
    );
    final packs = EditPackRegistry(consent: (w, diff) => true);
    packs.register(wire, authoredBody: body);
    final saved = csEditPacks;
    csEditPacks = packs;
    try {
      final r = _csEdit(
        root,
        path: counterRel,
        action: 'apply_executable',
        anchor: 'csym_f_src_Counter.cs_Counter_Bump',
        body: 'cs/fill_bump',
      );
      expect(r['ok'], true, reason: '$r');
      expect(r['reverted'], false, reason: '$r');

      final bytes = File('${jail.path}/$counterRel').readAsStringSync();
      expect(bytes, counterOriginal, reason: 'pack body spliced into the '
          'member (the consented body IS the body the member already '
          'carries — byte-identical re-splice)');
    } finally {
      csEditPacks = saved;
    }
  });

  test('e: THE LIMITATION — replace_member_body bounces with the '
      'class-scoped legal action list and NO format literals (§5)',
      () async {
    final r = _csEdit(
      root,
      path: counterRel,
      action: 'replace_member_body',
      anchor: 'csym_f_src_Counter.cs_Counter_Bump',
      body: 'count = 9;',
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
      r'(?<![A-Za-z0-9_])(cs|c#|csharp)(?![A-Za-z0-9_])',
    ).allMatches(bounceText).map((m) => m.group(0)).toList();
    expect(formatLeak, isEmpty, reason: 'format literal in bounce');
    // Nothing was touched.
    expect(File('${jail.path}/$counterRel').readAsStringSync(),
        counterOriginal);
  });

  test(
      'f: oracle_unavailable — with no dotnet in the jail and none on '
      'PATH, the move bounces BEFORE bytes land (file unchanged)',
      skip: _dotnetOnPath
          ? 'dotnet is on PATH — the oracle_unavailable precondition '
              'cannot be staged in a bare jail on this runner'
          : false, () async {
    final bareJail = await _jail(fakeDotnet: false);
    try {
      final bareRoot = FsToolsRoot(bareJail.path);
      final r = _csEdit(
        bareRoot,
        path: petsRel,
        action: 'insert_member',
        anchor: 'csym_f_src_Pets.cs_Dog',
        body: 'public void Extra() { }',
      );
      expect(r['ok'], false, reason: '$r');
      expect(r['bounce'], true, reason: 'a named PRE-apply bounce');
      expect(r['failureClass'], 'oracle_unavailable');
      expect(r['reverted'], false,
          reason: 'no byte was ever written — the oracle gate is BEFORE '
              'the splice lands');
      expect(r['repair'], contains('dotnet'));
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

  test('g: a failing analyzer AUTO-REVERTS (cs_error) — a broken edit '
      'never lands', () async {
    final badJail = await _jail(fakeDotnetExit: 1);
    try {
      final badRoot = FsToolsRoot(badJail.path);
      final r = _csEdit(
        badRoot,
        path: counterRel,
        action: 'remove_member',
        anchor: 'csym_f_src_Counter.cs_Counter_Bump',
      );
      expect(r['ok'], false, reason: '$r');
      expect(r['reverted'], true, reason: 'ALL bytes reverted');
      expect(r['failureClass'], 'cs_error');
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
      'Kennel.cs': kennelFixture,
      'Shapes.cs': shapesFixture,
    };
    final namedFailures = <String>[];
    for (final entry in fixtures.entries) {
      final expected = _parseMarkers(entry.value);
      final actual = csScanSymbols(entry.value);
      String actualKey(CsSymbol s) =>
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

  test('multibyte golden: CJK identifiers + emoji-in-comment/string spans '
      'decode EXACTLY (byte offsets ≠ code-unit offsets — the classic '
      'silent corruption)', () {
    final scanner = csScanSymbols(multibyteFixture);
    String slice(int s, int e) => _byteSlice(multibyteFixture, s, e);
    final dog = scanner.singleWhere((s) => s.name == '犬');
    expect(slice(dog.startByte, dog.endByte), startsWith('public class 犬'));
    final name = scanner.singleWhere(
      (s) => s.name == '名前' && s.parentName == '犬',
    );
    expect(slice(name.startByte, name.endByte),
        'private string 名前 = "ポチ";');
    final speak = scanner.singleWhere(
      (s) => s.name == '鳴く' && s.parentName == '犬',
    );
    final speakText = slice(speak.startByte, speak.endByte);
    expect(speakText, startsWith('public string 鳴く()'));
    expect(speakText, contains('return "ワン";'));
  });
}
