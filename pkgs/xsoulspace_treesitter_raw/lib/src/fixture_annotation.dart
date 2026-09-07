// ignore_for_file: lines_longer_as_80_chars

/// ADR 0035 §8 item 4 / ADR 0022 invariant — node expectations are DERIVED
/// from fixture annotations (comment markers), NEVER from a hand-authored
/// parallel truth table. The fixture IS the truth; the battery parses its
/// markers and holds the parser output against them.
///
/// Marker grammar (one per line, `//`-commented):
///     // @map file  `<grammarType>` `<name>`
///     // @map sym   `<grammarType>` `<name>`
///     // @map member `<grammarType>` `<Parent>`.`<name>`
///
/// A marker whose `<grammarType>` is not a mapping-table key is a NAMED
/// fixture error (`unknown_node_type_in_fixture`) — unknown node types in
/// fixtures never pass silently.
library;

import 'grammar_mapper.dart';

/// One expectation parsed from a fixture marker.
class FixtureExpectation {
  const FixtureExpectation({
    required this.kind,
    required this.grammarType,
    required this.name,
    required this.parentName,
    required this.line,
  });

  final SymbolKind kind;
  final String grammarType;
  final String name;

  /// Members only (`Parent.name` in the marker).
  final String? parentName;
  final int line;
}

/// A fixture: source text + parsed expectations.
class FixtureCase {
  FixtureCase._(this.name, this.source, this.expectations);

  final String name;
  final String source;
  final List<FixtureExpectation> expectations;

  /// Loads a fixture from its text: parses every `// @map` marker.
  factory FixtureCase.parse(String name, String source) {
    final expectations = <FixtureExpectation>[];
    final lines = source.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final m = _markerRe.firstMatch(lines[i]);
      if (m == null) continue;
      final kindStr = m.group(1)!;
      final grammarType = m.group(2)!;
      final nameTarget = m.group(3)!;
      final kind = switch (kindStr) {
        'file' => SymbolKind.file,
        'sym' => SymbolKind.sym,
        'member' => SymbolKind.member,
        _ => throw FixtureAnnotationException(
          'unknown_marker_kind:$kindStr',
          line: i + 1,
        ),
      };
      String? parentName;
      var name = nameTarget;
      if (kind == SymbolKind.member) {
        // Members read `<Parent>.<name>`; a parentless member (attached to
        // the file node — memberOf: 'file') reads bare `<name>`.
        final dot = nameTarget.indexOf('.');
        if (dot == 0 || dot == nameTarget.length - 1) {
          throw FixtureAnnotationException(
            'member_marker_needs_parent',
            line: i + 1,
            detail: 'member markers must read <Parent>.<name> or bare <name>',
          );
        }
        if (dot > 0) {
          parentName = nameTarget.substring(0, dot);
          name = nameTarget.substring(dot + 1);
        }
      }
      expectations.add(
        FixtureExpectation(
          kind: kind,
          grammarType: grammarType,
          name: name,
          parentName: parentName,
          line: i + 1,
        ),
      );
    }
    return FixtureCase._(name, source, expectations);
  }
}

final RegExp _markerRe = RegExp(
  r'^\s*//\s*@map\s+(file|sym|member)\s+([A-Za-z_][\w]*)\s+([^\s]+)\s*$',
);

/// The named fixture-annotation errors.
final class FixtureAnnotationException implements Exception {
  const FixtureAnnotationException(
    this.code, {
    required this.line,
    this.detail,
  });

  final String code;
  final int line;
  final String? detail;

  @override
  String toString() =>
      'fixture_annotation_error($code) at line $line'
      '${detail == null ? '' : ': $detail'}';
}

/// Validates fixture expectations against a mapping table: a marker whose
/// grammar type is not a table key is a NAMED error (ADR 0035 §8 — table
/// validation; unknown node types in fixtures never pass silently).
void validateFixtureAgainstTable(FixtureCase fixture, GrammarMapping mapping) {
  for (final e in fixture.expectations) {
    if (!mapping.table.containsKey(e.grammarType)) {
      throw FixtureAnnotationException(
        'unknown_node_type_in_fixture',
        line: e.line,
        detail:
            'marker references "${e.grammarType}", which is not a key of '
            'the mapping table (add it to the table or fix the marker)',
      );
    }
  }
}
