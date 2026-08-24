import 'dart:math';

import 'package:test/test.dart';
import 'package:universal_storage_convergence/universal_storage_convergence.dart';

/// Three replicas emit ops locally, then receive every other replica's ops
/// in deliberately different (seeded-random) delivery orders. The kernel
/// contract: all replicas converge to byte-identical state.
void main() {
  final baseTime = DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);

  DateTime timeAt(final int ms) => baseTime.add(Duration(milliseconds: ms));

  /// Drives one replica: emits its local ops and records them for gossip.
  ({ConvergenceDoc doc, List<OpRecord> emitted}) runReplica(
    final String actorId,
    final List<Map<String, Object?>> payloads,
  ) {
    final doc = ConvergenceDoc(docId: 'doc-1', actorId: actorId);
    final emitted = <OpRecord>[];
    for (var i = 0; i < payloads.length; i++) {
      emitted.add(doc.applyLocal(payloads[i], timeAt(i * 10)));
    }
    return (doc: doc, emitted: emitted);
  }

  /// Delivers [ops] to [doc] in a seeded shuffled order, in small batches
  /// simulating flaky link chunking.
  void deliverShuffled(
    final ConvergenceDoc doc,
    final List<OpRecord> ops,
    final int seed,
  ) {
    final shuffled = [...ops]..shuffle(Random(seed));
    for (var i = 0; i < shuffled.length; i += 3) {
      final batch = shuffled.skip(i).take(3);
      doc.applyRemote(batch);
      // Duplicate delivery must be a no-op.
      doc.applyRemote(batch.take(1));
    }
  }

  test('convergence under arbitrary delivery order across replicas', () {
    final replicas = [
      runReplica('r1', [
        {'k': 'title', 'v': 'from-r1'},
        {'k': 'color', 'v': 'red'},
      ]),
      runReplica('r2', [
        {'k': 'title', 'v': 'from-r2'},
        {'k': 'count', 'v': '7'},
        {'k': 'color', 'v': 'blue'},
      ]),
      runReplica('r3', [
        {'k': 'deleted-later', 'v': 'temp'},
      ]),
    ];

    // r3 deletes what it created.
    replicas[2].doc.applyLocal({'k': 'deleted-later', 'del': true}, timeAt(50));

    final allOps = replicas.expand((final r) => r.emitted).toList()
      ..addAll(replicas[2].doc.pendingOps);

    // Each replica receives the full op set in a different order.
    deliverShuffled(replicas[0].doc, allOps, 42);
    deliverShuffled(replicas[1].doc, allOps, 7);
    // r3 already has its own ops; still receives everything.
    deliverShuffled(replicas[2].doc, allOps, 99);

    final states = replicas.map((final r) => r.doc.state).toList();
    expect(states[0], states[1]);
    expect(states[1], states[2]);

    // LWW winner for the contested 'title' key is deterministic.
    expect(
      LwwMapStrategy.readValue(states[0], 'title'),
      anyOf('from-r1', 'from-r2', 'from-r3'),
    );
    // Tombstone wins over the earlier set.
    expect(LwwMapStrategy.readValue(states[0], 'deleted-later'), isNull);
  });

  test('idempotence: re-applying the same batch changes nothing', () {
    final writer = ConvergenceDoc(docId: 'd', actorId: 'w');
    final reader = ConvergenceDoc(docId: 'd', actorId: 'r');
    final op = writer.applyLocal({'k': 'a', 'v': '1'}, timeAt(0));

    expect(reader.applyRemote([op]), 1);
    final stateAfterFirst = reader.state;
    expect(reader.applyRemote([op]), 0);
    expect(reader.state, stateAfterFirst);
  });

  test('same-millisecond concurrent writes resolve deterministically', () {
    // Both writers issue at identical wall millis + counter: actorId
    // tiebreak decides, independent of arrival order.
    const wallMs = 5_000;
    final aOp = OpRecord(
      docId: 'd',
      hlc: Hlc(wallMs, 0, 'actor-a'),
      payload: {'k': 'x', 'v': 'value-a'},
    );
    final bOp = OpRecord(
      docId: 'd',
      hlc: Hlc(wallMs, 0, 'actor-b'),
      payload: {'k': 'x', 'v': 'value-b'},
    );
    final winner = aOp.hlc > bOp.hlc ? 'value-a' : 'value-b';

    final docForward = ConvergenceDoc(docId: 'd', actorId: 'z');
    docForward.applyRemote([aOp, bOp]);
    final docReverse = ConvergenceDoc(docId: 'd', actorId: 'z');
    docReverse.applyRemote([bOp, aOp]);

    expect(LwwMapStrategy.readValue(docForward.state, 'x'), winner);
    expect(docForward.state, docReverse.state);
  });

  group('delta shipping & compaction', () {
    test('opsSince returns exactly what a lagging peer lacks', () {
      final writer = ConvergenceDoc(docId: 'd', actorId: 'w');
      final reader = ConvergenceDoc(docId: 'd', actorId: 'r');
      final op1 = writer.applyLocal({'k': 'a', 'v': '1'}, timeAt(0));
      writer.applyLocal({'k': 'b', 'v': '2'}, timeAt(10));

      final laggingVv = VersionVector.zero.observed(op1.hlc);
      final missing = writer.opsSince(laggingVv);
      expect(missing, hasLength(1));
      expect(missing.first.payload['k'], 'b');

      reader.applyRemote(writer.opsSince(VersionVector.zero));
      expect(writer.needsSnapshotFor(laggingVv), isFalse);
    });

    test('compact retires the log; snapshot adoption covers compacted peers', () {
      final writer = ConvergenceDoc(docId: 'd', actorId: 'w');
      writer.applyLocal({'k': 'a', 'v': '1'}, timeAt(0));
      writer.applyLocal({'k': 'b', 'v': '2'}, timeAt(10));

      expect(writer.compact(), 2);
      expect(writer.pendingOps, isEmpty);

      // A peer that never saw anything can no longer be served by deltas.
      expect(writer.needsSnapshotFor(VersionVector.zero), isTrue);

      final lateJoiner = ConvergenceDoc(docId: 'd', actorId: 'late');
      lateJoiner.adoptSnapshot(writer.snapshotFor());
      expect(LwwMapStrategy.readValue(lateJoiner.state, 'a'), '1');
      expect(LwwMapStrategy.readValue(lateJoiner.state, 'b'), '2');
    });

    test('adopting an older snapshot keeps newer local pending ops', () {
      final writer = ConvergenceDoc(docId: 'd', actorId: 'w');
      writer.applyLocal({'k': 'a', 'v': '1'}, timeAt(0));
      final stale = writer.snapshotFor();
      writer.applyLocal({'k': 'a', 'v': '2'}, timeAt(10));

      final peer = ConvergenceDoc(docId: 'd', actorId: 'p');
      expect(peer.adoptSnapshot(stale), isTrue);
      expect(peer.adoptSnapshot(writer.snapshotFor()), isTrue);
      expect(LwwMapStrategy.readValue(peer.state, 'a'), '2');
    });
  });
}
