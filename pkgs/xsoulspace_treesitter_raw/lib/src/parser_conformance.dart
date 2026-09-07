// ignore_for_file: lines_longer_as_80_chars

/// ADR 0035 §8 item 5 — the conformance battery (ParserConformance): ONE
/// battery that ANY SourceParser implementation must pass. It runs against
/// the FFI impl now and against the future v1 mechanical TS scanner later;
/// the scanner↔tree-sitter conformance DELTA (this report) is the ADR 0035
/// §7 clause-1 evidence, measured as data — not argued.
///
/// The battery holds the mapped symbols against fixture-annotation
/// markers, BOTH directions:
/// - every marker must be satisfied by a mapped symbol (missing → fail);
/// - every mapped symbol (except the file symbol) must be claimed by a
///   marker (unclaimed → fail — keeps fixtures tight, no silent extras).
library;

import 'dart:convert';

import 'fixture_annotation.dart';
import 'grammar_mapper.dart';
import 'source_parser.dart';
import 'span_bridge.dart';

/// One conformance row (per fixture, per implementation).
class ConformanceRow {
  const ConformanceRow({
    required this.fixture,
    required this.implementation,
    required this.pass,
    required this.failures,
    required this.symbolCount,
    required this.durationMs,
  });

  final String fixture;
  final String implementation;
  final bool pass;
  final List<String> failures;
  final int symbolCount;
  final double durationMs;
}

/// The delta-table deliverable: rows for every fixture × implementation.
class ConformanceReport {
  final List<ConformanceRow> rows = [];

  void add(ConformanceRow row) => rows.add(row);

  bool get allPass => rows.every((r) => r.pass);

  /// The human-readable delta table (the results-row artifact).
  String render() {
    final b = StringBuffer()
      ..writeln('| fixture | implementation | pass | symbols | ms | failures |')
      ..writeln('| --- | --- | --- | --- | --- | --- |');
    for (final r in rows) {
      b.writeln(
        '| ${r.fixture} | ${r.implementation} | ${r.pass ? 'PASS' : 'FAIL'} '
        '| ${r.symbolCount} | ${r.durationMs.toStringAsFixed(1)} '
        '| ${r.failures.isEmpty ? '-' : r.failures.join('; ')} |',
      );
    }
    return b.toString();
  }
}

/// The battery itself (pure Dart — implementation-agnostic).
class ParserConformance {
  ParserConformance({required this.mapping});

  /// The validated mapping table the battery validates fixtures against.
  final GrammarMapping mapping;

  /// Runs every [fixture] against [parser] (any [SourceParser]) and
  /// returns the row. Throws (with named codes) for fixture/table wiring
  /// errors — unknown node types in fixtures are NAMED, never silent.
  ConformanceRow runCase(
    FixtureCase fixture,
    SourceParser parser, {
    String? implementation,
  }) {
    validateFixtureAgainstTable(fixture, mapping);
    final failures = <String>[];
    final sw = Stopwatch()..start();
    List<MappedSymbol> symbols;
    try {
      final root = parser.parse(fixture.source);
      final bridge = Utf8Utf16SpanBridge(fixture.source);
      final mapper = GrammarMapper(mapping: mapping);
      final fileName = fixture.name.endsWith('.ts')
          ? fixture.name
          : '${fixture.name}.ts';
      symbols = mapper.map(
        root,
        fixture.source,
        bridge: bridge,
        fileName: fileName,
      );
      // Span-bridge round-trip: every mapped symbol's SourceSpan text must
      // equal the byte-slice text (the multibyte corruption detector).
      for (final s in symbols) {
        final node = _nodeFor(root, s);
        if (node == null) {
          failures.add('span_round_trip: no tree node for ${s.name}');
          continue;
        }
        final spanText = bridge.span(node).text;
        if (spanText.isEmpty && node.endByte > node.startByte) {
          failures.add('span_round_trip: empty span text for ${s.name}');
        }
        // UTF-16 projection must land on rune boundaries: re-encoding the
        // sliced text must yield exactly the node's byte range.
        final reencoded = utf8.encode(spanText).length;
        if (reencoded != node.endByte - node.startByte) {
          failures.add(
            'span_round_trip: UTF-8 re-encode length $reencoded != byte span '
            '${node.endByte - node.startByte} for ${s.name}',
          );
        }
      }
    } on GrammarMapException catch (e) {
      sw.stop();
      return ConformanceRow(
        fixture: fixture.name,
        implementation: implementation ?? parser.runtimeType.toString(),
        pass: false,
        failures: ['${e.code}: ${e.detail ?? ''}'],
        symbolCount: 0,
        durationMs: sw.elapsedMilliseconds.toDouble(),
      );
    }
    sw.stop();

    // Forward: every marker satisfied.
    for (final e in fixture.expectations) {
      final hit = symbols.any(
        (s) =>
            s.kind == e.kind &&
            s.grammarType == e.grammarType &&
            s.name == e.name &&
            (e.kind != SymbolKind.member || s.parentName == e.parentName),
      );
      if (!hit) {
        failures.add(
          'missing: ${e.kind} ${e.grammarType} '
          '${e.kind == SymbolKind.member ? '${e.parentName}.' : ''}${e.name} '
          '(fixture line ${e.line})',
        );
      }
    }
    // Reverse: every mapped symbol claimed (file symbols excluded — the
    // file node is structural, not annotated).
    for (final s in symbols) {
      if (s.kind == SymbolKind.file) continue;
      final claimed = fixture.expectations.any(
        (e) =>
            e.kind == s.kind &&
            e.grammarType == s.grammarType &&
            e.name == s.name &&
            (s.kind != SymbolKind.member || e.parentName == s.parentName),
      );
      if (!claimed) {
        failures.add(
          'unclaimed: ${s.kind} ${s.grammarType} '
          '${s.kind == SymbolKind.member ? '${s.parentName}.' : ''}${s.name} '
          '— annotate it or tighten the fixture',
        );
      }
    }
    return ConformanceRow(
      fixture: fixture.name,
      implementation: implementation ?? parser.runtimeType.toString(),
      pass: failures.isEmpty,
      failures: failures,
      symbolCount: symbols.length,
      durationMs: sw.elapsedMilliseconds.toDouble(),
    );
  }

  /// Runs the whole battery.
  ConformanceReport run(
    List<FixtureCase> fixtures,
    SourceParser parser, {
    String? implementation,
  }) {
    final report = ConformanceReport();
    for (final f in fixtures) {
      report.add(runCase(f, parser, implementation: implementation));
    }
    return report;
  }

  SourceNode? _nodeFor(SourceNode root, MappedSymbol s) {
    for (final n in root.walk()) {
      if (n.startByte == s.startByte &&
          n.endByte == s.endByte &&
          n.type == s.grammarType) {
        return n;
      }
    }
    return null;
  }
}
