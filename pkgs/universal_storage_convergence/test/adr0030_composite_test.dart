import 'dart:math';

import 'package:test/test.dart';
import 'package:universal_storage_convergence/universal_storage_convergence.dart';

/// ADR 0030 contract tests: the composite merge strategy (one document,
/// one kernel doc, key-prefix lane dispatch).
///
/// Kernel obligations (ADR 0011 §2, extended by ADR 0030 §1):
/// - **Commutativity by inheritance**: when every lane is
///   commutative/idempotent, the composite is too — for any delivery
///   order, any lane interleaving, and any batch split;
/// - snapshots fold all lanes atomically (a peer is never half-covered);
/// - an op matching no lane is a NAMED error, never dropped;
/// - the lane map is wire-stable and restorable via
///   `ConvergenceDoc.fromJson`; a lane-map mismatch on restore is a
///   named error.
void main() {
  final baseTime = DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);
  var tick = 0;
  DateTime nextTime() => baseTime.add(Duration(milliseconds: tick++ * 10));

  /// The DocReplica lane shape (ADR 0030 §1 driving consumer): LWW lanes
  /// for `node/*` + `order/*`, RGA lane for `text/*`.
  const lanes = <String, MergeStrategy>{
    'node/': LwwMapStrategy(),
    'order/': LwwMapStrategy(),
    'text/': RgaTextStrategy(),
  };

  const spec = 'composite:node/=>lww_map,order/=>lww_map,text/=>rga_text';

  setUp(() => tick = 0);

  ConvergenceDoc compositeDoc(final String actorId) => ConvergenceDoc(
    docId: 'doc-1',
    actorId: actorId,
    strategy: CompositeMergeStrategy(lanes),
  );

  group('CompositeMergeStrategy — lane dispatch', () {
    test('registry name is the wire-stable composite spec', () {
      expect(CompositeMergeStrategy(lanes).name, spec);
    });

    test('fromJson restores the full lane map without parent re-routing', () {
      final doc = compositeDoc('a')
        ..applyLocal({'k': 'node/x/field', 'v': 'v1'}, nextTime())
        ..applyLocal({'k': 'text/x', 'after': null, 'text': 'hi'}, nextTime());

      final restored = ConvergenceDoc.fromJson(doc.toJson());
      expect(restored.strategy.name, spec);
      expect(restored.strategy, isA<CompositeMergeStrategy>());
      expect(
        LwwMapStrategy.readValue(restored.state, 'node/x/field'),
        'v1',
      );
      expect(RgaTextStrategy.readText(restored.state, 'text/x'), 'hi');

      // Restored doc still dispatches: new ops fold through the right lane.
      restored.applyLocal({'k': 'node/x/field', 'v': 'v2'}, nextTime());
      final anchorId = doc.pendingOps.last.opId;
      restored.applyLocal(
        {'k': 'text/x', 'after': '$anchorId#1', 'text': '!'},
        nextTime(),
      );
      expect(LwwMapStrategy.readValue(restored.state, 'node/x/field'), 'v2');
      expect(RgaTextStrategy.readText(restored.state, 'text/x'), 'hi!');
    });

    test('longest-matching prefix wins', () {
      final doc = ConvergenceDoc(
        docId: 'd',
        actorId: 'a',
        strategy: CompositeMergeStrategy({
          'a/': const RgaTextStrategy(),
          'a/b/': const LwwMapStrategy(),
        }),
      )
        ..applyLocal({'k': 'a/b/x', 'v': 'lww'}, nextTime())
        ..applyLocal({'k': 'a/c', 'after': null, 'text': 'rga'}, nextTime());
      // `a/b/x` went to the LWW lane (register entry shape)…
      final entry = doc.state['a/b/x'];
      expect(entry, isA<Map>());
      expect((entry! as Map)['hlc'], isNotNull);
      // …and `a/c` to the RGA lane (bucket shape).
      final bucket = doc.state['a/c'];
      expect(bucket, isA<Map>());
      expect((bucket! as Map)['nodes'], isNotNull);
    });

    test('an op matching no lane is a named error, never dropped', () {
      final doc = compositeDoc('a');
      final op = OpRecord(
        docId: 'doc-1',
        hlc: Hlc(baseTime.millisecondsSinceEpoch, 0, 'z'),
        payload: const {'k': 'unknown/namespace/key', 'v': 'x'},
      );
      expect(
        () => doc.applyRemote([op]),
        throwsA(
          isA<CompositeLaneMismatchError>().having(
            (final e) => e.toString(),
            'toString',
            contains('unknown/namespace/key'),
          ),
        ),
      );
      // Refused, not folded: state stays untouched.
      expect(doc.state, isEmpty);
      // And the op was NOT marked seen — redelivery retries the fold
      // (named error again), never a silent skip.
      doc.applyLocal({'k': 'node/f', 'v': 'ok'}, nextTime());
      expect(
        () => doc.applyRemote([op]),
        throwsA(isA<CompositeLaneMismatchError>()),
      );
    });

    test('malformed lane maps and specs are named errors', () {
      expect(
        () => CompositeMergeStrategy(const {}),
        throwsArgumentError,
      );
      expect(
        () => CompositeMergeStrategy({'': const LwwMapStrategy()}),
        throwsArgumentError,
      );
      final dup = <String, MergeStrategy>{'a/': const LwwMapStrategy()};
      dup['a/'] = const RgaTextStrategy();
      expect(CompositeMergeStrategy(dup).lanes['a/'], isA<RgaTextStrategy>());
      expect(
        () => CompositeMergeStrategy({'a,b/': const LwwMapStrategy()}),
        throwsArgumentError,
      );
      // Lane-map mismatch on restore: unknown sub-strategy is named.
      expect(
        () => ConvergenceDoc.strategyFor('composite:a/=>does_not_exist'),
        throwsA(
          isA<ArgumentError>().having(
            (final e) => e.toString(),
            'toString',
            contains('does_not_exist'),
          ),
        ),
      );
      expect(
        () => CompositeMergeStrategy.fromSpec('a=>lww_map,bogus'),
        throwsArgumentError,
      );
      expect(() => CompositeMergeStrategy.fromSpec(''), throwsArgumentError);
    });
  });

  group('CompositeMergeStrategy — commutativity by inheritance', () {
    /// Three replicas emit ops across ALL lanes in interleaved order
    /// (causally chained where the RGA needs anchors).
    List<ConvergenceDoc> buildReplicas() {
      final docs = [
        for (final actor in ['r1', 'r2', 'r3']) compositeDoc(actor),
      ];
      final r1 = docs[0];
      final r2 = docs[1];
      final r3 = docs[2];

      // r1: LWW field, order register, RGA chain anchor.
      r1
        ..applyLocal({'k': 'node/n1/title', 'v': 'r1'}, nextTime())
        ..applyLocal({'k': 'order/n1/c1', 'v': 'n'}, nextTime());
      final hello = r1.applyLocal(
        {'k': 'text/b1', 'after': null, 'text': 'Hello '},
        nextTime(),
      );
      r1.applyLocal(
        {'k': 'text/b1', 'after': '${hello.opId}#5', 'text': '!'},
        nextTime(),
      );

      // r2: conflicting LWW write, disjoint order register, concurrent RGA.
      r2
        ..applyLocal({'k': 'node/n1/title', 'v': 'r2'}, nextTime())
        ..applyLocal({'k': 'order/n1/c2', 'v': 'a'}, nextTime())
        ..applyLocal(
          {'k': 'text/b1', 'after': null, 'text': 'world'},
          nextTime(),
        )
        ..applyLocal({'k': 'node/n2/level', 'v': '3'}, nextTime());

      // r3: interleaved across all three lanes, plus an LWW tombstone.
      r3
        ..applyLocal({'k': 'text/b2', 'after': null, 'text': 'x'}, nextTime())
        ..applyLocal({'k': 'node/n1/title', 'v': 'r3'}, nextTime())
        ..applyLocal({'k': 'order/n1/c0', 'v': 'm'}, nextTime())
        ..applyLocal({'k': 'node/n2/level', 'del': true}, nextTime());
      return docs;
    }

    List<OpRecord> allOps(final List<ConvergenceDoc> docs) => [
      for (final doc in docs) ...doc.pendingOps,
    ];

    /// Delivers [ops] to [doc] in seeded-shuffled [batchSize]-sized chunks
    /// with duplicate redelivery inside each batch.
    void deliverShuffled(
      final ConvergenceDoc doc,
      final List<OpRecord> ops,
      final int seed, {
      final int batchSize = 3,
    }) {
      final shuffled = [...ops]..shuffle(Random(seed));
      for (var i = 0; i < shuffled.length; i += batchSize) {
        final batch = shuffled.skip(i).take(batchSize).toList();
        doc
          ..applyRemote(batch)
          ..applyRemote(batch.take(1));
      }
    }

    test('any delivery order, lane interleaving, and batch split converges',
        () {
      final docs = buildReplicas();
      final ops = allOps(docs);

      final orders = <int, int>{
        11: 1, // single-op batches, arbitrary order
        22: 2,
        33: 3,
        44: ops.length, // one huge batch
      };
      final seen = <Map<String, Object?>>[];
      for (final MapEntry(key: seed, value: batchSize) in orders.entries) {
        final doc = compositeDoc('observer');
        deliverShuffled(doc, ops, seed, batchSize: batchSize);
        seen.add(doc.state);
      }
      // Writers converge with the observers too.
      deliverShuffled(docs[0], ops, 55);
      deliverShuffled(docs[1], ops, 66, batchSize: 5);
      deliverShuffled(docs[2], ops, 77, batchSize: 4);
      seen.addAll(docs.map((final d) => d.state));

      for (final state in seen) {
        expect(state, seen.first, reason: 'states diverged: $state');
      }

      // One fold outcome, deterministic content across lanes.
      final state = seen.first;
      expect(LwwMapStrategy.readValue(state, 'node/n1/title'), isNotNull);
      expect(LwwMapStrategy.readValue(state, 'node/n2/level'), isNull,
          reason: 'tombstone wins');
      expect(
        RgaTextStrategy.readText(state, 'text/b1'),
        RgaTextStrategy.readText(docs[0].state, 'text/b1'),
      );
    });

    test('composite fold equals per-lane folds merged (inheritance)', () {
      final docs = buildReplicas();
      final ops = allOps(docs);

      final composite = compositeDoc('inherit');
      deliverShuffled(composite, ops, 7);

      // Fold every op through a standalone per-lane doc (only the ops
      // whose key the lane owns), then merge — disjoint prefixes mean the
      // merged map must equal the composite's.
      final perLane = {
        for (final prefix in lanes.keys)
          prefix: ConvergenceDoc(
            docId: 'doc-1',
            actorId: 'inherit',
            strategy: lanes[prefix]!,
          ),
      };
      for (final MapEntry(key: prefix, value: doc) in perLane.entries) {
        deliverShuffled(
          doc,
          ops
              .where(
                (final op) =>
                    op.payload['k'] is String &&
                    (op.payload['k']! as String).startsWith(prefix),
              )
              .toList(),
          8 + prefix.length,
        );
      }
      final merged = <String, Object?>{
        for (final doc in perLane.values) ...doc.state,
      };
      expect(composite.state, merged);
    });

    test('one VV, one log, one snapshot decision for the whole doc', () {
      final doc = compositeDoc('a')
        ..applyLocal({'k': 'node/f', 'v': '1'}, nextTime())
        ..applyLocal({'k': 'text/b', 'after': null, 'text': 'x'}, nextTime())
        ..applyLocal({'k': 'order/p/c', 'v': 'n'}, nextTime());

      // All three lanes advanced the ONE version vector.
      expect(doc.vv.actors, ['a']);
      // The ONE log carries all lanes' ops.
      expect(doc.pendingOps, hasLength(3));
      expect(doc.pendingOps.map((final op) => op.payload['k']), containsAll([
        'node/f',
        'text/b',
        'order/p/c',
      ]));
    });
  });

  group('CompositeMergeStrategy — atomic snapshot coverage', () {
    test('snapshot folds ALL lanes; adopting peers are never half-covered',
        () {
      final writer = compositeDoc('writer')
        ..applyLocal({'k': 'node/n1/title', 'v': 't'}, nextTime())
        ..applyLocal({'k': 'order/n1/c1', 'v': 'n'}, nextTime())
        ..applyLocal(
        {'k': 'text/b1', 'after': null, 'text': 'body'},
        nextTime(),
      );

      final snapshot = writer.snapshotFor();
      // Snapshot state == folded state across every lane.
      expect(snapshot.state, writer.state);
      expect(
        LwwMapStrategy.readValue(snapshot.state, 'node/n1/title'),
        't',
      );
      expect(
        LwwMapStrategy.readValue(snapshot.state, 'order/n1/c1'),
        'n',
      );
      expect(RgaTextStrategy.readText(snapshot.state, 'text/b1'), 'body');

      // A peer adopting the snapshot gets every lane at once.
      final peer = compositeDoc('peer');
      expect(peer.adoptSnapshot(snapshot), isTrue);
      expect(peer.state, writer.state);
      expect(peer.vv.toJson(), writer.vv.toJson());
      expect(writer.needsSnapshotFor(peer.vv), isFalse);
    });

    test('snapshot + compaction serve lagging peers across all lanes', () {
      final writer = compositeDoc('writer')
        ..applyLocal({'k': 'node/n1/title', 'v': 't'}, nextTime())
        ..applyLocal({'k': 'order/n1/c1', 'v': 'n'}, nextTime())
        ..applyLocal(
        {'k': 'text/b1', 'after': null, 'text': 'body'},
        nextTime(),
      );
      expect(writer.compact(), 3);
      expect(writer.pendingOps, isEmpty);
      expect(writer.needsSnapshotFor(VersionVector.zero), isTrue);

      final lateJoiner = compositeDoc('late')
        ..adoptSnapshot(writer.snapshotFor());
      expect(lateJoiner.state, writer.state);
    });
  });
}
