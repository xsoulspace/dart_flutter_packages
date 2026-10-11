import 'dart:math';

import 'package:test/test.dart';
import 'package:universal_storage_convergence/universal_storage_convergence.dart';
import 'package:universal_storage_convergence_session/universal_storage_convergence_session.dart';

/// ReceiveWatermark contract tests: the HLC receive rule (causality floor
/// for local writes after folding remote state), its raise-only
/// monotonicity, durable restore, and the ahead-wall-clock scenario that
/// motivates the whole type.
///
/// Coverage is a (wall, counter) notion, never a full-HLC compareTo: the
/// watermark is re-anchored to the receiver's actor, so its HLC never
/// travels and its actor never participates in ordering.
bool covers(final Hlc watermark, final Hlc delivery) =>
    watermark.wallMillis > delivery.wallMillis ||
    (watermark.wallMillis == delivery.wallMillis &&
        watermark.counter >= delivery.counter);

void main() {
  final realNow = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  group('basics', () {
    test('a fresh watermark has no value', () {
      expect(ReceiveWatermark(actorId: 'local').value, isNull);
    });

    test('observe raises and keeps the receiver actor id', () {
      final wm = ReceiveWatermark(actorId: 'local');
      const remote = Hlc(1700000000005, 0, 'remote');
      wm.observe(remote);
      final value = wm.value!;
      expect(value.actorId, 'local');
      expect(
        covers(value, remote),
        isTrue,
        reason: 'the watermark must cover the delivery (wall, counter)',
      );
    });

    test('observe is raise-only: older or equal deliveries are no-ops', () {
      final wm = ReceiveWatermark(actorId: 'local');
      const ahead = Hlc(1700000000100, 7, 'remote');
      wm.observe(ahead);
      final after = wm.value!;
      wm
        ..observe(const Hlc(1, 0, 'other'))
        ..observe(ahead);
      expect(wm.value, after);
    });

    test('observeSnapshot absorbs the snapshot createdAt', () {
      final wm = ReceiveWatermark(actorId: 'local');
      const createdAt = Hlc(1700000000042, 3, 'remote');
      wm.observeSnapshot(
        Snapshot(
          docId: 'd',
          baseVv: VersionVector(const {'remote': createdAt}),
          state: const {},
          createdAt: createdAt,
        ),
      );
      expect(covers(wm.value!, createdAt), isTrue);
    });

    test('floorNow raises a behind clock to the watermark wall clock', () {
      final wm = ReceiveWatermark(actorId: 'local');
      expect(wm.floorNow(realNow), realNow); // nothing received yet
      const aheadWall = 4000000000000; // year 2096
      wm.observe(const Hlc(aheadWall, 0, 'remote'));
      final behind = DateTime.fromMillisecondsSinceEpoch(1700000000001);
      final floored = wm.floorNow(behind);
      expect(floored.millisecondsSinceEpoch, aheadWall);
      expect(
        wm
            .floorNow(DateTime.fromMillisecondsSinceEpoch(aheadWall + 1))
            .millisecondsSinceEpoch,
        aheadWall + 1,
      );
    });
  });

  group('persistence', () {
    test('JSON round-trip with and without a value', () {
      final fresh = ReceiveWatermark(actorId: 'local');
      final restored = ReceiveWatermark.fromJson(fresh.toJson());
      expect(restored.actorId, 'local');
      expect(restored.value, isNull);

      final wm = ReceiveWatermark(actorId: 'local');
      const remote = Hlc(1700000000005, 9, 'remote');
      wm.observe(remote);
      final restored2 = ReceiveWatermark.fromJson(wm.toJson());
      expect(restored2.actorId, 'local');
      expect(restored2.value, wm.value);
      expect(restored2.value!.wallMillis, wm.value!.wallMillis);
      expect(restored2.value!.counter, wm.value!.counter);
      expect(restored2.value!.actorId, 'local');
    });

    test('a restored watermark keeps ordering later local writes', () {
      const aheadOpHlc = Hlc(4000000000000, 0, 'remote');
      final wm = ReceiveWatermark(actorId: 'local')
        ..observe(aheadOpHlc);
      final restored = ReceiveWatermark.fromJson(wm.toJson());

      final doc = ConvergenceDoc(docId: 'd', actorId: 'local');
      final op = doc.applyLocal(
        const {'k': 'x', 'v': 'after-restore'},
        realNow,
        lastIssued: restored.value,
      );
      expect(op.hlc > aheadOpHlc, isTrue);
    });
  });

  group('the ahead-clock scenario (why the watermark exists)', () {
    const aheadWall = 4000000000000; // remote clock ~year 2096
    const remoteOp = OpRecord(
      docId: 'd',
      hlc: Hlc(aheadWall, 0, 'remote'),
      payload: {'k': 'x', 'v': 'remote-value'},
    );

    test('WITHOUT the watermark, the ahead-clock remote op wins forever', () {
      final doc = ConvergenceDoc(docId: 'd', actorId: 'local')
        ..applyRemote([remoteOp]);
      final localOp = doc.applyLocal(const {
        'k': 'x',
        'v': 'local-value',
      }, realNow);
      expect(localOp.hlc > remoteOp.hlc, isFalse);
      expect(LwwMapStrategy.readValue(doc.state, 'x'), 'remote-value');
    });

    test(
      'WITH the watermark, the later local write wins LWW on both sides',
      () {
        final doc = ConvergenceDoc(docId: 'd', actorId: 'local')
          ..applyRemote([remoteOp]);
        final wm = ReceiveWatermark(actorId: 'local')
          ..observe(remoteOp.hlc);

        final localOp = doc.applyLocal(
          const {'k': 'x', 'v': 'local-value'},
          wm.floorNow(realNow),
          lastIssued: wm.value,
        );
        expect(localOp.hlc > remoteOp.hlc, isTrue);
        expect(LwwMapStrategy.readValue(doc.state, 'x'), 'local-value');

        // A peer that folds both ops in either order lands on the local value:
        // LWW reads the higher HLC, and the local op carries it.
        final otherSide = ConvergenceDoc(docId: 'd', actorId: 'peer2')
          ..applyRemote([remoteOp, localOp]);
        expect(LwwMapStrategy.readValue(otherSide.state, 'x'), 'local-value');
        final otherSide2 = ConvergenceDoc(docId: 'd', actorId: 'peer2')
          ..applyRemote([localOp, remoteOp]);
        expect(LwwMapStrategy.readValue(otherSide2.state, 'x'), 'local-value');
      },
    );
  });

  group('monotonicity property (seeded random delivery)', () {
    test(
      'watermark never regresses and ends strictly above every delivery',
      () {
        final random = Random(42);
        final actors = ['r1', 'r2', 'r3'];
        final deliveries = [
          for (var i = 0; i < 200; i++)
            Hlc(
              random.nextInt(1_000_000),
              random.nextInt(100),
              actors[random.nextInt(actors.length)],
            ),
        ];
        final wm = ReceiveWatermark(actorId: 'local');
        Hlc? previous;
        for (final delivery in deliveries) {
          wm.observe(delivery);
          final current = wm.value;
          expect(current, isNotNull);
          if (previous != null) {
            expect(
              current! >= previous,
              isTrue,
              reason: 'watermark regressed at $delivery',
            );
          }
          previous = current;
        }
        for (final delivery in deliveries) {
          expect(
            covers(wm.value!, delivery),
            isTrue,
            reason: 'watermark does not cover $delivery',
          );
        }
      },
    );
  });
}
