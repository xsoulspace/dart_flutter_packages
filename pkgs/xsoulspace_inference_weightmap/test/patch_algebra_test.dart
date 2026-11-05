/// Laws of the patch algebra, as tests (PROGRAM.md §0 propose-only;
/// pattern pm-core patch.rs port). Every law in the module doc has a case
/// here; the tolerance edge follows the PRE-REGISTERED inclusive rule.
library;

import 'package:test/test.dart';
import 'package:xsoulspace_inference_weightmap/src/patch_algebra.dart';

/// Builds an entry whose fingerprint precondition is honestly computed from
/// [base] (what a proposer observed), for window law tests.
PatchEntry windowEntry({
  required Tensor base,
  required String tensor,
  required String direction,
  required List<List<double>> vectors,
  double scale = 1,
  int? rowStart,
  int? rowEnd,
  int? colStart,
  int? colEnd,
}) {
  final address = TensorAddress(
    tensor: tensor,
    directionId: direction,
    rowStart: rowStart,
    rowEnd: rowEnd,
    colStart: colStart,
    colEnd: colEnd,
  );
  return PatchEntry(
    address: address,
    expectedOldFingerprint: windowFingerprint(base, address),
    delta: DeltaSpec(rank: vectors.length, vectors: vectors, scale: scale),
  );
}

void main() {
  // 0.25-grid values: every diff/apply/inverse round trip below is bit-exact,
  // so the exact-tolerance laws test the ALGEBRA, not float luck.
  final a = Tensor.fromRows([
    [1, 2, 3],
    [4, 5, 6],
  ]);
  final b = Tensor.fromRows([
    [1.5, 2, 2.75],
    [4, 5.25, 6],
  ]);
  const tensorName = 'model.layers.0.mlp.down_proj.weight';

  group('Tensor', () {
    test('get/set/clone with row-major layout', () {
      final t = Tensor(2, 3);
      expect(t.get(1, 2), 0.0);
      t.set(1, 2, 4.5);
      expect(t.get(1, 2), 4.5);
      expect(t.data[1 * 3 + 2], 4.5); // row-major offset
      final c = t.clone();
      c.set(1, 2, 9.5);
      expect(t.get(1, 2), 4.5); // clone is independent
      expect(() => t.get(2, 0), throwsRangeError);
      expect(() => t.set(0, 3, 1), throwsRangeError);
    });

    test('refuses non-finite values and invalid shapes, loudly', () {
      expect(
        () => Tensor(0, 3),
        throwsA(
          isArgumentError.having(
            (e) => e.message,
            'message',
            contains('INVALID_SHAPE'),
          ),
        ),
      );
      expect(
        () => Tensor.fromRows([
          [1, 2],
          [3],
        ]),
        throwsA(
          isArgumentError.having(
            (e) => e.message,
            'message',
            contains('RAGGED_ROWS'),
          ),
        ),
      );
      final t = Tensor(1, 1);
      expect(
        () => t.set(0, 0, double.nan),
        throwsA(
          isArgumentError.having(
            (e) => e.message,
            'message',
            contains('NON_FINITE_VALUE'),
          ),
        ),
      );
    });

    test('fingerprint is content-addressed and window-scoped', () {
      expect(tensorFingerprint(a), tensorFingerprint(a.clone()));
      final changed = a.clone()..set(0, 0, 1.0000001);
      expect(tensorFingerprint(changed), isNot(tensorFingerprint(a)));
      // Full-window address fingerprint == whole-tensor fingerprint.
      final full = TensorAddress(tensor: tensorName, directionId: 'd');
      expect(windowFingerprint(a, full), tensorFingerprint(a));
      // A window fingerprint ignores changes outside the window...
      final w = TensorAddress(
        tensor: tensorName,
        directionId: 'd',
        rowStart: 0,
        rowEnd: 1,
      );
      final outside = a.clone()..set(1, 0, 42);
      expect(windowFingerprint(outside, w), windowFingerprint(a, w));
      // ...and sees changes inside it.
      final inside = a.clone()..set(0, 0, 42);
      expect(windowFingerprint(inside, w), isNot(windowFingerprint(a, w)));
      // Fingerprinting an out-of-bounds window is a named caller bug.
      final bad = TensorAddress(
        tensor: tensorName,
        directionId: 'd',
        rowEnd: 99,
      );
      expect(
        () => windowFingerprint(a, bad),
        throwsA(
          isArgumentError.having(
            (e) => e.message,
            'message',
            contains('ADDRESS_OUT_OF_BOUNDS'),
          ),
        ),
      );
    });
  });

  group('Tolerance (oracle boundary)', () {
    test('pre-registered rule is edge-inclusive: at the edge passes', () {
      final tol = Tolerance(abs: 0.25, rel: 0);
      expect(tol.allows(0, 0.25), isTrue); // delta exactly at abs edge
      expect(tol.allows(1.0, 1.25), isTrue);
      // One representable step beyond the edge fails (0.25 + ulp).
      expect(tol.allows(0, 0.25000000000000006), isFalse);
    });

    test('rel term scales by the larger magnitude', () {
      final tol = Tolerance(abs: 0, rel: 0.1);
      expect(tol.allows(100, 109), isTrue); // 9 <= 0.1 * 109
      expect(tol.allows(100, 110), isTrue); // edge: 10 <= 0.1 * 110
      expect(tol.allows(100, 112), isFalse); // 12 > 0.1 * 112
    });

    test('exact registers zero slack and NaN never passes', () {
      expect(Tolerance.exact.allows(1, 1), isTrue);
      expect(Tolerance.exact.allows(1, 1.0000000000000002), isFalse);
      final tol = Tolerance(abs: 1e9, rel: 1e9);
      expect(tol.allows(1, double.nan), isFalse);
    });

    test('negative or non-finite slack is refused at construction', () {
      expect(
        () => Tolerance(abs: -1, rel: 0),
        throwsA(
          isArgumentError.having(
            (e) => e.message,
            'message',
            contains('TOLERANCE_ABS_OUT_OF_RANGE'),
          ),
        ),
      );
      expect(
        () => Tolerance(abs: double.infinity, rel: 0),
        throwsA(
          isArgumentError.having(
            (e) => e.message,
            'message',
            contains('TOLERANCE_ABS_OUT_OF_RANGE'),
          ),
        ),
      );
      expect(
        () => Tolerance(abs: 0, rel: -1),
        throwsA(
          isArgumentError.having(
            (e) => e.message,
            'message',
            contains('TOLERANCE_REL_OUT_OF_RANGE'),
          ),
        ),
      );
    });
  });

  group('DeltaSpec / PatchEntry construction is named, never silent', () {
    test('rank and vector invariants', () {
      expect(
        () => DeltaSpec(rank: 0, vectors: [], scale: 1),
        throwsA(
          isArgumentError.having(
            (e) => e.message,
            'message',
            contains('RANK_BELOW_ONE'),
          ),
        ),
      );
      expect(
        () => DeltaSpec(rank: 2, vectors: [
          [1, 1],
        ], scale: 1),
        throwsA(
          isArgumentError.having(
            (e) => e.message,
            'message',
            contains('RANK_VECTOR_COUNT_MISMATCH'),
          ),
        ),
      );
      expect(
        () => DeltaSpec(rank: 1, vectors: [[]], scale: 1),
        throwsA(
          isArgumentError.having(
            (e) => e.message,
            'message',
            contains('EMPTY_DIRECTION_VECTOR'),
          ),
        ),
      );
      expect(
        () => DeltaSpec(rank: 2, vectors: [
          [1, 1],
          [1, 1, 1],
        ], scale: 1),
        throwsA(
          isArgumentError.having(
            (e) => e.message,
            'message',
            contains('VECTOR_LENGTH_MISMATCH'),
          ),
        ),
      );
      expect(
        () => DeltaSpec(rank: 1, vectors: [
          [1, double.nan],
        ], scale: 1),
        throwsA(
          isArgumentError.having(
            (e) => e.message,
            'message',
            contains('NON_FINITE_DELTA'),
          ),
        ),
      );
      expect(
        () => DeltaSpec(rank: 1, vectors: [
          [1, 1],
        ], scale: double.infinity),
        throwsA(
          isArgumentError.having(
            (e) => e.message,
            'message',
            contains('NON_FINITE_SCALE'),
          ),
        ),
      );
    });

    test('rank composes directions: at(i) = scale * sum_k vectors[k][i]', () {
      final d = DeltaSpec(rank: 2, vectors: [
        [1, 2],
        [0.5, 0.5],
      ], scale: 2);
      expect(d.at(0), 3.0); // 2 * (1 + 0.5)
      expect(d.at(1), 5.0); // 2 * (2 + 0.5)
      expect(d.negated().at(0), -3.0);
    });

    test('entry refuses empty identity fields', () {
      final delta = DeltaSpec(rank: 1, vectors: [
        [1],
      ], scale: 1);
      expect(
        () => PatchEntry(
          address: TensorAddress(tensor: tensorName, directionId: 'd'),
          expectedOldFingerprint: '',
          delta: delta,
        ),
        throwsA(
          isArgumentError.having(
            (e) => e.message,
            'message',
            contains('EMPTY_FINGERPRINT'),
          ),
        ),
      );
      expect(
        () => PatchEntry(
          address: TensorAddress(tensor: tensorName, directionId: ''),
          expectedOldFingerprint: 'fp',
          delta: delta,
        ),
        throwsA(
          isArgumentError.having(
            (e) => e.message,
            'message',
            contains('EMPTY_DIRECTION_ID'),
          ),
        ),
      );
    });
  });

  group('apply / diff / inverse laws', () {
    test('law: apply(a, diff(a, b)) reproduces b', () {
      final d = diff(a, b, tensorName: tensorName);
      expect(d, isA<Proposal>());
      final entry = (d as Proposal).entries.single;
      final r = apply(
        a,
        entry,
        tol: Tolerance.exact,
        actualFingerprint: tensorFingerprint(a),
      );
      expect(r, isA<Applied>());
      final applied = r as Applied;
      // Exact on the 0.25 grid: the registered tolerance is the degenerate
      // zero-slack boundary, and the law still holds bit-for-bit.
      expect(applied.reproduces(b), isTrue);
      expect(tensorsEqual(applied.tensor, b, Tolerance.exact), isTrue);
    });

    test('law: round trip holds within a registered loose tolerance', () {
      // Honest float conditioning: x + (y - x) is NOT bit-exact in general.
      // At 1e16 the double ulp is 2, so fl(y - x) rounds to -1e16 and the
      // round trip lands on 0.0 instead of 1.0 — a full 1.0 of cancellation
      // error the registered oracle boundary must absorb. (The 0.25-grid
      // pairs elsewhere in this file are bit-exact BY CONSTRUCTION, not by
      // luck; this pair is the counterexample that proves the tolerance is
      // load-bearing.)
      final x = Tensor.fromRows([
        [1e16, 0.5],
      ]);
      final y = Tensor.fromRows([
        [1.0, 0.75],
      ]);
      final d = diff(x, y, tensorName: tensorName) as Proposal;
      final r = apply(
        x,
        d.entries.single,
        tol: Tolerance(abs: 1, rel: 0),
        actualFingerprint: tensorFingerprint(x),
      ) as Applied;
      // The cancellation error is exactly 1.0 — AT the registered edge, so
      // the inclusive rule accepts it...
      expect(r.tensor.get(0, 0), 0.0);
      expect(r.reproduces(y), isTrue);
      // ...and the same result is NOT claimed under exact slack: the numbers
      // stay in the oracle — different tolerance, different verdict.
      expect(tensorsEqual(r.tensor, y, Tolerance.exact), isFalse);
    });

    test('law: apply(apply(a, d), inverse(d)) returns to a', () {
      final d = diff(a, b, tensorName: tensorName);
      final forward = apply(
        a,
        (d as Proposal).entries.single,
        actualFingerprint: tensorFingerprint(a),
      ) as Applied;
      final inv = inverse(d);
      expect(inv, isA<Proposal>());
      final invEntry = (inv as Proposal).entries.single;
      // The inverse proposal expects the OBSERVED post state (b's fingerprint).
      expect(invEntry.expectedOldFingerprint, tensorFingerprint(b));
      final back = apply(
        forward.tensor,
        invEntry,
        actualFingerprint: tensorFingerprint(forward.tensor),
      );
      expect(back, isA<Applied>());
      expect((back as Applied).reproduces(a), isTrue);
    });

    test('law: inverse of an Applied recomputes from the observed tensor', () {
      final d = diff(a, b, tensorName: tensorName) as Proposal;
      final forward = apply(
        a,
        d.entries.single,
        actualFingerprint: tensorFingerprint(a),
      ) as Applied;
      final inv = inverse(forward) as Proposal;
      final back = apply(
        forward.tensor,
        inv.entries.single,
        actualFingerprint: windowFingerprint(forward.tensor, inv.entries.single
            .address),
      ) as Applied;
      expect(back.reproduces(a), isTrue);
    });

    test('law: a stale fingerprint refuses with NAMED STALE_PRECONDITION', () {
      final d = diff(a, b, tensorName: tensorName) as Proposal;
      final moved = a.clone()..set(0, 0, 99); // the base moved under us
      final r = apply(
        moved,
        d.entries.single,
        actualFingerprint: tensorFingerprint(moved),
      );
      expect(r, isA<Conflict>());
      final conflict = r as Conflict;
      expect(conflict.reason, ConflictReason.stalePrecondition);
      expect(conflict.reason.label, 'STALE_PRECONDITION');
      expect(conflict.detail, contains('FINGERPRINT_MISMATCH'));
      expect('$conflict', startsWith('CONFLICT STALE_PRECONDITION'));
    });

    test('law: shape violations refuse with NAMED SHAPE_MISMATCH', () {
      // Window does not fit the base. Built directly (windowFingerprint
      // refuses invalid addresses, as it must); the fingerprint value is
      // deliberately WRONG to pin the documented check order: structure is
      // validated before provenance, so a misshapen patch reports
      // SHAPE_MISMATCH even when it is also stale.
      final out = PatchEntry(
        address: TensorAddress(
          tensor: tensorName,
          directionId: 'd',
          rowEnd: 99,
        ),
        expectedOldFingerprint: 'does-not-matter-shape-is-checked-first',
        delta: DeltaSpec(rank: 1, vectors: [
          [1, 1, 1],
        ], scale: 1),
      );
      var r = apply(a, out, actualFingerprint: tensorFingerprint(a));
      expect((r as Conflict).reason.label, 'SHAPE_MISMATCH');
      expect(r.detail, contains('ROW_WINDOW_INVALID'));

      // Delta vector length != window area.
      final mismatch = PatchEntry(
        address: TensorAddress(tensor: tensorName, directionId: 'd'),
        expectedOldFingerprint: tensorFingerprint(a),
        delta: DeltaSpec(rank: 1, vectors: [
          [1, 2, 3, 4, 5],
        ], scale: 1), // 5 values for a 2x3 window
      );
      r = apply(a, mismatch, actualFingerprint: tensorFingerprint(a));
      expect((r as Conflict).reason.label, 'SHAPE_MISMATCH');
      expect(r.detail, contains('DELTA_AREA_MISMATCH'));

      // diff across different shapes.
      final other = Tensor.fromRows([
        [1, 2],
      ]);
      r = diff(a, other, tensorName: tensorName);
      expect((r as Conflict).reason.label, 'SHAPE_MISMATCH');
      expect(r.detail, contains('DIFF_SHAPE_MISMATCH'));
    });

    test('apply is propose-materialize: the base is never mutated', () {
      final d = diff(a, b, tensorName: tensorName) as Proposal;
      final before = tensorFingerprint(a);
      apply(a, d.entries.single, actualFingerprint: before);
      expect(tensorFingerprint(a), before);
      expect(a.get(0, 0), 1.0);
    });

    test('inverse propagates a Conflict unchanged (never laundered)', () {
      const conflict = Conflict(ConflictReason.overlap, 'WINDOWS_INTERSECT');
      expect(identical(inverse(conflict), conflict), isTrue);
    });

    test('inverse refuses an uncommitted post state, named', () {
      final entry = PatchEntry(
        address: TensorAddress(tensor: tensorName, directionId: 'd'),
        expectedOldFingerprint: tensorFingerprint(a),
        delta: DeltaSpec(rank: 1, vectors: [
          [0, 0, 0, 0, 0, 1],
        ], scale: 1),
        // no expectedNewFingerprint: nobody observed the post state
      );
      expect(
        () => inverse(Proposal([entry])),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('UNCOMMITTED_POSTSTATE'),
          ),
        ),
      );
    });
  });

  group('window discipline: commutation and overlap', () {
    late Tensor base;
    setUp(() {
      base = Tensor.fromRows([
        [0, 0],
        [0, 0],
        [0, 0],
        [0, 0],
      ]);
    });

    test('half-open windows: adjacent ranges are disjoint', () {
      final top = TensorAddress(
        tensor: tensorName,
        directionId: 'top',
        rowEnd: 2,
      );
      final bottom = TensorAddress(
        tensor: tensorName,
        directionId: 'bottom',
        rowStart: 2,
      );
      expect(addressesOverlap(top, bottom), isFalse); // [0,2) vs [2,4)
      // Different tensor names never overlap in this algebra (identity
      // binding is the harness's job).
      final otherTensor = TensorAddress(
        tensor: 'other.weight',
        directionId: 'top',
        rowEnd: 2,
      );
      expect(addressesOverlap(top, otherTensor), isFalse);
      // Unbounded (null) bounds conservatively overlap everything.
      expect(
        addressesOverlap(top, TensorAddress(
          tensor: tensorName,
          directionId: 'full',
        )),
        isTrue,
      );
    });

    test('law: disjoint patches commute (bit-exact, in both orders)', () {
      final e1 = windowEntry(
        base: base,
        tensor: tensorName,
        direction: 'planted-0',
        vectors: [
          [1 / 3, 1 / 3, 1 / 3, 1 / 3],
        ],
        rowEnd: 2,
      );
      final e2 = windowEntry(
        base: base,
        tensor: tensorName,
        direction: 'null-0',
        vectors: [
          [0.1, 0.1, 0.1, 0.1],
        ],
        rowStart: 2,
      );
      String fpOf(PatchEntry e) => windowFingerprint(base, e.address);
      final forward = applyAll(
        base,
        [e1, e2],
        actualFingerprintOf: fpOf,
      ) as Applied;
      final backward = applyAll(
        base,
        [e2, e1],
        actualFingerprintOf: fpOf,
      ) as Applied;
      // Disjoint windows: each element receives exactly one addition, so the
      // two orders agree bit-for-bit even on non-grid values.
      expect(
        tensorsEqual(forward.tensor, backward.tensor, Tolerance.exact),
        isTrue,
      );
      expect(forward.tensor.get(0, 0), 1 / 3);
      expect(forward.tensor.get(3, 1), closeTo(0.1, 1e-15));
    });

    test('law: overlapping patches refuse with NAMED OVERLAP', () {
      final e1 = windowEntry(
        base: base,
        tensor: tensorName,
        direction: 'planted-0',
        vectors: [
          [1, 1, 1, 1, 1, 1],
        ],
        rowEnd: 3,
      );
      final e2 = windowEntry(
        base: base,
        tensor: tensorName,
        direction: 'planted-1',
        vectors: [
          [1, 1, 1, 1],
        ],
        rowStart: 2,
      );
      final r = applyAll(base, [e1, e2], actualFingerprintOf: (e) {
        throw StateError('must refuse BEFORE any fingerprint is consumed');
      });
      expect(r, isA<Conflict>());
      final conflict = r as Conflict;
      expect(conflict.reason.label, 'OVERLAP');
      expect(conflict.detail, contains('WINDOWS_INTERSECT'));
      // Refuse-before-mutation: the base is untouched.
      expect(base.get(2, 0), 0.0);
    });

    test('column-only intersection also refuses', () {
      final left = windowEntry(
        base: base,
        tensor: tensorName,
        direction: 'l',
        vectors: [
          [1, 1, 1, 1],
        ],
        colEnd: 1,
      );
      final right = windowEntry(
        base: base,
        tensor: tensorName,
        direction: 'r',
        vectors: [
          [1, 1, 1, 1],
        ],
        colStart: 1,
      );
      expect(addressesOverlap(left.address, right.address), isFalse);
      final wide = windowEntry(
        base: base,
        tensor: tensorName,
        direction: 'w',
        vectors: [
          [1, 1, 1, 1, 1, 1, 1, 1],
        ],
      );
      expect(
        (applyAll(base, [left, wide], actualFingerprintOf: (e) =>
                windowFingerprint(base, e.address)) as Conflict)
            .reason
            .label,
        'OVERLAP',
      );
      expect(
        (applyAll(base, [right, wide], actualFingerprintOf: (e) =>
                windowFingerprint(base, e.address)) as Conflict)
            .reason
            .label,
        'OVERLAP',
      );
    });

    test('applyAll propagates the first named conflict in the fold', () {
      final good = windowEntry(
        base: base,
        tensor: tensorName,
        direction: 'good',
        vectors: [
          [1, 1],
        ],
        rowEnd: 1,
      );
      final stale = PatchEntry(
        address: TensorAddress(
          tensor: tensorName,
          directionId: 'stale',
          rowStart: 3,
        ),
        expectedOldFingerprint: 'not-what-the-base-says',
        delta: DeltaSpec(rank: 1, vectors: [
          [1, 1],
        ], scale: 1),
      );
      final r = applyAll(base, [good, stale], actualFingerprintOf: (e) {
        return windowFingerprint(base, e.address);
      });
      expect(r, isA<Conflict>());
      expect((r as Conflict).reason.label, 'STALE_PRECONDITION');
    });

    test('applyAll refuses an empty batch, named', () {
      expect(
        () => applyAll(base, [], actualFingerprintOf: (e) => ''),
        throwsA(
          isArgumentError.having(
            (e) => e.message,
            'message',
            contains('EMPTY_BATCH'),
          ),
        ),
      );
    });
  });

  group('tolerance edge law through apply', () {
    test('delta exactly at the registered edge is within; one step past is '
        'not', () {
      final zero = Tensor.fromRows([
        [0],
      ]);
      final atEdge = Tensor.fromRows([
        [0.25],
      ]);
      final pastEdge = Tensor.fromRows([
        [0.25000000000000006], // next representable double after 0.25
      ]);
      final edge = Tolerance(abs: 0.25, rel: 0);
      final d = diff(zero, atEdge, tensorName: tensorName) as Proposal;
      final r = apply(
        zero,
        d.entries.single,
        tol: edge,
        actualFingerprint: tensorFingerprint(zero),
      ) as Applied;
      // The applied delta is exactly the registered edge away from `zero`.
      // Pre-registered rule: the inclusive edge passes...
      expect(tensorsEqual(zero, r.tensor, edge), isTrue);
      // ...and one representable step beyond the edge fails.
      expect(tensorsEqual(zero, pastEdge, edge), isFalse);
      // The apply-site tolerance is carried on the result: exact reproduction
      // of the observed endpoint passes under it.
      expect(r.reproduces(atEdge), isTrue);
      // The SAME tensor pair under zero slack: only exact equality passes.
      expect(tensorsEqual(r.tensor, atEdge, Tolerance.exact), isTrue);
      expect(tensorsEqual(r.tensor, pastEdge, Tolerance.exact), isFalse);
    });

    test('shape mismatch is never "equal" at any tolerance', () {
      final wide = Tensor.fromRows([
        [0, 0],
      ]);
      final tall = Tensor.fromRows([
        [0],
        [0],
      ]);
      expect(tensorsEqual(wide, tall, Tolerance(abs: 1e9, rel: 1e9)),
          isFalse);
    });
  });
}
