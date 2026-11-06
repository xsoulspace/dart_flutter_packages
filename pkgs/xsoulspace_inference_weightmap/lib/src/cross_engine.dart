/// WS-2 cross-engine agreement: digest bundles and their certification.
///
/// Phase-B law (PROGRAM.md WS-2): an edit is certified only when the Rust
/// engine and the Python `mlx_lm` boundary AGREE on the frozen G-cell
/// battery. This module owns the frozen wire shape (digest bundles), its
/// parser (every refusal NAMED `MALFORMED_BUNDLE <detail>`, never a silent
/// default), and the certification verdict union.
///
/// PYTHON-FIRST LAW (frozen, never re-litigated here): `python_mlxlm` is the
/// REFERENCE engine (mlx_native's PYTHON-BOUNDARY law — Python is where the
/// model semantics are defined and observed); `rust` is the CANDIDATE that
/// must match it. The rule is mechanical, not prose: [CrossEngineCertification
/// .certify] assigns roles from the bundles' `engine` fields (argument order
/// is irrelevant), evaluates the pre-registered tolerance as
/// `allows(expected: reference, actual: candidate)`, and attributes every
/// disagreement to the candidate. Agreement NEVER certifies Python against
/// Rust; a pair without exactly one `python_mlxlm` and one `rust` bundle is a
/// named [CertificationRefused] (ENGINE_PAIR_INVALID), not a verdict.
///
/// TOLERANCE LAW (oracle boundary, inherited from `patch_algebra.dart`): the
/// per-cell absolute delta bound is typed [Tolerance] data supplied by the
/// caller from the frozen oracle side — this module invents no epsilon. The
/// comparison is [Tolerance]'s pre-registered edge-INCLUSIVE rule
/// `|actual - expected| <= max(abs, rel * max(|expected|, |actual|))`.
///
/// DIGESTS KEY, NUMBERS DECIDE: `logits_digest` / `behavior_digest` are
/// identity evidence — they key the certification (V-6 drift law: outside the
/// key = a new claim) and record bit-equality when it happens
/// ([Agree.logitsBitwiseEqual]). They are never the agreement criterion
/// themselves, because a digest cannot express a tolerance: two engines with
/// different kernel float order produce different logits digests for
/// behaviorally identical runs. The criterion is the per-cell numeric
/// `behavior_value` under the registered [Tolerance].
///
/// Frozen bundle wire shape (strict key sets; the same schema
/// `tool/runs/ws2_certify.py` parses — one rulebook, two implementations):
///
/// ```json
/// {"engine": "rust" | "python_mlxlm",
///  "cells": [{"cell": "<name>",
///             "logits_digest": "<non-empty string>",
///             "behavior_digest": "<non-empty string>",
///             "behavior_value": <finite number>}]}
/// ```
library;

import 'patch_algebra.dart' show Tolerance;

/// The two WS-2 engines. [wire] is the frozen `engine` field value.
enum CrossEngine {
  rust('rust'),
  pythonMlxlm('python_mlxlm');

  const CrossEngine(this.wire);

  final String wire;

  /// Parses the frozen wire value; anything else is a NAMED refusal
  /// (`ENGINE_UNKNOWN=<value>`), never a fallback.
  static CrossEngine fromWire(String value) {
    for (final engine in CrossEngine.values) {
      if (engine.wire == value) return engine;
    }
    throw FormatException('MALFORMED_BUNDLE ENGINE_UNKNOWN=$value '
        '(allowed: ${CrossEngine.values.map((e) => e.wire).join(', ')})');
  }
}

/// One frozen G-cell's digest evidence in a [DigestBundle].
///
/// [behaviorValue] is the cell's numeric oracle summary (e.g. loop rate) —
/// the value the pre-registered tolerance compares. The digests key the
/// certification and record bit-equality evidence; see library doc.
final class CellDigest {
  const CellDigest({
    required this.cell,
    required this.logitsDigest,
    required this.behaviorDigest,
    required this.behaviorValue,
  });

  /// Rebuilds from json with the frozen strict key set
  /// `{cell, logits_digest, behavior_digest, behavior_value}`. Every absence,
  /// type drift, or non-finite value throws a NAMED [FormatException]
  /// `MALFORMED_BUNDLE <detail>` carrying the cell [index] context.
  factory CellDigest.fromJson(Map<String, Object?> json, {required int index}) {
    return CellDigest(
      cell: _nonEmptyString(json, 'cell', index),
      logitsDigest: _nonEmptyString(json, 'logits_digest', index),
      behaviorDigest: _nonEmptyString(json, 'behavior_digest', index),
      behaviorValue: _finiteNum(json, 'behavior_value', index),
    );
  }

  final String cell;
  final String logitsDigest;
  final String behaviorDigest;
  final double behaviorValue;

  Map<String, Object?> toJson() => {
        'cell': cell,
        'logits_digest': logitsDigest,
        'behavior_digest': behaviorDigest,
        'behavior_value': behaviorValue,
      };

  static const Set<String> _keys = {
    'behavior_digest',
    'behavior_value',
    'cell',
    'logits_digest',
  };

  static String _nonEmptyString(
      Map<String, Object?> json, String field, int index) {
    final v = _require(json, field, index);
    if (v is! String || v.isEmpty) {
      throw FormatException('MALFORMED_BUNDLE cells[$index] '
          'MALFORMED_FIELD=$field expected=non-empty String '
          'found=${v.runtimeType}');
    }
    return v;
  }

  static double _finiteNum(Map<String, Object?> json, String field, int index) {
    final v = _require(json, field, index);
    if (v is! num || !v.isFinite) {
      throw FormatException('MALFORMED_BUNDLE cells[$index] '
          'MALFORMED_FIELD=$field expected=finite number '
          'found=${v.runtimeType}');
    }
    return v.toDouble();
  }

  static Object? _require(Map<String, Object?> json, String field, int index) {
    if (!json.containsKey(field)) {
      throw FormatException(
          'MALFORMED_BUNDLE cells[$index] MISSING_FIELD=$field');
    }
    return json[field];
  }
}

/// One engine's per-cell digest evidence over the frozen battery.
///
/// Wire shape and refusals: see library doc. Parser refusals are NAMED
/// [FormatException]s prefixed `MALFORMED_BUNDLE`: `MISSING_FIELD=<name>`,
/// `MALFORMED_FIELD=<name>`, `ENGINE_UNKNOWN=<value>`, EMPTY_CELLS,
/// CELL_NOT_OBJECT, `DUPLICATE_CELL=<name>`, and the strict-key-set report
/// `keys mismatch (missing=[...] extra=[...])`.
final class DigestBundle {
  DigestBundle({required this.engine, required List<CellDigest> cells})
      : cells = List.unmodifiable(cells) {
    if (cells.isEmpty) {
      throw const FormatException('MALFORMED_BUNDLE EMPTY_CELLS');
    }
    final seen = <String>{};
    for (final c in cells) {
      if (!seen.add(c.cell)) {
        throw FormatException('MALFORMED_BUNDLE DUPLICATE_CELL=${c.cell}');
      }
    }
  }

  /// Parses the frozen bundle shape (strict top-level key set
  /// `{engine, cells}`).
  factory DigestBundle.fromJson(Map<String, Object?> json) {
    final keys = json.keys.toSet();
    const required = {'cells', 'engine'};
    final missing = required.difference(keys).toList()..sort();
    final extra = keys.difference(required).toList()..sort();
    if (missing.isNotEmpty || extra.isNotEmpty) {
      throw FormatException('MALFORMED_BUNDLE keys mismatch '
          '(missing=$missing extra=$extra)');
    }
    final engineValue = json['engine'];
    if (engineValue is! String) {
      throw FormatException('MALFORMED_BUNDLE MALFORMED_FIELD=engine '
          'expected=String found=${engineValue.runtimeType}');
    }
    final rawCells = json['cells'];
    if (rawCells is! List) {
      throw FormatException('MALFORMED_BUNDLE MALFORMED_FIELD=cells '
          'expected=List found=${rawCells.runtimeType}');
    }
    final cells = <CellDigest>[];
    for (var i = 0; i < rawCells.length; i++) {
      final raw = rawCells[i];
      if (raw is! Map) {
        throw FormatException(
            'MALFORMED_BUNDLE cells[$i] CELL_NOT_OBJECT found=${raw.runtimeType}');
      }
      final cellJson = Map<String, Object?>.from(raw);
      final cellKeys = cellJson.keys.toSet();
      final missingCell = CellDigest._keys.difference(cellKeys).toList()..sort();
      final extraCell = cellKeys.difference(CellDigest._keys).toList()..sort();
      if (missingCell.isNotEmpty || extraCell.isNotEmpty) {
        throw FormatException('MALFORMED_BUNDLE cells[$i] keys mismatch '
            '(missing=$missingCell extra=$extraCell)');
      }
      cells.add(CellDigest.fromJson(cellJson, index: i));
    }
    return DigestBundle(engine: CrossEngine.fromWire(engineValue), cells: cells);
  }

  final CrossEngine engine;
  final List<CellDigest> cells;

  /// Cells keyed by name (constructor guarantees uniqueness).
  Map<String, CellDigest> get cellsByName =>
      {for (final c in cells) c.cell: c};

  Map<String, Object?> toJson() => {
        'engine': engine.wire,
        'cells': [for (final c in cells) c.toJson()],
      };

  @override
  String toString() =>
      'DigestBundle(engine: ${engine.wire}, cells: ${cells.length})';
}

/// The certification verdict union: material agreement ([Agree]), material
/// disagreement listing every offending cell ([Mismatch]), or a NAMED
/// structural refusal ([CertificationRefused]) — never null, never a bool.
sealed class CrossEngineVerdict {
  const CrossEngineVerdict();

  /// Canonical machine label for records and ledger rows.
  String get label;

  /// The frozen record shape shared with `tool/runs/ws2_certify.py`'s JSONL
  /// lines (the script wraps it with `tool` / `created_utc` envelope fields).
  Map<String, Object?> toJson();
}

/// AGREE: every shared cell's behavior value matches within the
/// pre-registered tolerance. [logitsBitwiseEqual] counts the cells whose
/// logits digests are byte-equal across engines — recorded evidence, never a
/// criterion (library doc).
final class Agree extends CrossEngineVerdict {
  const Agree({required this.cellsCompared, required this.logitsBitwiseEqual});

  final int cellsCompared;
  final int logitsBitwiseEqual;

  @override
  String get label => 'AGREE';

  @override
  Map<String, Object?> toJson() => {
        'verdict': label,
        'reference_engine': CrossEngine.pythonMlxlm.wire,
        'candidate_engine': CrossEngine.rust.wire,
        'cells_compared': cellsCompared,
        'logits_bitwise_equal': logitsBitwiseEqual,
        'mismatches': const [],
      };

  @override
  String toString() => 'AGREE cells=$cellsCompared '
      'logits_bitwise_equal=$logitsBitwiseEqual';
}

/// One offending cell, NAMED: [reason] is the frozen vocabulary
/// (BEHAVIOR_DELTA_OUT_OF_TOLERANCE, CELL_MISSING_IN_CANDIDATE,
/// CELL_MISSING_IN_REFERENCE) and [detail] carries the concrete numbers so
/// the disagreement can go straight into a ledger row.
final class CellDisagreement {
  const CellDisagreement({
    required this.cell,
    required this.reason,
    required this.detail,
  });

  final String cell;
  final String reason;
  final String detail;

  Map<String, Object?> toJson() =>
      {'cell': cell, 'reason': reason, 'detail': detail};

  @override
  String toString() => '$reason cell=$cell: $detail';
}

/// MISMATCH: the verdict lists EVERY offending cell (never just the first) —
/// selective reporting is structurally impossible (PROGRAM.md §3).
final class Mismatch extends CrossEngineVerdict {
  Mismatch({required List<CellDisagreement> cells, required this.cellsCompared})
      : cells = List.unmodifiable(cells);

  final List<CellDisagreement> cells;

  /// Shared cells the tolerance was actually evaluated on.
  final int cellsCompared;

  /// The frozen reason vocabulary.
  static const String behaviorDelta = 'BEHAVIOR_DELTA_OUT_OF_TOLERANCE';
  static const String missingInCandidate = 'CELL_MISSING_IN_CANDIDATE';
  static const String missingInReference = 'CELL_MISSING_IN_REFERENCE';

  @override
  String get label => 'MISMATCH';

  @override
  Map<String, Object?> toJson() => {
        'verdict': label,
        'reference_engine': CrossEngine.pythonMlxlm.wire,
        'candidate_engine': CrossEngine.rust.wire,
        'cells_compared': cellsCompared,
        'mismatches': [for (final c in cells) c.toJson()],
      };

  @override
  String toString() =>
      'MISMATCH cells=[${cells.map((c) => '${c.cell}:${c.reason}').join(', ')}]';
}

/// A NAMED structural refusal: the pair itself cannot be certified (today:
/// ENGINE_PAIR_INVALID — the two bundles are not exactly one `python_mlxlm`
/// reference and one `rust` candidate). This is not a disagreement between
/// the engines; it is a caller error, reported as a verdict so it can land in
/// a ledger row.
final class CertificationRefused extends CrossEngineVerdict {
  const CertificationRefused({required this.reason, required this.detail});

  /// The frozen refusal vocabulary.
  static const String enginePairInvalid = 'ENGINE_PAIR_INVALID';

  final String reason;
  final String detail;

  @override
  String get label => 'CERTIFICATION_REFUSED';

  @override
  Map<String, Object?> toJson() => {
        'verdict': label,
        'reason': reason,
        'detail': detail,
      };

  @override
  String toString() => '$label $reason: $detail';
}

/// WS-2 certification: does the Rust engine reproduce the Python reference
/// on the frozen battery, within the pre-registered tolerance?
///
/// Nothing here runs an engine or adopts anything (propose-only law): the
/// digests and numbers arrive as typed [DigestBundle]s produced by the
/// frozen capture harness, and the verdict is data.
final class CrossEngineCertification {
  const CrossEngineCertification._();

  /// Certifies [a] and [b] against each other under the caller-registered
  /// [tolerance] (per-cell absolute delta bound as `Tolerance(abs: bound,
  /// rel: ...)`; the comparison rule is [Tolerance]'s pre-registered
  /// edge-inclusive law).
  ///
  /// Roles come from the `engine` fields, NOT the argument order: the
  /// `python_mlxlm` bundle is the reference, the `rust` bundle the candidate
  /// (Python-first law, library doc). A pair that is not exactly one of each
  /// is a [CertificationRefused] ENGINE_PAIR_INVALID.
  ///
  /// Per shared cell the criterion is
  /// `tolerance.allows(expected: reference.behaviorValue, actual:
  /// candidate.behaviorValue)`; failure is a [CellDisagreement] named
  /// BEHAVIOR_DELTA_OUT_OF_TOLERANCE with the concrete numbers. Cells absent
  /// from one side are named CELL_MISSING_IN_CANDIDATE /
  /// CELL_MISSING_IN_REFERENCE. ALL offending cells are listed; the verdict
  /// is [Agree] only when that list is empty.
  static CrossEngineVerdict certify({
    required DigestBundle a,
    required DigestBundle b,
    required Tolerance tolerance,
  }) {
    final DigestBundle reference;
    final DigestBundle candidate;
    if (a.engine == CrossEngine.pythonMlxlm &&
        b.engine == CrossEngine.rust) {
      reference = a;
      candidate = b;
    } else if (a.engine == CrossEngine.rust &&
        b.engine == CrossEngine.pythonMlxlm) {
      reference = b;
      candidate = a;
    } else {
      return CertificationRefused(
        reason: CertificationRefused.enginePairInvalid,
        detail: 'expected exactly one python_mlxlm reference and one rust '
            'candidate, found engines=[${a.engine.wire}, ${b.engine.wire}] '
            '(Python-first law: rust must match python_mlxlm, never the '
            'reverse)',
      );
    }

    final candidateCells = candidate.cellsByName;
    final referenceCells = reference.cellsByName;
    final disagreements = <CellDisagreement>[];
    var compared = 0;
    var logitsBitwiseEqual = 0;

    for (final refCell in reference.cells) {
      final candCell = candidateCells[refCell.cell];
      if (candCell == null) {
        disagreements.add(CellDisagreement(
          cell: refCell.cell,
          reason: Mismatch.missingInCandidate,
          detail: 'cell present in reference (python_mlxlm) but absent from '
              'candidate (rust)',
        ));
        continue;
      }
      compared++;
      if (refCell.logitsDigest == candCell.logitsDigest) logitsBitwiseEqual++;
      if (!tolerance.allows(refCell.behaviorValue, candCell.behaviorValue)) {
        final delta =
            (candCell.behaviorValue - refCell.behaviorValue).abs();
        disagreements.add(CellDisagreement(
          cell: refCell.cell,
          reason: Mismatch.behaviorDelta,
          detail: 'expected(python_mlxlm)=${refCell.behaviorValue} '
              'actual(rust)=${candCell.behaviorValue} delta=$delta '
              'tolerance abs=${tolerance.abs} rel=${tolerance.rel}',
        ));
      }
    }
    for (final candCell in candidate.cells) {
      if (!referenceCells.containsKey(candCell.cell)) {
        disagreements.add(CellDisagreement(
          cell: candCell.cell,
          reason: Mismatch.missingInReference,
          detail: 'cell present in candidate (rust) but absent from '
              'reference (python_mlxlm)',
        ));
      }
    }

    if (disagreements.isEmpty) {
      return Agree(
          cellsCompared: compared, logitsBitwiseEqual: logitsBitwiseEqual);
    }
    return Mismatch(cells: disagreements, cellsCompared: compared);
  }
}
