import 'package:test/test.dart';
import 'package:universal_storage_convergence/universal_storage_convergence.dart';

void main() {
  group('Hlc', () {
    test('tick is strictly monotonic across wall-clock regression', () {
      final actor = 'a';
      var clock = Hlc.zero(actor);
      final t1 = DateTime.fromMillisecondsSinceEpoch(1000);
      clock = clock.tick(t1);
      // Wall clock regresses.
      clock = clock.tick(DateTime.fromMillisecondsSinceEpoch(500));
      final afterRegression = clock.tick(
        DateTime.fromMillisecondsSinceEpoch(500),
      );
      expect(afterRegression > clock, isTrue);
      expect(clock > Hlc(1000, 0, actor), isTrue);
    });

    test('receive stays strictly above remote and local', () {
      final a = Hlc(1000, 5, 'a');
      final b = Hlc(1000, 9, 'b');
      final received = a.receive(b, DateTime.fromMillisecondsSinceEpoch(999));
      expect(received > a, isTrue);
      expect(received > b, isTrue);
      expect(received.actorId, 'a');
    });

    test('restore keeps monotonicity across process restart', () {
      final persisted = Hlc(2000, 7, 'a');
      // Wall clock behind persisted value.
      final restored = hlcRestoreMonotonic(
        persistedLast: persisted,
        now: DateTime.fromMillisecondsSinceEpoch(1500),
      );
      final next = restored.tick(DateTime.fromMillisecondsSinceEpoch(1500));
      expect(next > persisted, isTrue);
    });

    test('json and string round-trips', () {
      const hlc = Hlc(1234, 56, 'actor-1');
      expect(Hlc.fromJson(hlc.toJson()), hlc);
      expect(Hlc.fromString(hlc.toString()), hlc);
    });
  });

  group('VersionVector', () {
    test('contains dedupes per-actor monotonic events', () {
      var vv = VersionVector.zero;
      final h1 = Hlc(10, 0, 'a');
      final h2 = h1.tick(DateTime.fromMillisecondsSinceEpoch(11));
      vv = vv.observed(h1);
      expect(vv.contains(h1), isTrue);
      expect(vv.contains(h2), isFalse);
      vv = vv.observed(h2);
      expect(vv.contains(h2), isTrue);
    });

    test('observed never regresses', () {
      final older = Hlc(10, 0, 'a');
      final newer = Hlc(20, 0, 'a');
      final vv = VersionVector.zero.observed(newer).observed(older);
      expect(vv['a'], newer);
    });
  });
}
