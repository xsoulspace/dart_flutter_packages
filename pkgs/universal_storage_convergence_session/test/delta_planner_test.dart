import 'package:test/test.dart';
import 'package:universal_storage_convergence/universal_storage_convergence.dart';
import 'package:universal_storage_convergence_session/universal_storage_convergence_session.dart';

/// DeltaPlanner contract tests: the per-document anti-entropy decision
/// (ADR 0010 §4) extracted from the mesh exchange, proven pure and
/// budget-honoring — the same cases the mesh integration tests exercise
/// over the wire, now testable without a transport.
void main() {
  const planner = DeltaPlanner();

  OpRecord op(final String docId, final int counter, final String actor) =>
      OpRecord(
        docId: docId,
        hlc: Hlc(1700000000000 + counter, counter, actor),
        payload: {'k': 'k$counter', 'v': 'v$counter'},
      );

  /// A hand-rolled replica for pure decision tests.
  FakeReplica replica(
    final String docId, {
    final VersionVector? vv,
    final List<OpRecord>? pendingOps,
    final List<OpRecord> Function(VersionVector)? opsSince,
    final bool Function(VersionVector)? needsSnapshotFor,
    final Snapshot? snapshot,
  }) => FakeReplica(
    docId: docId,
    vv: vv ?? VersionVector.zero,
    pendingOps: pendingOps ?? const [],
    opsSince: opsSince,
    needsSnapshotFor: needsSnapshotFor,
    snapshot: snapshot,
  );

  group('per-document decision', () {
    test('unannounced doc with pending ops ships the ops', () {
      final pending = [op('d', 1, 'a'), op('d', 2, 'a')];
      final plan = planner.plan(
        docs: [replica('d', pendingOps: pending)],
        remoteVectors: const {},
      );
      expect(plan.ops, pending);
      expect(plan.states, isEmpty);
    });

    test('unannounced doc with an empty log ships a snapshot', () {
      final snapshot = Snapshot(
        docId: 'd',
        baseVv: VersionVector.zero,
        state: const {'k': 'v'},
        createdAt: const Hlc(1, 0, 'a'),
      );
      final plan = planner.plan(
        docs: [replica('d', snapshot: snapshot, needsSnapshotFor: (_) => true)],
        remoteVectors: const {},
      );
      expect(plan.ops, isEmpty);
      expect(plan.states, [snapshot]);
    });

    test('lagging doc ships exactly the unobserved ops', () {
      final pending = [op('d', 1, 'a'), op('d', 2, 'a')];
      final missing = [op('d', 2, 'a')];
      final theirs = VersionVector(const {'a': Hlc(1700000000001, 1, 'a')});
      final plan = planner.plan(
        docs: [replica('d', pendingOps: pending, opsSince: (_) => missing)],
        remoteVectors: {'d': theirs},
      );
      expect(plan.ops, missing);
      expect(plan.states, isEmpty);
    });

    test('covered-but-compacted doc ships a snapshot', () {
      final snapshot = Snapshot(
        docId: 'd',
        baseVv: VersionVector(const {'a': Hlc(1700000000002, 2, 'a')}),
        state: const {},
        createdAt: const Hlc(1700000000002, 2, 'a'),
      );
      final theirs = VersionVector(const {'a': Hlc(1700000000002, 2, 'a')});
      final plan = planner.plan(
        docs: [
          replica(
            'd',
            opsSince: (_) => const [],
            needsSnapshotFor: (_) => true,
            snapshot: snapshot,
          ),
        ],
        remoteVectors: {'d': theirs},
      );
      expect(plan.states, [snapshot]);
      expect(plan.ops, isEmpty);
    });

    test('up-to-date doc ships nothing', () {
      final theirs = VersionVector(const {'a': Hlc(1700000000002, 2, 'a')});
      final plan = planner.plan(
        docs: [
          replica(
            'd',
            opsSince: (_) => const [],
            needsSnapshotFor: (_) => false,
          ),
        ],
        remoteVectors: {'d': theirs},
      );
      expect(plan.isEmpty, isTrue);
    });
  });

  group('budget (receiver-expressed backpressure-lite)', () {
    test('stops before a doc once sent ops reach the budget', () {
      final first = [op('d1', 1, 'a'), op('d1', 2, 'a')];
      final second = [op('d2', 3, 'a')];
      final plan = planner.plan(
        docs: [
          replica('d1', pendingOps: first),
          replica('d2', pendingOps: second),
        ],
        remoteVectors: const {},
        maxOps: 2,
      );
      expect(plan.ops, first); // d2's op never enters the plan…
      expect(plan.states, isEmpty); // …and d2 gets no snapshot either.
    });

    test('null budget ships everything', () {
      final plan = planner.plan(
        docs: [
          replica('d1', pendingOps: [op('d1', 1, 'a')]),
          replica('d2', pendingOps: [op('d2', 2, 'a')]),
        ],
        remoteVectors: const {},
      );
      expect(plan.ops.length, 2);
    });
  });

  group('over a real ConvergenceDoc (structural adapter)', () {
    test('serves lagging peers from the log, compacted peers via snapshot', () {
      final doc = ConvergenceDoc(docId: 'd', actorId: 'alice')
        ..applyLocal(const {
          'k': 'a',
          'v': '1',
        }, DateTime.fromMillisecondsSinceEpoch(1700000000000))
        ..applyLocal(const {
          'k': 'b',
          'v': '2',
        }, DateTime.fromMillisecondsSinceEpoch(1700000000001));
      final lagging = VersionVector({'alice': doc.pendingOps.first.hlc});

      final plan1 = planner.plan(
        docs: [_DocSource(doc)],
        remoteVectors: {'d': lagging},
      );
      expect(plan1.ops, [doc.pendingOps[1]]);
      expect(plan1.ops.last, doc.pendingOps.last);

      // After compaction the log is gone: the still-lagging peer cannot be
      // served ops, and the kernel's needsSnapshotFor flips — a snapshot
      // must carry the state instead. (A fully-covered peer gets nothing,
      // exactly like the mesh exchange always did.)
      doc.compact();
      final plan2 = planner.plan(
        docs: [_DocSource(doc)],
        remoteVectors: {'d': lagging},
      );
      expect(plan2.ops, isEmpty);
      expect(plan2.states.length, 1);
      expect(plan2.states.single.docId, 'd');
    });
  });
}

/// Minimal hand-rolled [DeltaReplica] with injectable answers.
class FakeReplica implements DeltaReplica {
  FakeReplica({
    required this.docId,
    required this.vv,
    required this.pendingOps,
    final List<OpRecord> Function(VersionVector)? opsSince,
    final bool Function(VersionVector)? needsSnapshotFor,
    final Snapshot? snapshot,
  }) : _opsSince = opsSince ?? ((_) => pendingOps),
       _needsSnapshotFor = needsSnapshotFor ?? ((_) => false),
       _snapshot =
           snapshot ??
           Snapshot(
             docId: docId,
             baseVv: vv,
             state: const {},
             createdAt: const Hlc(0, 0, 'fake'),
           );

  @override
  final String docId;
  @override
  final VersionVector vv;
  @override
  final List<OpRecord> pendingOps;
  final List<OpRecord> Function(VersionVector) _opsSince;
  final bool Function(VersionVector) _needsSnapshotFor;
  final Snapshot _snapshot;

  @override
  List<OpRecord> opsSince(final VersionVector remoteVv) => _opsSince(remoteVv);

  @override
  bool needsSnapshotFor(final VersionVector remoteVv) =>
      _needsSnapshotFor(remoteVv);

  @override
  Snapshot snapshotFor() => _snapshot;
}

/// The one-line adapter the spec promises: `ConvergenceDoc` exposes exactly
/// the [DeltaReplica] members, so wrapping is mechanical.
class _DocSource implements DeltaReplica {
  _DocSource(this._doc);

  final ConvergenceDoc _doc;

  @override
  String get docId => _doc.docId;
  @override
  VersionVector get vv => _doc.vv;
  @override
  List<OpRecord> get pendingOps => _doc.pendingOps;
  @override
  List<OpRecord> opsSince(final VersionVector remoteVv) =>
      _doc.opsSince(remoteVv);
  @override
  bool needsSnapshotFor(final VersionVector remoteVv) =>
      _doc.needsSnapshotFor(remoteVv);
  @override
  Snapshot snapshotFor() => _doc.snapshotFor();
}
