import 'dart:math';

import 'package:test/test.dart';
import 'package:universal_storage_convergence/universal_storage_convergence.dart';

/// ADR 0029 contract tests: the RGA-text sequence strategy pulled forward
/// for streamed agent text, and the ephemeral op class (presence registry).
///
/// Kernel obligations (ADR 0011 §2, ADR 0029 §1): every shipped strategy
/// is commutative and idempotent — any replica order of the same op set
/// yields identical state — and ephemeral expiry is commutative and
/// idempotent too.
void main() {
  final baseTime = DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);
  var tick = 0;
  DateTime nextTime() => baseTime.add(Duration(milliseconds: tick++ * 10));

  setUp(() => tick = 0);

  group('RgaTextStrategy — convergence under arbitrary delivery order', () {
    /// Builds three replicas with causally-chained inserts and one
    /// cross-anchor concurrent insert per replica, then delivers every
    /// op to every replica in a seeded shuffled order (with duplicate
    /// redelivery) and asserts byte-identical text.
    List<ConvergenceDoc> buildReplicas() {
      final docs = [
        for (final actor in ['r1', 'r2', 'r3'])
          ConvergenceDoc(
            docId: 'doc',
            actorId: actor,
            strategy: const RgaTextStrategy(),
          ),
      ];
      final r1 = docs[0];
      final r2 = docs[1];
      final r3 = docs[2];

      // Causal chain on r1: 'Hello ' then '!' anchored after its own tail.
      final hello = r1.applyLocal({
        'k': 'body',
        'after': null,
        'text': 'Hello ',
      }, nextTime());
      final helloTail = '${hello.opId}#5';
      r1.applyLocal({'k': 'body', 'after': helloTail, 'text': '!'}, nextTime());

      // Concurrent root insert on r2 and mid-text insert on r3.
      r2.applyLocal({'k': 'body', 'after': null, 'text': 'world'}, nextTime());
      r3.applyLocal({
        'k': 'body',
        'after': '${hello.opId}#1',
        'text': 'XYZ',
      }, nextTime());
      return docs;
    }

    List<OpRecord> allOps(final List<ConvergenceDoc> docs) => [
      for (final doc in docs) ...doc.pendingOps,
    ];

    void deliverShuffled(
      final ConvergenceDoc doc,
      final List<OpRecord> ops,
      final int seed,
    ) {
      final shuffled = [...ops]..shuffle(Random(seed));
      for (var i = 0; i < shuffled.length; i += 2) {
        final batch = shuffled.skip(i).take(2);
        doc.applyRemote(batch);
        // Duplicate redelivery must be a no-op.
        doc.applyRemote(batch.take(1));
      }
    }

    test('three replicas converge to identical text', () {
      final docs = buildReplicas();
      final ops = allOps(docs);
      for (var i = 0; i < docs.length; i++) {
        deliverShuffled(docs[i], ops, 10 + i);
      }
      final texts = docs
          .map((final d) => RgaTextStrategy.readText(d.state, 'body'))
          .toList();
      expect(texts[0], isNotNull);
      expect(texts[0], texts[1]);
      expect(texts[1], texts[2]);
      // Every emitted character survives (15 total, repeats are legal).
      expect(texts[0]!.length, 15);
      expect(texts[0], contains('Hello '));
      expect(texts[0], contains('!'));
      expect(texts[0], contains('world'));
      expect(texts[0], contains('XYZ'));
    });

    test('delete converges and tombstones win regardless of arrival order', () {
      final docs = buildReplicas();
      final ops = allOps(docs);

      // r3 deletes the two elements r1 emitted first ('H', 'e').
      final helloId = ops
          .firstWhere(
            (final op) =>
                op.actorId == 'r1' &&
                op.payload['text'] == 'Hello ' &&
                op.payload['del'] == null,
          )
          .opId;
      docs[2].applyLocal({
        'k': 'body',
        'del': ['$helloId#0', '$helloId#1'],
      }, nextTime());
      final all = [...ops, ...docs[2].pendingOps];
      for (var i = 0; i < docs.length; i++) {
        deliverShuffled(docs[i], all, 40 + i);
      }
      final texts = docs
          .map((final d) => RgaTextStrategy.readText(d.state, 'body'))
          .toList();
      expect(texts[0], texts[1]);
      expect(texts[1], texts[2]);
      expect(texts[0], startsWith('llo '));
    });

    test('out-of-order delivery: insert arrives before its anchor', () {
      final a = ConvergenceDoc(
        docId: 'doc',
        actorId: 'a',
        strategy: const RgaTextStrategy(),
      );
      final b = ConvergenceDoc(
        docId: 'doc',
        actorId: 'b',
        strategy: const RgaTextStrategy(),
      );
      final anchor = a.applyLocal({
        'k': 'body',
        'after': null,
        'text': 'A',
      }, nextTime());
      final second = a.applyLocal({
        'k': 'body',
        'after': '${anchor.opId}#0',
        'text': 'B',
      }, nextTime());
      // Deliver the SECOND op first — its anchor is unknown on b, so the
      // element is retained but NOT YET visible (honest intermediate:
      // convergence is over the final op set, not partial deliveries).
      b.applyRemote([second]);
      expect(RgaTextStrategy.readText(b.state, 'body'), '');
      b.applyRemote([anchor]);
      expect(RgaTextStrategy.readText(b.state, 'body'), 'AB');
      expect(RgaTextStrategy.readText(a.state, 'body'), 'AB');
    });

    test('serialization round-trip preserves text and strategy name', () {
      final doc = ConvergenceDoc(
        docId: 'doc',
        actorId: 'a',
        strategy: const RgaTextStrategy(),
      );
      doc.applyLocal({'k': 'body', 'after': null, 'text': 'Hi'}, nextTime());
      final restored = ConvergenceDoc.fromJson(doc.toJson());
      expect(restored.strategy.name, 'rga_text');
      expect(
        RgaTextStrategy.readText(restored.state, 'body'),
        RgaTextStrategy.readText(doc.state, 'body'),
      );
    });

    test('invalid payloads are named data, never silent corruption', () {
      final doc = ConvergenceDoc(
        docId: 'doc',
        actorId: 'a',
        strategy: const RgaTextStrategy(),
      );
      expect(
        () => doc.applyLocal({
          'k': 'body',
          'after': null,
          'text': '',
        }, nextTime()),
        throwsArgumentError,
      );
      expect(
        () => doc.applyLocal({'k': 'body', 'del': <String>[]}, nextTime()),
        throwsArgumentError,
      );
    });
  });

  group('Ephemeral ops (ADR 0029 §1) — presence registry', () {
    test('never fold into durable state, log, snapshot, or version vector', () {
      final doc = ConvergenceDoc(docId: 'd', actorId: 'a');
      doc.applyLocalEphemeral(
        {'k': 'presence:a', 'v': 'editing'},
        baseTime,
        ttl: const Duration(seconds: 30),
      );
      expect(doc.state, isEmpty, reason: 'durable state must stay empty');
      expect(doc.pendingOps, isEmpty, reason: 'durable delta log stays empty');
      expect(doc.vv['a'], isNull, reason: 'ephemeral ops never advance the VV');
      final snap = doc.snapshotFor();
      expect(snap.state, isEmpty, reason: 'snapshots exclude ephemeral folds');
      expect(
        LwwMapStrategy.readValue(doc.ephemeralState, 'presence:a'),
        'editing',
      );
    });

    test('no opId collision: durable op after ephemeral op is distinct', () {
      final doc = ConvergenceDoc(docId: 'd', actorId: 'a');
      final ephemeral = doc.applyLocalEphemeral(
        {'k': 'presence', 'v': 'x'},
        baseTime,
        ttl: const Duration(seconds: 5),
      );
      final durable = doc.applyLocal({'k': 'k', 'v': '1'}, baseTime);
      expect(durable.opId, isNot(ephemeral.opId));
      // And the durable op is not silently deduped by the ephemeral one.
      expect(doc.state['k'], isNotNull);
      expect(doc.pendingOps, hasLength(1));
    });

    test('remote delivery: applied before expiry, dropped after', () {
      final issuer = ConvergenceDoc(docId: 'd', actorId: 'a');
      final op = issuer.applyLocalEphemeral(
        {'k': 'presence:a', 'v': 'here'},
        baseTime,
        ttl: const Duration(seconds: 30),
      );

      final live = ConvergenceDoc(docId: 'd', actorId: 'b');
      expect(
        live.applyRemote([op], now: baseTime.add(const Duration(seconds: 1))),
        1,
      );
      expect(
        LwwMapStrategy.readValue(live.ephemeralState, 'presence:a'),
        'here',
      );
      expect(live.pendingEphemeralOps, hasLength(1));

      final late = ConvergenceDoc(docId: 'd', actorId: 'c');
      expect(
        late.applyRemote([op], now: baseTime.add(const Duration(seconds: 31))),
        0,
        reason: 'expired ephemeral ops are dropped on apply',
      );
      expect(late.ephemeralState, isEmpty);
      // Redelivery after expiry is still dropped (deduped, not re-folded).
      expect(
        late.applyRemote([op], now: baseTime.add(const Duration(seconds: 31))),
        0,
      );
    });

    test('sweepEphemeral drops expired ops and re-folds the registry', () {
      final doc = ConvergenceDoc(docId: 'd', actorId: 'a');
      doc.applyLocalEphemeral(
        {'k': 'presence:a', 'v': 'here'},
        baseTime,
        ttl: const Duration(seconds: 10),
      );
      doc.applyLocalEphemeral(
        {'k': 'presence:b', 'v': 'there'},
        baseTime.add(const Duration(seconds: 5)),
        ttl: const Duration(minutes: 10),
      );
      final dropped = doc.sweepEphemeral(
        baseTime.add(const Duration(seconds: 30)),
      );
      expect(dropped, 1);
      expect(
        LwwMapStrategy.readValue(doc.ephemeralState, 'presence:a'),
        isNull,
      );
      expect(
        LwwMapStrategy.readValue(doc.ephemeralState, 'presence:b'),
        'there',
      );
      // Idempotent: a second sweep at the same time drops nothing.
      expect(doc.sweepEphemeral(baseTime.add(const Duration(seconds: 30))), 0);
    });

    test('compaction keeps ephemeral dedupe intact', () {
      final doc = ConvergenceDoc(docId: 'd', actorId: 'a');
      doc.applyLocal({'k': 'durable', 'v': '1'}, baseTime);
      doc.applyLocalEphemeral(
        {'k': 'presence', 'v': 'x'},
        baseTime,
        ttl: const Duration(minutes: 5),
      );
      doc.compact();
      // Ephemeral ops are still deduped after compaction.
      final peer = ConvergenceDoc(docId: 'd', actorId: 'b');
      final allEphemeral = doc.pendingEphemeralOps;
      peer.applyRemote(allEphemeral, now: baseTime);
      expect(peer.applyRemote(allEphemeral, now: baseTime), 0);
    });

    test('serialization round-trip restores the ephemeral registry', () {
      final doc = ConvergenceDoc(docId: 'd', actorId: 'a');
      doc.applyLocalEphemeral(
        {'k': 'presence:a', 'v': 'here'},
        baseTime,
        ttl: const Duration(minutes: 5),
      );
      final restored = ConvergenceDoc.fromJson(doc.toJson());
      expect(restored.pendingEphemeralOps, hasLength(1));
      expect(
        LwwMapStrategy.readValue(restored.ephemeralState, 'presence:a'),
        'here',
      );
    });
  });
}
