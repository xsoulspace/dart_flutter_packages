/// Edit-contract core: the continuous-tensor patch algebra.
///
/// Ported from `~/xs/pattern`'s patch algebra (`crates/pm-core/src/patch.rs`:
/// `diff` / `apply` / named `ConflictReason`s / overlap-refuse-before-mutation)
/// and its propose-only discipline (pattern exp 0007 / ADR 0018; PROGRAM.md
/// §0), adapted from discrete JSON-shaped values to continuous Float64 weight
/// tensors.
///
/// Laws implemented here (errors are NAMED, never silent):
///
/// - **Oracle boundary** (pattern law: "numbers live in the oracle, never in
///   semantics"): comparison slack is typed [Tolerance] data supplied by the
///   caller at the apply site. The only default is [Tolerance.exact], which
///   registers *zero* slack rather than inventing an epsilon.
/// - **Propose-only** (PROGRAM.md §0): [diff] and [inverse] propose; nothing
///   here adopts. [apply] materializes a proposal only against the
///   caller-supplied fingerprint of the actual base, and every refusal is a
///   named [Conflict] (STALE_PRECONDITION, SHAPE_MISMATCH, OVERLAP), never an
///   exception and never a silent no-op.
/// - **Overlap is a refuse, not a warning** (PROGRAM.md §3, three disjoint
///   probe sets): [applyAll] refuses intersecting windows before any mutation.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

// sha256 is the fingerprint primitive. `crypto` resolves through the pub
// workspace; the frozen pubspec declares it only as a dev_dependency, so this
// lib/ import carries a NAMED suppression until pubspec ownership promotes it.
import 'package:crypto/crypto.dart';

/// A row-major Float64 tensor of [rows] x [cols] weight values.
///
/// The algebra's base material. Values must be finite: a NaN or infinity in a
/// weight tensor is a bug in the producing pipeline, and this class refuses it
/// loudly at [set]/construction time instead of propagating it silently.
final class Tensor {
  factory Tensor(int rows, int cols) {
    if (rows < 1 || cols < 1) {
      throw ArgumentError('INVALID_SHAPE rows=$rows cols=$cols (both >= 1)');
    }
    return Tensor._(rows, cols, Float64List(rows * cols));
  }

  /// Builds a tensor from row-major [source] rows (must be rectangular).
  factory Tensor.fromRows(List<List<double>> source) {
    if (source.isEmpty || source.first.isEmpty) {
      throw ArgumentError.value(source, 'source', 'EMPTY_TENSOR');
    }
    final rows = source.length;
    final cols = source.first.length;
    final data = Float64List(rows * cols);
    for (var r = 0; r < rows; r++) {
      if (source[r].length != cols) {
        throw ArgumentError.value(
          source[r],
          'source[$r]',
          'RAGGED_ROWS expected=$cols found=${source[r].length}',
        );
      }
      for (var c = 0; c < cols; c++) {
        final v = source[r][c];
        if (!v.isFinite) {
          throw ArgumentError.value(v, 'source[$r][$c]', 'NON_FINITE_VALUE');
        }
        data[r * cols + c] = v;
      }
    }
    return Tensor._(rows, cols, data);
  }

  const Tensor._(this.rows, this.cols, this.data);

  final int rows;
  final int cols;

  /// Row-major backing storage. Exposed for canonical iteration; mutate only
  /// through [set] so the finiteness invariant holds.
  final Float64List data;

  int get elementCount => rows * cols;

  double get(int row, int col) => data[_offset(row, col)];

  void set(int row, int col, double value) {
    if (!value.isFinite) {
      throw ArgumentError.value(
        value,
        'value',
        'NON_FINITE_VALUE row=$row col=$col',
      );
    }
    data[_offset(row, col)] = value;
  }

  int _offset(int row, int col) {
    if (row < 0 || row >= rows) {
      throw RangeError.range(row, 0, rows - 1, 'row');
    }
    if (col < 0 || col >= cols) {
      throw RangeError.range(col, 0, cols - 1, 'col');
    }
    return row * cols + col;
  }

  Tensor clone() => Tensor._(rows, cols, Float64List.fromList(data));
}

/// Typed ORACLE-BOUNDARY data: how much numeric slack a comparison may take.
///
/// Implements the pattern law "numbers live in the oracle, never in
/// semantics": a tolerance is always passed in from the frozen oracle/harness
/// side, never invented as a default inside the algebra. The single default,
/// [Tolerance.exact], registers zero slack (the absence of tolerance, not a
/// chosen epsilon).
///
/// PRE-REGISTERED COMPARISON RULE (frozen here, exercised at the edge by
/// `test/patch_algebra_test.dart`): two values are equal within tolerance iff
///
/// ```text
/// |actual - expected| <= max(abs, rel * max(|expected|, |actual|))
/// ```
///
/// The edge is INCLUSIVE (`<=`): a delta exactly at the registered boundary
/// passes, one float step beyond it fails. NaN never passes (comparisons with
/// NaN are false by IEEE rule, which is the loud behavior we want).
final class Tolerance {
  /// Validates unconditionally (not only under asserts): slack must be a
  /// finite, non-negative number. A named [ArgumentError] beats a silently
  /// infinite tolerance that would pass every comparison.
  factory Tolerance({required double abs, required double rel}) {
    if (!abs.isFinite || abs < 0) {
      throw ArgumentError.value(
        abs,
        'abs',
        'TOLERANCE_ABS_OUT_OF_RANGE (finite, >= 0 required)',
      );
    }
    if (!rel.isFinite || rel < 0) {
      throw ArgumentError.value(
        rel,
        'rel',
        'TOLERANCE_REL_OUT_OF_RANGE (finite, >= 0 required)',
      );
    }
    return Tolerance._(abs, rel);
  }

  const Tolerance._(this.abs, this.rel);

  /// Zero slack: equality is exact float equality. Not a chosen epsilon.
  static const Tolerance exact = Tolerance._(0, 0);

  /// Absolute slack floor.
  final double abs;

  /// Relative slack, scaled by the larger magnitude being compared.
  final double rel;

  /// The pre-registered comparison rule (see class doc). Edge-inclusive.
  bool allows(double expected, double actual) {
    final delta = (actual - expected).abs();
    return delta <= math.max(abs, rel * math.max(expected.abs(), actual.abs()));
  }

  @override
  bool operator ==(Object other) =>
      other is Tolerance && other.abs == abs && other.rel == rel;

  @override
  int get hashCode => Object.hash(abs, rel);

  @override
  String toString() => 'Tolerance(abs: $abs, rel: $rel)';
}

/// Elementwise comparison of two tensors under a registered [tol].
///
/// There is deliberately no `Tensor.operator==`: tensor equality is ALWAYS
/// tolerance-parameterized (oracle-boundary law). Shape mismatch is never
/// "equal" at any tolerance.
bool tensorsEqual(Tensor a, Tensor b, Tolerance tol) {
  if (a.rows != b.rows || a.cols != b.cols) return false;
  for (var i = 0; i < a.data.length; i++) {
    if (!tol.allows(a.data[i], b.data[i])) return false;
  }
  return true;
}

/// Names a tensor and a (possibly partial) rectangular window inside it, plus
/// the [directionId] of the proposed direction this address belongs to.
///
/// Window bounds are half-open `[start, end)`; `null` means "full extent".
/// The algebra checks window geometry; binding [tensor] names to actual engine
/// buffers is the harness's job (identity lives in receipts, not here).
final class TensorAddress {
  const TensorAddress({
    required this.tensor,
    required this.directionId,
    this.rowStart,
    this.rowEnd,
    this.colStart,
    this.colEnd,
  });

  final String tensor;
  final String directionId;
  final int? rowStart;
  final int? rowEnd;
  final int? colStart;
  final int? colEnd;

  /// Human/ledger-readable description used in named conflict details.
  String get description =>
      '$tensor[rows=${rowStart ?? ':'}..${rowEnd ?? ':'} '
      'cols=${colStart ?? ':'}..${colEnd ?? ':'}] dir=$directionId';
}

/// Two addresses overlap when they name the same tensor and their (null =
/// unbounded) row and column intervals intersect. Overlap is a refuse, not a
/// warning (PROGRAM.md §3).
bool addressesOverlap(TensorAddress a, TensorAddress b) {
  if (a.tensor != b.tensor) return false;
  return _intervalsOverlap(a.rowStart, a.rowEnd, b.rowStart, b.rowEnd) &&
      _intervalsOverlap(a.colStart, a.colEnd, b.colStart, b.colEnd);
}

bool _intervalsOverlap(int? aStart, int? aEnd, int? bStart, int? bEnd) {
  const negInf = -0x7FFFFFFFFFFFFFFF;
  const posInf = 0x7FFFFFFFFFFFFFFF;
  final as = aStart ?? negInf;
  final ae = aEnd ?? posInf;
  final bs = bStart ?? negInf;
  final be = bEnd ?? posInf;
  return as < be && bs < ae;
}

/// A rank-1..r direction delta over an addressed window.
///
/// [vectors] holds exactly [rank] flattened direction vectors, each of the
/// same length and each covering the addressed window in row-major order
/// (`i = (row - rowStart) * width + (col - colStart)`). The composite element
/// delta is `scale * sum_k vectors[k][i]` (see [at]); a rank-1 contrastive
/// steering direction (PREREG-A A3) is the single-vector case, and higher
/// ranks compose additional directions in the same window.
///
/// All values must be finite at construction (named ArgumentError otherwise):
/// non-finite deltas are pipeline bugs, not conflicts.
final class DeltaSpec {
  DeltaSpec({
    required this.rank,
    required List<List<double>> vectors,
    required this.scale,
  }) : vectors = List.unmodifiable([
         for (final v in vectors) List<double>.unmodifiable(v),
       ]) {
    if (rank < 1) {
      throw ArgumentError.value(rank, 'rank', 'RANK_BELOW_ONE');
    }
    if (this.vectors.length != rank) {
      throw ArgumentError(
        'RANK_VECTOR_COUNT_MISMATCH rank=$rank vectors=${this.vectors.length}',
      );
    }
    if (!scale.isFinite) {
      throw ArgumentError.value(scale, 'scale', 'NON_FINITE_SCALE');
    }
    final width = this.vectors.first.length;
    if (width == 0) {
      throw ArgumentError.value(vectors, 'vectors', 'EMPTY_DIRECTION_VECTOR');
    }
    for (var k = 0; k < this.vectors.length; k++) {
      final v = this.vectors[k];
      if (v.length != width) {
        throw ArgumentError(
          'VECTOR_LENGTH_MISMATCH expected=$width found=${v.length} at=$k',
        );
      }
      for (var i = 0; i < v.length; i++) {
        if (!v[i].isFinite) {
          throw ArgumentError.value(
            v[i],
            'vectors[$k][$i]',
            'NON_FINITE_DELTA',
          );
        }
      }
    }
  }

  final int rank;
  final List<List<double>> vectors;
  final double scale;

  /// Required length of each direction vector (window element count).
  int get elementCount => vectors.first.length;

  /// Composite element delta at window index [i]: `scale * sum_k vectors[k][i]`.
  double at(int i) {
    var sum = 0.0;
    for (final v in vectors) {
      sum += v[i];
    }
    return scale * sum;
  }

  /// Same directions, opposite sign (used by [inverse]).
  DeltaSpec negated() => DeltaSpec(rank: rank, vectors: vectors, scale: -scale);
}

/// One proposed edit: where ([address]), against which observed base state
/// ([expectedOldFingerprint]), what ([delta]), and under which declared
/// [preconditions].
///
/// [preconditions] are NAMED strings carried, not evaluated: this algebra has
/// no oracle, and per the propose-only law the harness (frozen oracle side)
/// decides whether declared preconditions hold before it calls [apply].
///
/// [expectedNewFingerprint] is an optional commitment to the post-state window
/// fingerprint. [diff] sets it because it has observed both endpoints; entries
/// that only predict a post state leave it null (a float round trip is not
/// bit-exact, so committing an unobserved fingerprint would be a lie).
/// [inverse] of a [Proposal] requires the commitment; [inverse] of an
/// [Applied] recomputes it from the observed post tensor.
final class PatchEntry {
  PatchEntry({
    required this.address,
    required this.expectedOldFingerprint,
    required this.delta,
    List<String> preconditions = const [],
    this.expectedNewFingerprint,
  }) : preconditions = List.unmodifiable(preconditions) {
    if (address.tensor.isEmpty) {
      throw ArgumentError.value(address.tensor, 'address.tensor', 'EMPTY_TENSOR_NAME');
    }
    if (address.directionId.isEmpty) {
      throw ArgumentError.value(
        address.directionId,
        'address.directionId',
        'EMPTY_DIRECTION_ID',
      );
    }
    if (expectedOldFingerprint.isEmpty) {
      throw ArgumentError.value(
        expectedOldFingerprint,
        'expectedOldFingerprint',
        'EMPTY_FINGERPRINT',
      );
    }
  }

  final TensorAddress address;
  final String expectedOldFingerprint;
  final DeltaSpec delta;
  final List<String> preconditions;
  final String? expectedNewFingerprint;
}

/// NAMED refusal vocabulary, ported from pattern's `ConflictReason`
/// (`pm-core/src/patch.rs`). [label] is the canonical machine string that
/// lands in ledgers and receipts.
enum ConflictReason {
  stalePrecondition('STALE_PRECONDITION'),
  shapeMismatch('SHAPE_MISMATCH'),
  overlap('OVERLAP');

  const ConflictReason(this.label);

  final String label;
}

/// The patch-algebra result union: every operation returns either material
/// ([Applied], [Proposal]) or a named refusal ([Conflict]) — never null, never
/// a silent no-op.
sealed class Patch {
  const Patch();
}

/// A proposal: entries that have NOT been materialized. Produced by [diff]
/// and [inverse]. Propose-only law: a proposal changes nothing until [apply]
/// runs it against the actual base fingerprint.
final class Proposal extends Patch {
  Proposal(List<PatchEntry> entries)
    : entries = List.unmodifiable(entries) {
    if (entries.isEmpty) {
      throw ArgumentError.value(entries, 'entries', 'EMPTY_PROPOSAL');
    }
  }

  final List<PatchEntry> entries;
}

/// A materialized application: the post tensor, the entries that produced it,
/// and the [tolerance] registered at the apply site.
final class Applied extends Patch {
  Applied({
    required this.tensor,
    required List<PatchEntry> entries,
    required this.tolerance,
  }) : entries = List.unmodifiable(entries);

  final Tensor tensor;
  final List<PatchEntry> entries;

  /// The oracle-boundary tolerance registered by the caller of [apply]/
  /// [applyAll]. Carried so downstream assertions compare under the SAME
  /// registered numbers instead of inventing new ones.
  final Tolerance tolerance;

  /// True when the post tensor equals [expected] under the registered
  /// [tolerance] (pre-registered rule in [Tolerance]).
  bool reproduces(Tensor expected) => tensorsEqual(tensor, expected, tolerance);
}

/// A named refusal. [reason] is the frozen vocabulary; [detail] names the
/// concrete offending values so the refusal can go straight into a ledger row.
final class Conflict extends Patch {
  const Conflict(this.reason, this.detail);

  final ConflictReason reason;
  final String detail;

  @override
  String toString() => 'CONFLICT ${reason.label}: $detail';
}

/// Applies one [entry] to [base] and returns the materialized [Applied]
/// tensor, or a named [Conflict]:
///
/// - SHAPE_MISMATCH: the addressed window does not fit [base], or a delta
///   vector length does not equal the window element count. Structural checks
///   run first — a patch that cannot be shaped never reaches provenance.
/// - STALE_PRECONDITION: [actualFingerprint] (computed by the caller from the
///   ACTUAL base, engine-side) differs from [PatchEntry.expectedOldFingerprint]
///   (what the proposer observed). The base moved; the proposal is stale.
/// - OVERLAP: not reachable from a single entry; [applyAll] raises it for
///   intersecting windows in a batch.
///
/// [tol] is the oracle-boundary tolerance registered for this application; it
/// does not loosen the arithmetic (apply is exact float addition) but is
/// carried on the [Applied] result so downstream comparisons use the same
/// registered numbers. Overflow to a non-finite result throws a named
/// ArgumentError from [Tensor.set] — it is a loud pipeline bug, not a
/// conflict class.
Patch apply(
  Tensor base,
  PatchEntry entry, {
  Tolerance tol = Tolerance.exact,
  required String actualFingerprint,
}) {
  final violation = _windowViolation(entry.address, base.rows, base.cols);
  if (violation != null) {
    return Conflict(
      ConflictReason.shapeMismatch,
      '${entry.address.description} $violation',
    );
  }
  final window = _resolveWindow(entry.address, base.rows, base.cols);
  final area = (window.rowEnd - window.rowStart) *
      (window.colEnd - window.colStart);
  if (entry.delta.elementCount != area) {
    return Conflict(
      ConflictReason.shapeMismatch,
      'DELTA_AREA_MISMATCH ${entry.address.description} '
      'delta=${entry.delta.elementCount} window=$area',
    );
  }
  if (actualFingerprint != entry.expectedOldFingerprint) {
    return Conflict(
      ConflictReason.stalePrecondition,
      'FINGERPRINT_MISMATCH ${entry.address.description} '
      'expected=${entry.expectedOldFingerprint} actual=$actualFingerprint',
    );
  }
  final out = _materialize(base, window, entry.delta);
  return Applied(tensor: out, entries: [entry], tolerance: tol);
}

/// Applies a batch of entries to [base] as one refuse-before-mutation unit
/// (pattern's `apply` over a ChangeSet: overlap check precedes any change).
///
/// Order of named refusals: per-entry SHAPE_MISMATCH (structure), then
/// pairwise OVERLAP (geometry), then the per-entry fold where each entry can
/// still fail STALE_PRECONDITION. [actualFingerprintOf] is the caller's oracle
/// hook: because overlapping windows were refused up front, a fingerprint
/// computed against the ORIGINAL base stays valid for every entry as the fold
/// evolves the tensor (disjoint windows never touch each other's bytes).
///
/// All entries address windows of the single [base] buffer; cross-tensor
/// batches are the harness's composition problem, not the algebra's.
Patch applyAll(
  Tensor base,
  List<PatchEntry> entries, {
  Tolerance tol = Tolerance.exact,
  required String Function(PatchEntry entry) actualFingerprintOf,
}) {
  if (entries.isEmpty) {
    throw ArgumentError.value(entries, 'entries', 'EMPTY_BATCH');
  }
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final violation = _windowViolation(entry.address, base.rows, base.cols);
    if (violation != null) {
      return Conflict(
        ConflictReason.shapeMismatch,
        'entry[$i] ${entry.address.description} $violation',
      );
    }
    final window = _resolveWindow(entry.address, base.rows, base.cols);
    final area = (window.rowEnd - window.rowStart) *
        (window.colEnd - window.colStart);
    if (entry.delta.elementCount != area) {
      return Conflict(
        ConflictReason.shapeMismatch,
        'entry[$i] DELTA_AREA_MISMATCH ${entry.address.description} '
        'delta=${entry.delta.elementCount} window=$area',
      );
    }
  }
  for (var i = 0; i < entries.length; i++) {
    for (var j = i + 1; j < entries.length; j++) {
      if (addressesOverlap(entries[i].address, entries[j].address)) {
        return Conflict(
          ConflictReason.overlap,
          'WINDOWS_INTERSECT entry[$i]=${entries[i].address.description} '
          'entry[$j]=${entries[j].address.description}',
        );
      }
    }
  }
  var current = base;
  for (final entry in entries) {
    final result = apply(
      current,
      entry,
      tol: tol,
      actualFingerprint: actualFingerprintOf(entry),
    );
    if (result is Conflict) return result;
    current = (result as Applied).tensor;
  }
  return Applied(tensor: current, entries: entries, tolerance: tol);
}

/// Proposes the minimal rank-1 full-window delta whose [apply] reproduces [b]
/// from [a] within any registered tolerance (exactly, for well-conditioned
/// values). Pure proposal: nothing is mutated.
///
/// Both fingerprints are committed ([PatchEntry.expectedOldFingerprint] from
/// [a], [PatchEntry.expectedNewFingerprint] from [b]) because diff has
/// OBSERVED both endpoints — this is what makes [inverse] of a diff proposal
/// safe without re-running arithmetic.
Patch diff(Tensor a, Tensor b, {required String tensorName}) {
  if (a.rows != b.rows || a.cols != b.cols) {
    return Conflict(
      ConflictReason.shapeMismatch,
      'DIFF_SHAPE_MISMATCH tensor=$tensorName '
      'a=${a.rows}x${a.cols} b=${b.rows}x${b.cols}',
    );
  }
  final delta = DeltaSpec(
    rank: 1,
    vectors: [
      [for (var i = 0; i < a.data.length; i++) b.data[i] - a.data[i]],
    ],
    scale: 1,
  );
  final address = TensorAddress(tensor: tensorName, directionId: 'diff');
  return Proposal([
    PatchEntry(
      address: address,
      expectedOldFingerprint: tensorFingerprint(a),
      expectedNewFingerprint: tensorFingerprint(b),
      delta: delta,
    ),
  ]);
}

/// Proposes the inverse of a patch: same windows, negated deltas.
///
/// - [Conflict] input propagates unchanged — a named failure is never
///   laundered into a proposal.
/// - [Applied] input: post-state fingerprints are recomputed from the OBSERVED
///   post tensor, so the inverse applies cleanly to it.
/// - [Proposal] input: requires every entry to carry
///   [PatchEntry.expectedNewFingerprint] (a committed, observed post state);
///   inverting an uncommitted post state would fabricate a fingerprint, so it
///   throws a named StateError (UNCOMMITTED_POSTSTATE) instead.
Patch inverse(Patch p) {
  switch (p) {
    case Conflict():
      return p;
    case Applied(:final entries, :final tensor):
      return Proposal([
        for (final e in entries)
          PatchEntry(
            address: e.address,
            expectedOldFingerprint: windowFingerprint(tensor, e.address),
            delta: e.delta.negated(),
            preconditions: e.preconditions,
          ),
      ]);
    case Proposal(:final entries):
      return Proposal([
        for (final e in entries)
          PatchEntry(
            address: e.address,
            expectedOldFingerprint: _committedPostState(e),
            expectedNewFingerprint: e.expectedOldFingerprint,
            delta: e.delta.negated(),
            preconditions: e.preconditions,
          ),
      ]);
  }
}

String _committedPostState(PatchEntry e) {
  final fp = e.expectedNewFingerprint;
  if (fp == null) {
    throw StateError(
      'UNCOMMITTED_POSTSTATE direction=${e.address.directionId} has no '
      'observed post-state fingerprint; refusing to fabricate one',
    );
  }
  return fp;
}

/// Canonical sha256 fingerprint of a whole tensor (full window).
String tensorFingerprint(Tensor tensor) =>
    _fingerprint(tensor, 0, tensor.rows, 0, tensor.cols);

/// Canonical sha256 fingerprint of the addressed window of [tensor].
///
/// The pre-image is a versioned textual header (shape + resolved half-open
/// window) followed by each window value as a big-endian IEEE-754 double, so
/// the digest is stable across platforms and independent of proposal metadata
/// (tensor name and directionId identify the proposal, not the content).
///
/// Throws a named ArgumentError (ADDRESS_OUT_OF_BOUNDS) when the window does
/// not fit: fingerprinting an invalid address is a caller bug, not a conflict.
String windowFingerprint(Tensor tensor, TensorAddress address) {
  final violation = _windowViolation(address, tensor.rows, tensor.cols);
  if (violation != null) {
    throw ArgumentError.value(
      address.description,
      'address',
      'ADDRESS_OUT_OF_BOUNDS $violation',
    );
  }
  final w = _resolveWindow(address, tensor.rows, tensor.cols);
  return _fingerprint(tensor, w.rowStart, w.rowEnd, w.colStart, w.colEnd);
}

String _fingerprint(
  Tensor tensor,
  int rowStart,
  int rowEnd,
  int colStart,
  int colEnd,
) {
  final header = utf8.encode(
    'weightmap-fingerprint-v1|shape=${tensor.rows}x${tensor.cols}|'
    'window=$rowStart:$rowEnd:$colStart:$colEnd\n',
  );
  final width = colEnd - colStart;
  final count = (rowEnd - rowStart) * width;
  final bytes = ByteData(count * 8);
  var i = 0;
  for (var r = rowStart; r < rowEnd; r++) {
    for (var c = colStart; c < colEnd; c++) {
      bytes.setFloat64(i * 8, tensor.data[r * tensor.cols + c], Endian.big);
      i++;
    }
  }
  final sink = BytesBuilder(copy: false)
    ..add(header)
    ..add(bytes.buffer.asUint8List());
  return sha256.convert(sink.takeBytes()).toString();
}

typedef _Window =
    ({int rowStart, int rowEnd, int colStart, int colEnd});

String? _windowViolation(TensorAddress a, int rows, int cols) {
  final rs = a.rowStart ?? 0;
  final re = a.rowEnd ?? rows;
  final cs = a.colStart ?? 0;
  final ce = a.colEnd ?? cols;
  if (rs < 0 || re > rows || rs >= re) {
    return 'ROW_WINDOW_INVALID rowStart=${a.rowStart} rowEnd=${a.rowEnd} '
        'rows=$rows (half-open, non-empty, in-bounds required)';
  }
  if (cs < 0 || ce > cols || cs >= ce) {
    return 'COL_WINDOW_INVALID colStart=${a.colStart} colEnd=${a.colEnd} '
        'cols=$cols (half-open, non-empty, in-bounds required)';
  }
  return null;
}

_Window _resolveWindow(TensorAddress a, int rows, int cols) => (
  rowStart: a.rowStart ?? 0,
  rowEnd: a.rowEnd ?? rows,
  colStart: a.colStart ?? 0,
  colEnd: a.colEnd ?? cols,
);

Tensor _materialize(Tensor base, _Window w, DeltaSpec delta) {
  final out = base.clone();
  final width = w.colEnd - w.colStart;
  for (var r = w.rowStart; r < w.rowEnd; r++) {
    for (var c = w.colStart; c < w.colEnd; c++) {
      final i = (r - w.rowStart) * width + (c - w.colStart);
      out.set(r, c, base.get(r, c) + delta.at(i));
    }
  }
  return out;
}
