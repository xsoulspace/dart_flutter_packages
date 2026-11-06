/// WS-1 bridge: the sidecar delta format <-> typed patch algebra, and the
/// replay record that ties a ledger `edit` row to a mirror receipt.
///
/// This is the Phase-B glue (PROGRAM.md: "the edit is a typed artifact"). The
/// A3 arm writes edits as SIDECAR artifacts via `tool/eval/apply_delta.py`
/// (spec shape `{tensor, columns, direction, scale}`; the base checkpoint is
/// never mutated). The patch algebra (`patch_algebra.dart`) is the typed
/// contract core. This module converts between the two WITHOUT ever adopting
/// anything: [sidecarDeltaToPatch] and [patchToSidecarSpec] are pure
/// proposals, and [ReplayReceipt] only reports whether committed digests
/// still agree.
///
/// Conversion laws (errors are NAMED, never silent):
///
/// - **Frozen spec shape**: the sidecar spec key set is EXACTLY
///   `{tensor, columns, direction, scale}` — the same frozen shape
///   `apply_delta.py` enforces, with the same `SPEC_SHAPE_MISMATCH`
///   vocabulary and detail strings, so a spec that one side accepts the other
///   accepts too. Non-finite values are caught downstream by [DeltaSpec]'s
///   own named refusals (NON_FINITE_DELTA, NON_FINITE_SCALE).
/// - **Rank-1, column-window encoding**: a spec's delta is `scale *
///   direction` written into each chosen column. The patch address window is
///   the minimal FULL-ROW column span `[min(columns), max(columns) + 1)`;
///   inside that span, unchosen columns carry an exact `0.0` in the single
///   direction vector, so materialization adds `+0.0` there (bit-identity
///   except the IEEE sign normalization `-0.0 + 0.0 = +0.0`, documented, not
///   silently absorbed). Rank and scale stay SEPARATE fields — the raw
///   direction lives in the vector, [DeltaSpec.scale] carries the spec scale
///   unchanged.
/// - **Round-trip stability within [Tolerance.exact] for representable
///   values**: `patchToSidecarSpec(sidecarDeltaToPatch(spec))` returns the
///   spec's canonical form — columns sorted ascending, numbers as doubles
///   (JSON ints round-trip as numerically equal doubles) — bit-for-bit.
///   NOT representable (named refusals, never a lossy guess): rank != 1
///   (SIDECAR_RANK_UNREPRESENTABLE), bounded row windows
///   (SIDECAR_ROW_WINDOW_UNREPRESENTABLE), unbounded column windows
///   (SIDECAR_COL_WINDOW_UNBOUNDED), non-rectangular vector length
///   (SIDECAR_WINDOW_AREA_MISMATCH), chosen columns whose direction slices
///   differ (SIDECAR_COLUMN_DRIFT), and an all-zero direction
///   (SIDECAR_ZERO_DELTA — a zero edit cannot name its columns, because the
///   encoding recovers columns as the nonzero slices of the vector).
/// - **Preconditions carry the base fingerprint**: the converted entry's
///   [PatchEntry.expectedOldFingerprint] IS the caller-supplied
///   `baseFingerprint`, and it is ALSO carried as the named precondition
///   `BASE_FINGERPRINT=<fp>`, so a harness can check provenance before it
///   ever calls `apply`. A stale fingerprint therefore refuses at the
///   algebra with the existing NAMED STALE_PRECONDITION — the bridge adds no
///   new apply semantics.
/// - **Replay is a report, not an adoption** (propose-only law): the WS-1
///   replay record `{patch_digest, mirror_digest, battery_digest,
///   reproduced}` compares the ledger row's COMMITTED digests against what
///   the replay recomputes/observes. Digest disagreement is the measured
///   outcome `reproduced: false` with the NAMED refusal REPLAY_DIGEST_DRIFT
///   (detail names the drifted pair: PATCH_COMMITMENT and/or MIRROR_RECEIPT);
///   structural problems (wrong row kind, missing payload fields) are named
///   ArgumentError/FormatException, mirroring `ledger.dart` /
///   `receipts.dart` vocabulary.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'ledger.dart' show LedgerRow, canonicalJson;
import 'patch_algebra.dart';

/// The frozen sidecar spec key set (`apply_delta.py` REQUIRED_KEYS).
const Set<String> sidecarSpecKeys = {'columns', 'direction', 'scale', 'tensor'};

/// Default [TensorAddress.directionId] for bridge-converted sidecar patches.
const String sidecarDirectionId = 'sidecar';

/// The named precondition token carrying the base fingerprint.
String baseFingerprintPrecondition(String fingerprint) =>
    'BASE_FINGERPRINT=$fingerprint';

/// Returns the named shape problems of a sidecar [spec]; empty = valid.
///
/// Deliberately mirrors `apply_delta.py`'s `spec_shape_problems` detail
/// strings, so the Dart and Python sides refuse the same specs for the same
/// named reasons. Unlike the Python real run, there is no tensor header here
/// to check `direction` length or column range against — those remain
/// apply-time SHAPE_MISMATCH refusals in the algebra.
List<String> sidecarSpecProblems(Map<String, Object?> spec) {
  final problems = <String>[];
  final keys = spec.keys.toSet();
  final missing = sidecarSpecKeys.difference(keys).toList()..sort();
  final extra = keys.difference(sidecarSpecKeys).toList()..sort();
  if (missing.isNotEmpty || extra.isNotEmpty) {
    problems.add('keys mismatch (missing=$missing extra=$extra)');
  }
  final tensor = spec['tensor'];
  if (tensor is! String || tensor.isEmpty) {
    problems.add('tensor must be a non-empty string');
  }
  final columns = spec['columns'];
  if (columns is! List || columns.isEmpty || columns.any((c) => c is! int)) {
    problems.add('columns must be a non-empty list of ints');
  } else {
    if (columns.toSet().length != columns.length) {
      problems.add('columns contain duplicate indices');
    }
    if (columns.any((c) => (c as int) < 0)) {
      problems.add('columns contain negative indices');
    }
  }
  final direction = spec['direction'];
  if (direction is! List ||
      direction.isEmpty ||
      direction.any((d) => d is! num)) {
    problems.add('direction must be a non-empty list of numbers');
  }
  if (spec['scale'] is! num) {
    problems.add('scale must be a number');
  }
  return problems;
}

/// Validates [spec] or throws a named ArgumentError `SPEC_SHAPE_MISMATCH`
/// listing ALL problems (same vocabulary as `apply_delta.py`).
void validateSidecarSpec(Map<String, Object?> spec) {
  final problems = sidecarSpecProblems(spec);
  if (problems.isNotEmpty) {
    throw ArgumentError.value(spec, 'spec',
        'SPEC_SHAPE_MISMATCH ${problems.join('; ')}');
  }
}

/// Converts a frozen sidecar delta [spec] (`{tensor, columns, direction,
/// scale}`, see `tool/eval/apply_delta.py`) into a rank-1 [PatchEntry].
///
/// The address window is the columns: full rows, half-open column span
/// `[min(columns), max(columns) + 1)`. The single direction vector covers
/// that window row-major; a chosen column offset carries `direction[row]`,
/// an unchosen one carries exact `0.0` (see library doc). [baseFingerprint]
/// — the fingerprint the proposer observed on the ACTUAL base — becomes both
/// [PatchEntry.expectedOldFingerprint] and the named precondition
/// `BASE_FINGERPRINT=<fp>`; applying against a base whose fingerprint moved
/// refuses with the algebra's NAMED STALE_PRECONDITION.
///
/// [PatchEntry.expectedNewFingerprint] stays null: nobody has observed the
/// post state, and committing an unobserved fingerprint would be a lie
/// (algebra law).
///
/// Refusals: `SPEC_SHAPE_MISMATCH` (named [ArgumentError], all problems
/// listed), plus [DeltaSpec]'s NON_FINITE_DELTA / NON_FINITE_SCALE and
/// [PatchEntry]'s EMPTY_FINGERPRINT / EMPTY_TENSOR_NAME for material the
/// shape check cannot see.
PatchEntry sidecarDeltaToPatch(
  Map<String, Object?> spec, {
  required String baseFingerprint,
  String directionId = sidecarDirectionId,
}) {
  validateSidecarSpec(spec);
  final tensor = spec['tensor']! as String;
  final columns = (spec['columns']! as List).cast<int>();
  final direction = [
    for (final d in spec['direction']! as List) (d as num).toDouble(),
  ];
  final scale = (spec['scale']! as num).toDouble();

  final minCol = columns.reduce((a, b) => a < b ? a : b);
  final maxCol = columns.reduce((a, b) => a > b ? a : b);
  final chosen = columns.toSet();
  final width = maxCol - minCol + 1;
  final rows = direction.length;

  // Row-major over the window: vector[row * width + (col - minCol)].
  final vector = List<double>.filled(rows * width, 0.0);
  for (var row = 0; row < rows; row++) {
    for (final col in chosen) {
      vector[row * width + (col - minCol)] = direction[row];
    }
  }

  return PatchEntry(
    address: TensorAddress(
      tensor: tensor,
      directionId: directionId,
      colStart: minCol,
      colEnd: maxCol + 1,
    ),
    expectedOldFingerprint: baseFingerprint,
    delta: DeltaSpec(rank: 1, vectors: [vector], scale: scale),
    preconditions: [baseFingerprintPrecondition(baseFingerprint)],
  );
}

/// Converts a rank-1 column-window [PatchEntry] back into the frozen sidecar
/// spec map `{tensor, columns, direction, scale}` — the exact
/// `apply_delta.py` shape (strict key set, sorted canonical columns).
///
/// Recovery rules (all refusals are named [ArgumentError]s; see library doc
/// for the full vocabulary): the entry must be rank 1 over a full-row window
/// with explicit column bounds; `columns` are the window offsets whose
/// direction slice is not all-zero; every recovered column must carry the
/// SAME slice (SIDECAR_COLUMN_DRIFT otherwise — one direction per spec is
/// the frozen format); `direction` is that shared slice; `scale` is
/// [DeltaSpec.scale] unchanged. The round trip is bit-exact ([Tolerance.exact]
/// stability) for every representable spec: `patchToSidecarSpec(
/// sidecarDeltaToPatch(spec, baseFingerprint: fp))` equals the canonical
/// form of `spec` — columns sorted, numbers as doubles (a JSON int
/// round-trips as a numerically equal double).
Map<String, Object?> patchToSidecarSpec(PatchEntry entry) {
  if (entry.delta.rank != 1) {
    throw ArgumentError.value(entry.delta.rank, 'entry.delta.rank',
        'SIDECAR_RANK_UNREPRESENTABLE (sidecar spec carries one direction)');
  }
  final address = entry.address;
  if (address.rowStart != null || address.rowEnd != null) {
    throw ArgumentError.value(
        address.description,
        'entry.address',
        'SIDECAR_ROW_WINDOW_UNREPRESENTABLE rowStart=${address.rowStart} '
            'rowEnd=${address.rowEnd} (sidecar direction spans all rows)');
  }
  final colStart = address.colStart;
  final colEnd = address.colEnd;
  if (colStart == null || colEnd == null) {
    throw ArgumentError.value(address.description, 'entry.address',
        'SIDECAR_COL_WINDOW_UNBOUNDED colStart=$colStart colEnd=$colEnd '
        '(sidecar columns are explicit indices)');
  }
  final width = colEnd - colStart;
  final vector = entry.delta.vectors.single;
  if (width < 1 || vector.length % width != 0) {
    throw ArgumentError('SIDECAR_WINDOW_AREA_MISMATCH vector=${vector.length} '
        'width=$width (vector length must be rows * width)');
  }
  final rows = vector.length ~/ width;

  List<double> sliceAt(int offset) => [
        for (var row = 0; row < rows; row++) vector[row * width + offset],
      ];

  final columns = <int>[];
  List<double>? direction;
  for (var offset = 0; offset < width; offset++) {
    final slice = sliceAt(offset);
    final nonzero = slice.any((v) => v != 0.0);
    if (!nonzero) continue;
    if (direction == null) {
      direction = slice;
      columns.add(colStart + offset);
      continue;
    }
    // Exact equality is the frozen rule (Tolerance.exact): a spec has ONE
    // direction; slices that differ are not sidecar-representable.
    for (var row = 0; row < rows; row++) {
      if (!Tolerance.exact.allows(direction[row], slice[row])) {
        throw ArgumentError('SIDECAR_COLUMN_DRIFT col=${colStart + offset} '
            'first=${columns.first} row=$row '
            'expected=${direction[row]} found=${slice[row]}');
      }
    }
    columns.add(colStart + offset);
  }
  if (columns.isEmpty || direction == null) {
    throw ArgumentError.value(address.description, 'entry.address',
        'SIDECAR_ZERO_DELTA (an all-zero direction cannot name its columns; '
        'a zero edit is not a representable sidecar spec)');
  }
  return {
    'tensor': address.tensor,
    'columns': List<int>.unmodifiable(columns),
    'direction': List<double>.unmodifiable(direction),
    'scale': entry.delta.scale,
  };
}

/// The canonical digest of a sidecar patch spec: sha256 over its
/// [canonicalJson] encoding. This is the commitment recorded in a ledger
/// `edit` row's `patch_digest` and recomputed at replay time.
String patchDigestOf(Map<String, Object?> patch) =>
    sha256.convert(utf8.encode(canonicalJson(patch))).toString();

/// Builds the frozen payload of a ledger `kind == 'edit'` row that
/// [ReplayReceipt.replay] consumes:
///
/// ```json
/// {"patch": <sidecar spec>, "patch_digest": <sha256 of canonicalJson(patch)>,
///  "mirror_digest": <digest observed on the mirror receipt at edit time>,
///  "battery_digest": <frozen battery the edit is certified against>}
/// ```
///
/// The [patch] spec is validated ([validateSidecarSpec]) BEFORE the payload
/// is built, so a malformed edit never reaches the chain; digests must be
/// non-empty (named ArgumentError otherwise). The caller appends the payload
/// through `ledger.dart`'s [append] — this module never writes.
Map<String, Object?> editRowPayload({
  required Map<String, Object?> patch,
  required String mirrorDigest,
  required String batteryDigest,
}) {
  validateSidecarSpec(patch);
  if (mirrorDigest.isEmpty) {
    throw ArgumentError.value(mirrorDigest, 'mirrorDigest', 'EMPTY_DIGEST');
  }
  if (batteryDigest.isEmpty) {
    throw ArgumentError.value(batteryDigest, 'batteryDigest', 'EMPTY_DIGEST');
  }
  return {
    'patch': patch,
    'patch_digest': patchDigestOf(patch),
    'mirror_digest': mirrorDigest,
    'battery_digest': batteryDigest,
  };
}

/// The WS-1 replay record: proof-of-agreement between a ledger `edit` row's
/// committed digests and what a replay actually recomputes/observes.
///
/// Fields follow the frozen record shape `{patch_digest, mirror_digest,
/// battery_digest, reproduced}` (wire keys snake_case, see [toJson]):
///
/// - [patchDigest] — RECOMPUTED from the row's `payload.patch` at replay
///   time (never trusted from the row alone).
/// - [mirrorDigest] — the LIVE mirror receipt digest the replay observed
///   (the required argument to [ReplayReceipt.replay]).
/// - [batteryDigest] — carried from the row's committed payload.
/// - [reproduced] — true iff BOTH commitments hold: the recomputed patch
///   digest equals the row's recorded `patch_digest` (PATCH_COMMITMENT) and
///   the live mirror digest equals the row's recorded `mirror_digest`
///   (MIRROR_RECEIPT).
///
/// When a commitment breaks, the receipt is still produced — drift is the
/// measured outcome, not a tool failure — with `reproduced: false` and the
/// NAMED refusal [refusal]: `REPLAY_DIGEST_DRIFT` followed by
/// `PATCH_COMMITMENT recorded=<x> recomputed=<y>` and/or
/// `MIRROR_RECEIPT recorded=<x> live=<y>` — listing EVERY drifted pair,
/// never just the first. Structural
/// problems refuse loudly instead: a row whose kind is not `edit` throws a
/// named ArgumentError (REPLAY_ROW_KIND_MISMATCH), and missing/mistyped
/// payload fields throw FormatException with the `receipts.dart` vocabulary
/// (`MISSING_FIELD=<name>` / `MALFORMED_FIELD=<name>`).
final class ReplayReceipt {
  const ReplayReceipt({
    required this.patchDigest,
    required this.mirrorDigest,
    required this.batteryDigest,
    required this.reproduced,
    this.refusal,
  });

  /// The frozen refusal label for digest disagreement.
  static const String digestDrift = 'REPLAY_DIGEST_DRIFT';

  /// The ledger row kind this receipt replays.
  static const String editRowKind = 'edit';

  /// Recomputes the replay record for an `edit` [row] against the LIVE
  /// [mirrorDigest] observed on the mirror receipt. See class doc for the
  /// contract and the named refusals.
  factory ReplayReceipt.replay(
    LedgerRow row, {
    required String mirrorDigest,
  }) {
    if (row.kind != editRowKind) {
      throw ArgumentError.value(row.kind, 'row.kind',
          'REPLAY_ROW_KIND_MISMATCH expected=$editRowKind');
    }
    if (mirrorDigest.isEmpty) {
      throw ArgumentError.value(
          mirrorDigest, 'mirrorDigest', 'EMPTY_MIRROR_DIGEST');
    }
    final payload = row.payload;
    final patch = _payloadMap(payload, 'patch');
    final recordedPatchDigest = _payloadString(payload, 'patch_digest');
    final recordedMirrorDigest = _payloadString(payload, 'mirror_digest');
    final batteryDigest = _payloadString(payload, 'battery_digest');

    final recomputedPatchDigest = patchDigestOf(patch);
    final drift = <String>[];
    if (recomputedPatchDigest != recordedPatchDigest) {
      drift.add('PATCH_COMMITMENT recorded=$recordedPatchDigest '
          'recomputed=$recomputedPatchDigest');
    }
    if (mirrorDigest != recordedMirrorDigest) {
      drift.add(
          'MIRROR_RECEIPT recorded=$recordedMirrorDigest live=$mirrorDigest');
    }
    return ReplayReceipt(
      patchDigest: recomputedPatchDigest,
      mirrorDigest: mirrorDigest,
      batteryDigest: batteryDigest,
      reproduced: drift.isEmpty,
      refusal: drift.isEmpty ? null : '$digestDrift ${drift.join('; ')}',
    );
  }

  final String patchDigest;
  final String mirrorDigest;
  final String batteryDigest;
  final bool reproduced;

  /// The NAMED refusal; non-null exactly when [reproduced] is false.
  final String? refusal;

  /// The frozen record shape (snake_case wire keys). `refusal` is present
  /// only on drift — an agreeing replay carries no refusal field.
  Map<String, Object?> toJson() => {
        'patch_digest': patchDigest,
        'mirror_digest': mirrorDigest,
        'battery_digest': batteryDigest,
        'reproduced': reproduced,
        if (refusal != null) 'refusal': refusal,
      };

  @override
  String toString() => 'ReplayReceipt(reproduced: $reproduced'
      '${refusal == null ? '' : ', refusal: $refusal'})';

  static Object? _requireField(Map<String, Object?> payload, String field) {
    if (!payload.containsKey(field)) {
      throw FormatException('MISSING_FIELD=$field');
    }
    return payload[field];
  }

  static String _payloadString(Map<String, Object?> payload, String field) {
    final v = _requireField(payload, field);
    if (v is! String) {
      throw FormatException(
          'MALFORMED_FIELD=$field expected=String found=${v.runtimeType}');
    }
    return v;
  }

  static Map<String, Object?> _payloadMap(
      Map<String, Object?> payload, String field) {
    final v = _requireField(payload, field);
    if (v is! Map) {
      throw FormatException(
          'MALFORMED_FIELD=$field expected=Map found=${v.runtimeType}');
    }
    return Map<String, Object?>.from(v);
  }
}
