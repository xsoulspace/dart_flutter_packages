// ignore_for_file: lines_longer_than_80_chars

/// `locate` structural discovery (ADR 0014 §2) — the ray-cast over a symbol
/// index. Verifies: deterministic def+uses ranking, jail-relative paths, a
/// miss returns null (not error), and the index JSON round-trips so hosts can
/// persist / restore / feed it as AE-shaped world-affordance.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_agentic_harness/src/tooling/locate_index.dart';

void main() {
  late Directory jail;
  late SymbolIndex index;

  setUp(() async {
    jail = await Directory.systemTemp.createTemp('locate_test_');
    for (final (path, body) in [
      ('lib/hero.dart', 'class Hero {\n  final String name;\n}\nHero hero = Hero();\n'),
      ('lib/villain.dart', 'final enemy = Hero();\n'),
      ('README.md', 'The hero rides at dawn.\n'),
    ]) {
      final f = File('${jail.path}/$path');
      await f.parent.create(recursive: true);
      await f.writeAsString(body);
    }
    index = SymbolIndex.build(jail.path);
  });

  tearDown(() async {
    if (jail.existsSync()) await jail.delete(recursive: true);
  });

  test('locate finds def (class) + uses, ranked, jail-relative', () {
    final r = index.locate('Hero');
    expect(r, isNotNull);
    expect(r!.definitionCount, greaterThanOrEqualTo(1));
    // Same file carries both the class def and a use; multi-file uses too.
    final files = r.occurrences.map((o) => o.file).toSet();
    expect(files, contains('lib/hero.dart'));
    expect(files, contains('lib/villain.dart'));
    // Never leaks the absolute jail path.
    expect(jsonEncode(r.toJson()), isNot(contains(jail.path)));
    // Defs sort first.
    final first = r.occurrences.first;
    expect(first.isDefinition, isTrue);
  });

  test('misses are a null / found:false, not an error', () {
    expect(index.locate('DoesNotExistAtAll'), isNull);
    expect(index.locate('macguffin_relic'), isNull); // absent in every file
  });

  test('index JSON round-trips for persistence / AE-shaped affordance', () {
    final json = jsonEncode(index.toJson());
    final restored = SymbolIndex.fromJson(jail.path, json);
    final r = restored.locate('Hero');
    expect(r, isNotNull);
    expect(r!.total, index.locate('Hero')!.total);
    expect(r.occurrences.length, index.locate('Hero')!.occurrences.length);
  });

  test('locate seam-3 tool returns found:false on a miss', () async {
    final tool = locateTool(LocateRoot(index));
    final out = await tool.execute({'symbol': 'nopeXYZ'});
    expect(out, isNotNull);
    final map = jsonDecode(out!) as Map<String, dynamic>;
    expect(map['found'], false);
    expect(map['ok'], true);
  });

  test('locate tool returns defs first + total count on a hit', () async {
    final tool = locateTool(LocateRoot(index));
    final out = await tool.execute({'symbol': 'Hero'});
    expect(out, isNotNull);
    final map = jsonDecode(out!) as Map<String, dynamic>;
    expect(map['found'], true);
    expect(map['total'], greaterThanOrEqualTo(2));
    expect(map['definitions'], greaterThanOrEqualTo(1));
    expect(map['occurrences'], isA<List>());
  });
}
