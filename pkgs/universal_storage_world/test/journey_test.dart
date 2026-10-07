import 'package:test/test.dart';
import 'package:universal_storage_world/universal_storage_world.dart';

void main() {
  group('JourneyState', () {
    test('canonical warm journey passes through every phase', () {
      final journey = JourneyState();
      expect(journey.phase, JourneyPhase.idle);

      journey.transitionTo(
        JourneyPhase.subscribing,
        targetDocId: 'zones/dungeon',
      );
      expect(journey.targetDocId, 'zones/dungeon');
      journey.transitionTo(JourneyPhase.warming);
      journey.transitionTo(JourneyPhase.switching);
      journey.transitionTo(JourneyPhase.catchingUp);
      journey.transitionTo(JourneyPhase.settled);
      journey.transitionTo(JourneyPhase.idle);

      expect(journey.isIdle, isTrue);
      expect(journey.targetDocId, isNull);
    });

    test('cold journey skips warming (still no loader)', () {
      final journey = JourneyState();
      journey.transitionTo(JourneyPhase.switching, targetDocId: 'zones/x');
      journey.transitionTo(JourneyPhase.settled);
      expect(journey.phase, JourneyPhase.settled);
    });

    test('switching may go straight to settled when nothing to catch up', () {
      final journey = JourneyState()
        ..transitionTo(JourneyPhase.subscribing)
        ..transitionTo(JourneyPhase.switching)
        ..transitionTo(JourneyPhase.settled);
      expect(journey.phase, JourneyPhase.settled);
    });

    test('abort is legal from any phase', () {
      const path = [
        JourneyPhase.subscribing,
        JourneyPhase.warming,
        JourneyPhase.switching,
        JourneyPhase.catchingUp,
        JourneyPhase.settled,
      ];
      for (final target in path) {
        final journey = JourneyState();
        for (final step in path) {
          journey.transitionTo(step);
          if (step == target) break;
        }
        expect(journey.phase, target);
        journey.abort();
        expect(journey.isIdle, isTrue);
      }
    });

    test('out-of-order moves throw loudly (orchestration bug)', () {
      final journey = JourneyState();
      expect(
        () => journey.transitionTo(JourneyPhase.catchingUp),
        throwsA(isA<JourneyTransitionError>()),
      );
      journey.transitionTo(JourneyPhase.subscribing);
      expect(
        () => journey.transitionTo(JourneyPhase.catchingUp),
        throwsA(isA<JourneyTransitionError>()),
      );
      journey.transitionTo(JourneyPhase.warming);
      expect(
        () => journey.transitionTo(JourneyPhase.subscribing),
        throwsA(isA<JourneyTransitionError>()),
      );
    });
  });
}
