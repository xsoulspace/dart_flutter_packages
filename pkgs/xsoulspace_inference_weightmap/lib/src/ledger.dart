/// Append-only hash-chained jsonl journal: the denominator ledger.
///
/// Implements PROGRAM.md §3 (denominator journal; ADR 0032
/// predicted-versus-observed): every proposed direction, every run, and every
/// named failure appends a row, so headline claims always carry their
/// denominator ("3 wins of 400 attempts") and selective reporting is
/// structurally impossible. Durable evidence is textual (house probe-scratch
/// law): the ledger is jsonl, never a binary capture.
///
/// CHAIN LAW (frozen): each row's `digest` is
/// `sha256(prevDigest + canonicalJson({seq, ts, kind, payload}))` — the digest
/// field cannot sign itself, so the signed content is the row minus `digest`,
/// with the previous row's digest prepended as a raw hex string. The genesis
/// row's `prevDigest` is 64 zeros ([genesisPrevDigest]). [canonicalJson] is
/// recursive key-sorted, whitespace-free JSON, so the digest is stable across
/// encoders and key insertion orders.
///
/// Verification re-encodes the DECODED row canonically; whitespace-only
/// reformatting of a line is therefore invisible by design, and any CONTENT
/// change is caught as a named `CHAIN_BROKEN_AT=<index>` verdict.
///
/// Single-writer assumption (house law: one authoritative writer). No
/// cross-process locking is attempted; concurrent appends are out of contract.
library;

import 'dart:convert';
import 'dart:io';

// sha256 is the chain primitive. `crypto` resolves through the pub workspace;
// the frozen pubspec declares it only as a dev_dependency, so this lib/ import
// carries a NAMED suppression until pubspec ownership promotes it.
import 'package:crypto/crypto.dart';

/// `prevDigest` of the genesis row: 64 zeros (named, not empty — an empty
/// string would make "no previous row" indistinguishable from a parse gap).
final String genesisPrevDigest = '0' * 64;

/// Canonical JSON: recursively sorted object keys, no whitespace, lists in
/// order. This is the exact pre-image the chain law digests.
///
/// Throws named [ArgumentError]s for material JSON cannot carry
/// (NON_STRING_KEY, NON_CANONICALIZABLE); NaN/infinity fail loudly inside
/// [jsonEncode], as canonical JSON has no representation for them.
String canonicalJson(Object? value) => jsonEncode(_canonicalize(value));

Object? _canonicalize(Object? value) {
  if (value == null || value is bool || value is num || value is String) {
    return value;
  }
  if (value is Map) {
    final keys = <String>[];
    for (final k in value.keys) {
      if (k is! String) {
        throw ArgumentError.value(k, 'key', 'NON_STRING_KEY');
      }
      keys.add(k);
    }
    keys.sort();
    return {for (final k in keys) k: _canonicalize(value[k])};
  }
  if (value is List) {
    return [for (final e in value) _canonicalize(e)];
  }
  throw ArgumentError.value(value, 'value', 'NON_CANONICALIZABLE');
}

/// A malformed ledger line: named, with the 0-based line [index] so the
/// failure can go straight into a verdict without re-scanning.
final class LedgerFormatException implements Exception {
  const LedgerFormatException(this.index, this.detail);

  final int index;
  final String detail;

  @override
  String toString() => 'MALFORMED_ROW_AT=$index: $detail';
}

/// One journal row. [seq] is the 0-based position; [ts] is informational UTC
/// wall clock (integrity rests on seq + digests, not the clock); [payload] is
/// arbitrary canonical-JSON-able content.
final class LedgerRow {
  const LedgerRow({
    required this.seq,
    required this.ts,
    required this.kind,
    required this.payload,
    required this.prevDigest,
    required this.digest,
  });

  /// Rebuilds a row from decoded json, validating every field with a NAMED
  /// [LedgerFormatException] on absence or type drift.
  factory LedgerRow.fromJson(Map<String, Object?> json, {required int index}) {
    return LedgerRow(
      seq: _intField(json, 'seq', index),
      ts: _stringField(json, 'ts', index),
      kind: _stringField(json, 'kind', index),
      payload: _payloadField(json, index),
      prevDigest: _stringField(json, 'prevDigest', index),
      digest: _stringField(json, 'digest', index),
    );
  }

  final int seq;
  final String ts;
  final String kind;
  final Map<String, Object?> payload;
  final String prevDigest;
  final String digest;

  Map<String, Object?> toJson() => {
    'seq': seq,
    'ts': ts,
    'kind': kind,
    'payload': payload,
    'prevDigest': prevDigest,
    'digest': digest,
  };

  /// The frozen chain-law digest (see library doc).
  static String computeDigest({
    required String prevDigest,
    required int seq,
    required String ts,
    required String kind,
    required Map<String, Object?> payload,
  }) => sha256
      .convert(
        utf8.encode(
          prevDigest +
              canonicalJson({
                'seq': seq,
                'ts': ts,
                'kind': kind,
                'payload': payload,
              }),
        ),
      )
      .toString();

  static int _intField(Map<String, Object?> json, String field, int index) {
    final v = _require(json, field, index);
    if (v is! int) {
      throw LedgerFormatException(
        index,
        'MALFORMED_FIELD=$field expected=int found=${v.runtimeType}',
      );
    }
    return v;
  }

  static String _stringField(
    Map<String, Object?> json,
    String field,
    int index,
  ) {
    final v = _require(json, field, index);
    if (v is! String) {
      throw LedgerFormatException(
        index,
        'MALFORMED_FIELD=$field expected=String found=${v.runtimeType}',
      );
    }
    return v;
  }

  static Map<String, Object?> _payloadField(
    Map<String, Object?> json,
    int index,
  ) {
    final v = _require(json, 'payload', index);
    if (v is! Map) {
      throw LedgerFormatException(
        index,
        'MALFORMED_FIELD=payload expected=Map found=${v.runtimeType}',
      );
    }
    return Map<String, Object?>.from(v);
  }

  static Object? _require(Map<String, Object?> json, String field, int index) {
    if (!json.containsKey(field)) {
      throw LedgerFormatException(index, 'MISSING_FIELD=$field');
    }
    return json[field];
  }
}

/// Appends one row and returns it. Creates the file (and parents) on first
/// append; the genesis row links to [genesisPrevDigest].
///
/// [payload] must be canonical-JSON-able (see [canonicalJson]); unsupported
/// values throw a named ArgumentError BEFORE anything is written, so a failed
/// append never leaves a half row.
LedgerRow append(File file, String kind, Map<String, Object?> payload) {
  final rows = file.existsSync() ? readAll(file) : const <LedgerRow>[];
  final seq = rows.length;
  final prevDigest = rows.isEmpty ? genesisPrevDigest : rows.last.digest;
  final ts = DateTime.now().toUtc().toIso8601String();
  final digest = LedgerRow.computeDigest(
    prevDigest: prevDigest,
    seq: seq,
    ts: ts,
    kind: kind,
    payload: payload,
  );
  final row = LedgerRow(
    seq: seq,
    ts: ts,
    kind: kind,
    payload: payload,
    prevDigest: prevDigest,
    digest: digest,
  );
  // Canonicalize (and thereby validate) before touching the filesystem.
  final line = canonicalJson(row.toJson());
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
  return row;
}

/// Reads every row, validating wire format. A missing file throws dart:io's
/// named [FileSystemException] (absence of a ledger is not an empty ledger);
/// an empty file yields `[]`. Malformed lines throw [LedgerFormatException]
/// naming the 0-based line index.
List<LedgerRow> readAll(File file) {
  final text = file.readAsStringSync();
  if (text.isEmpty) return const [];
  final lines = text.split('\n');
  if (lines.last.isEmpty) lines.removeLast(); // tolerate the trailing newline
  final rows = <LedgerRow>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) {
      throw LedgerFormatException(i, 'EMPTY_LINE');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException catch (e) {
      throw LedgerFormatException(i, 'INVALID_JSON ${e.message}');
    }
    if (decoded is! Map) {
      throw LedgerFormatException(
        i,
        'ROW_NOT_OBJECT found=${decoded.runtimeType}',
      );
    }
    rows.add(
      LedgerRow.fromJson(Map<String, Object?>.from(decoded), index: i),
    );
  }
  return rows;
}

/// Chain-verdict union: intact, or broken AT a named 0-based row index.
sealed class ChainVerdict {
  const ChainVerdict();

  /// Canonical machine label for ledgers and receipts.
  String get label;
}

/// The chain recomputed cleanly over [rows] rows (0 = empty ledger, which
/// verifies by law).
final class ChainIntact extends ChainVerdict {
  const ChainIntact(this.rows);

  final int rows;

  @override
  String get label => 'CHAIN_INTACT';

  @override
  String toString() => '$label rows=$rows';
}

/// The first broken row, named: [index] plus the [cause] vocabulary
/// (MALFORMED_ROW, SEQ_GAP, PREV_LINK_MISMATCH, DIGEST_MISMATCH).
final class ChainBroken extends ChainVerdict {
  const ChainBroken({required this.index, required this.cause});

  final int index;
  final String cause;

  @override
  String get label => 'CHAIN_BROKEN_AT=$index';

  @override
  String toString() => '$label cause=$cause';
}

/// Recomputes the whole chain and returns the FIRST break as a named verdict,
/// never a bool: a clean `false` cannot say where or why. Checks per row:
/// wire format (MALFORMED_ROW), `seq == index` (SEQ_GAP), `prevDigest` linkage
/// (PREV_LINK_MISMATCH), and the frozen digest law (DIGEST_MISMATCH).
ChainVerdict verifyChain(File file) {
  final List<LedgerRow> rows;
  try {
    rows = readAll(file);
  } on LedgerFormatException catch (e) {
    return ChainBroken(index: e.index, cause: 'MALFORMED_ROW ${e.detail}');
  }
  var expectedPrev = genesisPrevDigest;
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    if (row.seq != i) {
      return ChainBroken(
        index: i,
        cause: 'SEQ_GAP expected=$i found=${row.seq}',
      );
    }
    if (row.prevDigest != expectedPrev) {
      return ChainBroken(
        index: i,
        cause: 'PREV_LINK_MISMATCH expected=$expectedPrev '
            'found=${row.prevDigest}',
      );
    }
    final recomputed = LedgerRow.computeDigest(
      prevDigest: row.prevDigest,
      seq: row.seq,
      ts: row.ts,
      kind: row.kind,
      payload: row.payload,
    );
    if (recomputed != row.digest) {
      return ChainBroken(
        index: i,
        cause: 'DIGEST_MISMATCH expected=$recomputed found=${row.digest}',
      );
    }
    expectedPrev = row.digest;
  }
  return ChainIntact(rows.length);
}

/// Row counts by kind — the denominator counters that make selective
/// reporting structurally impossible (PROGRAM.md §3).
Map<String, int> denominators(File file) {
  final counts = <String, int>{};
  for (final row in readAll(file)) {
    counts[row.kind] = (counts[row.kind] ?? 0) + 1;
  }
  return counts;
}
