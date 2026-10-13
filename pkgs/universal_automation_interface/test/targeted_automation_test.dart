import 'dart:async';

import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';

void main() {
  Snapshot tree() => Snapshot(
    roots: const [
      AxNode(
        role: 'main',
        children: [AxNode(role: 'button', name: 'Save')],
      ),
      AxNode(
        role: 'dialog',
        name: 'Editor',
        children: [
          AxNode(
            role: 'button',
            name: 'Save',
            attributes: {'ref': 'dialog-save'},
          ),
        ],
      ),
    ],
    capturedAt: DateTime.now(),
    revision: 1,
  );
  test('duplicates refuse; exact scoped target keeps adapter reference', () {
    expect(
      () => resolveSemanticTarget(tree(), const SemanticTarget(name: 'Save')),
      throwsA(isA<TargetResolutionException>()),
    );
    final node = resolveSemanticTarget(
      tree(),
      const SemanticTarget(
        role: 'button',
        name: 'Save',
        scope: [SemanticTarget(role: 'dialog', name: 'Editor')],
      ),
    );
    expect(node.attributes['ref'], 'dialog-save');
    expect(
      () => resolveSemanticTarget(tree(), const SemanticTarget(name: 'Sav')),
      throwsA(isA<TargetResolutionException>()),
    );
  });
  test(
    'observed effect survives a lost delivery response without replay',
    () async {
      var state = 0;
      var dispatches = 0;
      final receipt = await verifyEffect<int>(
        dispatch: () {
          dispatches++;
          state++;
          return Future<void>.error(StateError('response lost'));
        },
        observe: () async => state,
        changed: (a, b) => a != b,
      );
      expect(receipt.delivery, EffectDelivery.unknown);
      expect(receipt.effect, EffectObservation.observed);
      expect(dispatches, 1);
    },
  );
  test('already satisfied skips dispatch', () async {
    var dispatches = 0;
    final receipt = await verifyEffect<int>(
      dispatch: () async {
        dispatches++;
      },
      observe: () async => 2,
      changed: (a, b) => a != b,
      isSatisfied: (v) => v == 2,
    );
    expect(receipt.effect, EffectObservation.alreadySatisfied);
    expect(receipt.delivery, EffectDelivery.notDispatched);
    expect(dispatches, 0);
  });
  test('delivery success with no effect times out and never replays', () async {
    var dispatches = 0;
    final receipt = await verifyEffect<int>(
      dispatch: () async {
        dispatches++;
      },
      observe: () async => 0,
      changed: (a, b) => a != b,
      timeout: const Duration(milliseconds: 35),
      pollInterval: const Duration(milliseconds: 5),
    );
    expect(receipt.delivery, EffectDelivery.completed);
    expect(receipt.effect, EffectObservation.timedOut);
    expect(dispatches, 1);
  });
  test('hung observation is bounded', () async {
    var observations = 0;
    final receipt = await verifyEffect<int>(
      dispatch: () async {},
      observe: () =>
          observations++ == 0 ? Future.value(0) : Completer<int>().future,
      changed: (a, b) => a != b,
      timeout: const Duration(milliseconds: 35),
    );
    expect(receipt.effect, EffectObservation.timedOut);
    expect(receipt.observationError, contains('TimeoutException'));
  });
  test(
    'hung dispatch consumes only dispatch budget and allows effect observation',
    () async {
      var state = 0;
      final receipt = await verifyEffect<int>(
        dispatch: () {
          state = 1;
          return Completer<void>().future;
        },
        observe: () async => state,
        changed: (a, b) => a != b,
        timeout: const Duration(milliseconds: 100),
        dispatchTimeout: const Duration(milliseconds: 10),
      );
      expect(receipt.delivery, EffectDelivery.unknown);
      expect(receipt.effect, EffectObservation.observed);
    },
  );
}
