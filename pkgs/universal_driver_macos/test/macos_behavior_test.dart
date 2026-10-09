import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_driver_macos/universal_driver_macos.dart';

import 'macos_driver_test.dart' show FakeBridge;

/// The ADR 0044 behavior contract over the macOS bridge (ADR 0053's
/// MoE-from-day-one stance for the coordinate verbs included).
void main() {
  test('the behavioral driver advertises the full facet set', () {
    final driver = BehavioralMacosDriver(bridge: FakeBridge());
    expect(driver.capabilities.behaviorDynamics, isTrue);
    expect(driver.capabilities.pointerCoordinates, isTrue);
  });

  test('agentImmediate clickAt dispatches move + press + release', () async {
    final bridge = FakeBridge();
    final driver = BehavioralMacosDriver(bridge: bridge);
    final outcome = await driver.performWith(
      const ClickAtAction(120, 80),
      BehaviorProfile.agentImmediate,
      seed: 7,
    );
    expect(outcome.verdict, BehaviorVerdict.complete);
    expect(outcome.cause, isNull);
    expect(bridge.pointerEvents.map((event) => event['kind']).toList(), [
      'move',
      'down',
      'up',
    ]);
    expect(bridge.pointerEvents[1]['x'], 120);
    expect(bridge.pointerEvents[1]['y'], 80);
    // Drift is real wall-clock jitter around zero-timing plans.
    for (final step in outcome.dispatched) {
      expect(step.driftUs.abs(), lessThan(50_000));
    }
  });

  test('humanPrior drag is a carried bezier gesture, exact at both ends',
      () async {
    final bridge = FakeBridge();
    final driver = BehavioralMacosDriver(bridge: bridge);
    final outcome = await driver.performWith(
      const DragAction(10, 20, 300, 400),
      BehaviorProfile.humanPrior(7),
      seed: 7,
    );
    expect(outcome.verdict, BehaviorVerdict.complete);
    final kinds = bridge.pointerEvents
        .map((event) => event['kind'])
        .toList();
    expect(kinds.first, 'move');
    expect(kinds.where((kind) => kind == 'down'), hasLength(1));
    expect(kinds.last, 'up');
    // The press happens at the end of the animated approach, near the
    // from-point; the release lands exactly on the to-point.
    final down = bridge.pointerEvents.firstWhere(
      (event) => event['kind'] == 'down',
    );
    expect((down['x']! as num).toDouble(), closeTo(10, 30));
    expect((down['y']! as num).toDouble(), closeTo(20, 30));
    final up = bridge.pointerEvents.last;
    expect(up['x'], 300);
    expect(up['y'], 400);
  });

  test('double clickAt keeps the escalating click state in the plan',
      () async {
    final bridge = FakeBridge();
    final driver = BehavioralMacosDriver(bridge: bridge);
    final outcome = await driver.performWith(
      const ClickAtAction(5, 6, clickCount: 2),
      BehaviorProfile.agentImmediate,
      seed: 3,
    );
    expect(outcome.verdict, BehaviorVerdict.complete);
    final clicks = outcome.plan.steps
        .whereType<PointerDownStep>()
        .map((step) => step.clickCount)
        .toList();
    expect(clicks, [1, 2]);
    final downs = bridge.pointerEvents
        .where((event) => event['kind'] == 'down')
        .toList();
    expect(downs.map((event) => event['clickCount']).toList(), [1, 2]);
  });

  test('keys lower to named bridge down/up pairs', () async {
    final bridge = FakeBridge();
    final driver = BehavioralMacosDriver(bridge: bridge);
    final outcome = await driver.performWith(
      const KeyPressAction('Enter'),
      BehaviorProfile.agentImmediate,
      seed: 1,
    );
    expect(outcome.verdict, BehaviorVerdict.complete);
    expect(bridge.calls.contains('keyDown(Enter)'), isTrue);
    expect(bridge.calls.contains('keyUp(Enter)'), isTrue);
  });

  test('unmapped key names refuse loudly mid-dispatch', () async {
    final bridge = FakeBridge();
    final driver = BehavioralMacosDriver(bridge: bridge);
    bridge.keyResult = 1;
    await expectLater(
      driver.performWith(
        const KeyPressAction('Enter'),
        BehaviorProfile.agentImmediate,
      ),
      throwsA(isA<DriverUnsupportedException>()),
    );
  });

  test('wheel pixels convert to bridge wheel lines', () async {
    final bridge = FakeBridge();
    final driver = BehavioralMacosDriver(bridge: bridge);
    final outcome = await driver.performWith(
      const ScrollAction(direction: 'up', distance: 100),
      BehaviorProfile.agentImmediate,
      seed: 2,
    );
    expect(outcome.verdict, BehaviorVerdict.complete);
    // WheelStep carries CDP pixels (up = negative); the bridge gets
    // macOS lines (up = positive): -100 px -> +10 lines.
    expect(bridge.lastScrollDy, 10.0);
    expect(bridge.lastScrollDx, 0.0);
  });

  test('scheduler timeout truncates loudly', () async {
    final bridge = FakeBridge();
    // A humanPrior type plan carries real dwell/inter-key timing; the
    // short deadline must cut it partway.
    final plan = synthesizeBehavior(
      BehaviorProfile.humanPrior(7),
      7,
      const TypeAction('hello world'),
    );
    final outcome = await MacosBehaviorScheduler(
      bridge,
      timeout: const Duration(milliseconds: 20),
    ).dispatch(plan);
    expect(outcome.verdict, BehaviorVerdict.truncated);
    expect(outcome.cause, BehaviorInterruptionCause.timeout);
    expect(outcome.dispatched.length, lessThan(plan.steps.length));
  });
}
