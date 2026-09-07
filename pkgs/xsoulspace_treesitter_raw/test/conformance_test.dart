// The conformance battery (ADR 0035 §8 item 5) run against the FFI impl.
// The battery itself is implementation-agnostic (ParserConformance) — the
// future v1 mechanical TS scanner runs the SAME cases; the scanner↔
// tree-sitter DELTA (ConformanceReport.render) is the clause-1 evidence.
import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_treesitter_raw/xsoulspace_treesitter_raw.dart';

const fixtures = [
  'calculator.ts',
  'functions.ts',
  'generics.ts',
  'multibyte.ts',
];

void main() {
  final dylibPath = findGrammarDylib();
  final skipReason = dylibPath == null
      ? 'grammar_dylib_missing — run tool/build_grammar.sh'
      : false;

  test(
    'the battery passes against the FFI impl (both directions, '
    'span round-trip included)',
    skip: skipReason,
    () {
      final parser = TreeSitterParser.open();
      try {
        final mapping = GrammarMapping.validate(tsMappingTable);
        final cases = [
          for (final name in fixtures)
            FixtureCase.parse(
              name,
              File('test/fixtures/$name').readAsStringSync(),
            ),
        ];
        final battery = ParserConformance(mapping: mapping);
        final report = battery.run(
          cases,
          parser,
          implementation: 'TreeSitterParser(ffi)',
        );
        // ignore: avoid_print
        print('--- conformance delta table ---');
        // ignore: avoid_print
        print(report.render());
        for (final row in report.rows) {
          expect(
            row.failures,
            isEmpty,
            reason: 'fixture ${row.fixture} failed: ${row.failures.join('; ')}',
          );
        }
        expect(report.allPass, isTrue);
      } finally {
        parser.dispose();
      }
    },
  );

  test(
    'fixture annotations with unknown node types are NAMED errors',
    skip: skipReason,
    () {
      const badFixture = '''
// @map file program bad.ts
// @map sym class_declaration Nope
class Nope {}
// @map sym not_in_table Mystery
''';
      final fixture = FixtureCase.parse('bad.ts', badFixture);
      final mapping = GrammarMapping.validate(tsMappingTable);
      expect(
        () => validateFixtureAgainstTable(fixture, mapping),
        throwsA(
          predicate<Object>(
            (e) =>
                e.toString().contains('unknown_node_type_in_fixture') &&
                e.toString().contains('not_in_table'),
          ),
        ),
      );
    },
  );
}
