import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';

void main() {
  group('canonical encoding', () {
    test('sha256 matches published vectors', () {
      expect(sha256Hex(''.codeUnits),
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(sha256Hex('abc'.codeUnits),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });

    test('sorts map keys and rejects doubles', () {
      expect(canonicalJson({'b': 1, 'a': 2}), '{"a":2,"b":1}');
      expect(canonicalJson([1, 'x', null, true]), '[1,"x",null,true]');
      expect(() => canonicalJson(1.5), throwsArgumentError);
    });

    test('escapes strings', () {
      expect(canonicalJson(r'a"b\c'), r'"a\"b\\c"');
    });

    test('hashes are stable and grid helpers round-trip', () {
      expect(canonicalHash({'a': 1}), canonicalHash({'a': 1}));
      expect(pixelsFromGrid(gridValue(40.12)), 40.12);
    });
  });

  group('BehaviorRng', () {
    test('is deterministic per seed and differs across seeds', () {
      int draw(int seed) => BehaviorRng(seed).nextUint32();
      expect(draw(42), draw(42));
      expect(draw(42), isNot(draw(43)));
    });

    test('nextUnit stays in [0, 1)', () {
      final rng = BehaviorRng(7);
      for (var i = 0; i < 1000; i++) {
        final unit = rng.nextUnit();
        expect(unit, inInclusiveRange(0, 0.9999999));
      }
    });
  });

  group('TimingDistribution', () {
    test('fixed samples its constant', () {
      const timing = FixedTiming(micros: 1500);
      expect(timing.sample(BehaviorRng(1)), 1500);
      expect(timing.meanUs, 1500);
    });

    test('uniform stays in bounds', () {
      const timing = UniformTiming(minMicros: 100, maxMicros: 200);
      final rng = BehaviorRng(3);
      for (var i = 0; i < 500; i++) {
        final sample = timing.sample(rng);
        expect(sample, inInclusiveRange(100, 199));
      }
      expect(timing.meanUs, 150);
    });

    test('piecewise interpolates within boundaries', () {
      const timing = PiecewiseTiming(boundariesUs: [0, 100, 400]);
      final rng = BehaviorRng(5);
      for (var i = 0; i < 500; i++) {
        expect(timing.sample(rng), inInclusiveRange(0, 399));
      }
      expect(timing.meanUs, 150);
    });

    test('validation collects violations', () {
      expect(
        const UniformTiming(minMicros: 5, maxMicros: 1).validate(),
        isNotEmpty,
      );
      expect(
        const PiecewiseTiming(boundariesUs: [10, 5]).validate(),
        isNotEmpty,
      );
      expect(
        const FixedTiming(micros: -1).validate(),
        isNotEmpty,
      );
      expect(
        TimingDistribution.fromJson(const UniformTiming(
          minMicros: 1,
          maxMicros: 2,
        ).toJson()),
        const UniformTiming(minMicros: 1, maxMicros: 2),
      );
    });
  });

  group('BehaviorPlan', () {
    test('sorts steps and round-trips with a stable hash', () {
      final plan = BehaviorPlan(steps: const [
        PointerUpStep(plannedAtUs: 900),
        PointerDownStep(plannedAtUs: 100),
      ]);
      expect(plan.steps.first.plannedAtUs, 100);
      final restored = BehaviorPlan.fromJson(plan.toJson());
      expect(restored.hash, plan.hash);
      expect(restored.totalDurationUs, 900);
      expect(
        () => BehaviorPlan(
          steps: [const DwellStep(plannedAtUs: -1, durationUs: 1)],
        ),
          throwsA(isA<SpecViolationException>()));
    });
  });

  group('BehaviorProfile', () {
    test('agentImmediate is the zero profile', () {
      final profile = BehaviorProfile.agentImmediate;
      expect(profile.reaction.floorUs, 0);
      expect(profile.rhythm.beforeAction.meanUs, 0);
      expect(profile.pointer.moveDuration.meanUs, 0);
    });

    test('construction fails closed on invalid facets', () {
      expect(
        () => BehaviorProfile(
          reaction: const ReactionDelay(floorUs: -5),
        ),
        throwsA(isA<SpecViolationException>()),
      );
    });

    test('humanPrior samples valid, varied profiles', () {
      final a = BehaviorProfile.humanPrior(11);
      final b = BehaviorProfile.humanPrior(12);
      expect(a, isNot(b));
      expect(a.validate(), isEmpty);
      expect(b.validate(), isEmpty);
      expect(a.reaction.floorUs, greaterThanOrEqualTo(160_000));
      expect(a.reaction.floorUs, lessThanOrEqualTo(420_000));
    });

    test('hash and canonical JSON round-trip', () {
      final profile = BehaviorProfile.humanPrior(11);
      final restored = BehaviorProfile.fromJson(profile.toJson());
      // The canonical (grid-quantized) form is what gets hashed and
      // serialized, so hashes are stable across serialization even when
      // a facet double carries sub-grid bits.
      expect(restored.hash, profile.hash);
      expect(restored.toJson(), profile.toJson());
    });

    test('copyWith replaces only the given facet', () {
      const rhythm = ActionRhythm(
        beforeAction: FixedTiming(micros: 42),
      );
      final profile = BehaviorProfile.agentImmediate.copyWith(rhythm: rhythm);
      expect(profile.rhythm, rhythm);
      expect(profile.reaction, BehaviorProfile.agentImmediate.reaction);
    });
  });

  group('synthesizeBehavior', () {
    const click = ClickAction(css: '#go');

    test('is deterministic per seed and varies across seeds', () {
      final profile = BehaviorProfile.humanPrior(11);
      final a = synthesizeBehavior(profile, 1, click);
      final b = synthesizeBehavior(profile, 1, click);
      final c = synthesizeBehavior(profile, 2, click);
      expect(a.hash, b.hash);
      expect(a.hash, isNot(c.hash));
    });

    test('agentImmediate click is a teleport move plus down/up', () {
      final plan = synthesizeBehavior(
        BehaviorProfile.agentImmediate,
        1,
        click,
        target: const AxBounds(left: 0, top: 0, width: 120, height: 48),
      );
      expect(plan.totalDurationUs, 0);
      expect(
        plan.steps.map((step) => step.kind).toList(),
        ['pointerMove', 'pointerDown', 'pointerUp'],
      );
      final move = plan.steps.whereType<PointerMoveStep>().single;
      expect(move.durationUs, 0);
      expect(move.x, 60);
      expect(move.y, 24);
    });

    group('modifier chords (ADR 0053)', () {
      test('shift+click lowers to key steps around a flagged press',
          () async {
        final plan = synthesizeBehavior(
          BehaviorProfile.agentImmediate,
          1,
          const ClickAtAction(10, 20, modifiers: ['shift']),
        );
        final kinds = plan.steps.map((step) => step.kind).toList();
        expect(kinds, [
          'pointerMove',
          'keyDown',
          'pointerDown',
          'pointerUp',
          'keyUp',
        ]);
        final down = plan.steps.whereType<PointerDownStep>().single;
        expect(down.modifiers, ['shift']);
        final keyDown = plan.steps.whereType<KeyDownStep>().single;
        expect(keyDown.key, 'Shift');
        expect(keyDown.keyCode, namedVirtualKeyCode('Shift'));
        // Round-trips through the canonical form.
        expect(BehaviorStep.fromJson(down.toJson()).toJson(), down.toJson());
      });

      test('meta+drag holds the chord through the whole gesture', () async {
        final plan = synthesizeBehavior(
          BehaviorProfile.agentImmediate,
          1,
          const DragAction(0, 0, 40, 40, modifiers: ['meta']),
        );
        final kinds = plan.steps.map((step) => step.kind).toList();
        expect(kinds.first, 'pointerMove');
        expect(kinds, containsAll(['keyDown', 'pointerDown', 'keyUp']));
        expect(kinds.indexOf('keyDown'), lessThan(kinds.indexOf('pointerDown')));
        expect(kinds.lastIndexOf('keyUp'), greaterThan(kinds.indexOf('pointerUp')));
        expect(
          plan.steps.whereType<PointerUpStep>().single.modifiers,
          ['meta'],
        );
      });

      test('control+Tab is a key chord around the key', () async {
        final plan = synthesizeBehavior(
          BehaviorProfile.agentImmediate,
          1,
          const KeyPressAction('Tab', modifiers: ['control']),
        );
        final keys = plan.steps
            .whereType<KeyDownStep>()
            .map((step) => step.key)
            .toList();
        expect(keys, ['Control', 'Tab']);
        final ups = plan.steps
            .whereType<KeyUpStep>()
            .map((step) => step.key)
            .toList();
        // Release order mirrors the press order.
        expect(ups, ['Tab', 'Control']);
      });

      test('no-modifier plans stay byte-identical to the old shape', () async {
        final plan = synthesizeBehavior(
          BehaviorProfile.agentImmediate,
          1,
          const ClickAtAction(10, 20),
        );
        final down = plan.steps.whereType<PointerDownStep>().single;
        expect(down.toJson(), isNot(contains('modifiers')));
      });
    });

    test('humanPrior click animates: dwell, moves, hold, up', () {
      final profile = BehaviorProfile.humanPrior(11);
      final plan = synthesizeBehavior(
        profile,
        1,
        click,
        target: const AxBounds(left: 100, top: 100, width: 120, height: 48),
      );
      final kinds = plan.steps.map((step) => step.kind).toList();
      expect(kinds.first, 'dwell');
      expect(kinds, contains('pointerMove'));
      expect(kinds.where((kind) => kind == 'pointerMove').length,
          greaterThan(1));
      expect(kinds.last, 'pointerUp');
      expect(plan.totalDurationUs, greaterThan(0));
      // Landing point is the element center.
      final lastMove = plan.steps.whereType<PointerMoveStep>().last;
      expect(lastMove.x, closeTo(160, 0.01));
      expect(lastMove.y, closeTo(124, 0.01));
    });

    test('coordinate drag humanizes the carried path (ADR 0053)', () {
      final plan = synthesizeBehavior(
        BehaviorProfile.humanPrior(7),
        1,
        const DragAction(10, 20, 300, 400),
      );
      final kinds = plan.steps.map((step) => step.kind).toList();
      expect(kinds.first, 'dwell');
      // Pressed once at the start, released once at the end, with the
      // carried path animated between them.
      expect(kinds.where((kind) => kind == 'pointerDown').length, 1);
      expect(kinds.where((kind) => kind == 'pointerUp').length, 1);
      expect(kinds.indexOf('pointerDown'),
          lessThan(kinds.lastIndexOf('pointerMove')));
      expect(kinds.last, 'pointerUp');
      final moves = plan.steps.whereType<PointerMoveStep>().toList();
      // The bezier approach departs near the from-point (curvature
      // allowed) and lands exactly on the to-point.
      expect(moves.first.x, closeTo(10, 30));
      expect(moves.first.y, closeTo(20, 30));
      expect(moves.last.x, closeTo(300, 0.01));
      expect(moves.last.y, closeTo(400, 0.01));
    });

    test('double clickAt emits two presses with escalating clickCount', () {
      final plan = synthesizeBehavior(
        BehaviorProfile.agentImmediate,
        1,
        const ClickAtAction(50, 60, clickCount: 2),
      );
      final downs = plan.steps.whereType<PointerDownStep>().toList();
      final ups = plan.steps.whereType<PointerUpStep>().toList();
      expect(downs.length, 2);
      expect(ups.length, 2);
      expect(downs[0].clickCount, 1);
      expect(downs[1].clickCount, 2);
      expect(ups[1].clickCount, 2);
      final move = plan.steps.whereType<PointerMoveStep>().single;
      expect(move.x, 50);
      expect(move.y, 60);
    });

    test('moveTo is a dwell plus an approach, no button events', () {
      final plan = synthesizeBehavior(
        BehaviorProfile.humanPrior(3),
        1,
        const MoveAction(200, 150),
      );
      expect(plan.steps.whereType<PointerDownStep>(), isEmpty);
      expect(plan.steps.whereType<PointerUpStep>(), isEmpty);
      final lastMove = plan.steps.whereType<PointerMoveStep>().last;
      expect(lastMove.x, closeTo(200, 0.01));
      expect(lastMove.y, closeTo(150, 0.01));
    });

    test('typing emits per-key steps and submit adds Enter', () {
      final plan = synthesizeBehavior(
        BehaviorProfile.agentImmediate,
        1,
        const TypeAction('Hi!', submit: true),
      );
      final keyDowns = plan.steps.whereType<KeyDownStep>().toList();
      expect(
        keyDowns.map((step) => step.key).toList(),
        ['H', 'i', '!', 'Enter'],
      );
      expect(keyDowns.first.keyCode, 72); // ASCII H
    });

    test('non-ASCII runes degrade to explicit char steps', () {
      final plan = synthesizeBehavior(
        BehaviorProfile.agentImmediate,
        1,
        const TypeAction('é'),
      );
      expect(plan.steps.single, isA<CharStep>());
    });

    test('unknown named keys are rejected loudly', () {
      expect(
        () => synthesizeBehavior(
          BehaviorProfile.agentImmediate,
          1,
          const KeyPressAction('F5'),
        ),
        throwsA(isA<SpecViolationException>()),
      );
    });

    test('scroll maps direction to wheel deltas', () {
      final plan = synthesizeBehavior(
        BehaviorProfile.agentImmediate,
        1,
        const ScrollAction(direction: 'up', distance: 120),
      );
      final wheel = plan.steps.whereType<WheelStep>().single;
      expect(wheel.deltaY, -120);
      expect(wheel.deltaX, 0);
    });

    test('projection includes the reaction floor', () {
      final profile = BehaviorProfile.agentImmediate.copyWith(
        reaction: const ReactionDelay(floorUs: 250_000),
      );
      final projection = projectBehavior(profile, 1, click);
      expect(projection.plan.totalDurationUs, 0);
      expect(projection.projectedDurationUs, 250_000);
    });
  });

  group('auditBehavior', () {
    test('agentImmediate audits clean and silent', () {
      final plan = synthesizeBehavior(
        BehaviorProfile.agentImmediate,
        1,
        const TypeAction('hello'),
      );
      final report = auditBehavior(plan, BehaviorProfile.agentImmediate);
      expect(report.subFloorKeyGapCount, 0);
      expect(report.overCeilingSpeedCount, 0);
      // Zero-timing delivery: all inter-key gaps are exactly 0, so no
      // positive-gap samples exist and no floor is violated.
      expect(report.cadenceGaps.count, 0);
      expect(report.eventCount, 10); // 5 chars x (down, up)
    });

    test('humanPrior reports self-consistency near declared means', () {
      final profile = BehaviorProfile.humanPrior(11);
      final plan = synthesizeBehavior(
        profile,
        1,
        const TypeAction('hello world'),
        target: const AxBounds(left: 0, top: 0, width: 100, height: 40),
      );
      final report = auditBehavior(plan, profile);
      expect(report.declaredVsObservedUs.keys, contains('cadence.digraph'));
      final delta = report.declaredVsObservedUs['cadence.digraph']!;
      final declared = profile.cadence.digraph.meanUs;
      // Self-consistency: observed mean within 60% of declared.
      expect(delta.abs(), lessThan(declared * 0.6));
      expect(report.subFloorKeyGapCount, 0);
      expect(report.dwells.count, 1);
      expect(report.planHash, plan.hash);
      expect(report.profileHash, profile.hash);
    });

    test('curved motion reports sinuosity above one', () {
      final profile = BehaviorProfile(
        pointer: const PointerMotion(
          path: BezierPath(curvature: 0.3, overshootPx: 0),
          moveDuration: FixedTiming(micros: 1000),
          maxStepPx: 10,
        ),
      );
      final plan = synthesizeBehavior(
        profile,
        1,
        const ClickAction(css: '#x'),
        target: const AxBounds(left: 0, top: 0, width: 100, height: 40),
      );
      final report = auditBehavior(plan, profile);
      expect(report.moveCount, greaterThan(1));
      expect(report.pathLengthPx, greaterThanOrEqualTo(report.displacementPx));
    });
  });

  group('BehaviorReceipts', () {
    test('envelope and terminal encode the contract fields', () {
      final profile = BehaviorProfile.agentImmediate;
      final plan = synthesizeBehavior(profile, 9, const ClickAction(css: '#a'));
      final outcome = BehaviorOutcome(
        verdict: BehaviorVerdict.complete,
        plan: plan,
        dispatched: [
          DispatchedStep(
            sequence: 0,
            step: plan.steps.first,
            dispatchedAtUs: 40,
            driftUs: 40,
          ),
        ],
      );
      final envelope = BehaviorReceipts.envelope(
        profileHash: profile.hash,
        seed: 9,
        driverId: 'cdp',
        transport: 'cdp',
      );
      expect(envelope['schema'], 'behavior.receipts/v1');
      expect(envelope['rng'], 'xoshiro128starstar-v1');
      expect(envelope['facetVersions'], isNotEmpty);
      final terminal = BehaviorReceipts.terminal(
        outcome: outcome,
        maxDriftUs: BehaviorReceipts.maxDriftUs(outcome.dispatched),
      );
      expect(terminal['verdict'], 'complete');
      expect(terminal['maxDriftUs'], 40);
      expect(outcome.toJson()['dispatchedSteps'], 1);
    });
  });

  group('ProfiledDriver', () {
    test('rides a default profile and rebinds immutably', () async {
      final inner = _StubBehavioralDriver();
      final wrapper = ProfiledDriver(inner);
      expect(wrapper.defaultProfile, BehaviorProfile.agentImmediate);
      final prior = BehaviorProfile.humanPrior(3);
      final rebound = wrapper.withProfile(prior);
      expect(rebound.defaultProfile, prior);
      expect(wrapper.defaultProfile, BehaviorProfile.agentImmediate);

      await wrapper.performProfiled(const ClickAction(css: '#a'), seed: 5);
      expect(inner.lastProfile, BehaviorProfile.agentImmediate);
      await rebound.performProfiled(const ClickAction(css: '#a'));
      expect(inner.lastProfile, prior);
    });
  });
}

/// Minimal driver stub for wrapper tests.
class _StubDriver implements AutomationDriver {
  @override
  DriverCapabilities get capabilities => DriverCapabilities.full;

  @override
  Future<Snapshot> snapshot() async =>
      Snapshot(roots: const [], capturedAt: DateTime.now(), revision: 0);

  @override
  Future<void> perform(AutomationAction action) async {}

  @override
  Future<Uint8List> screenshot() async => Uint8List(0);

  @override
  Future<void> close() async {}
}

/// BehavioralDriver is exported; a ProfiledDriver must ride a behavioral
/// inner driver.
class _StubBehavioralDriver implements BehavioralDriver {
  final _StubDriver _inner = _StubDriver();
  BehaviorProfile? lastProfile;

  @override
  DriverCapabilities get capabilities => _inner.capabilities;

  @override
  Future<Snapshot> snapshot() => _inner.snapshot();

  @override
  Future<void> perform(AutomationAction action) => _inner.perform(action);

  @override
  Future<Uint8List> screenshot() => _inner.screenshot();

  @override
  Future<void> close() => _inner.close();

  @override
  Future<BehaviorOutcome> performWith(
    AutomationAction action,
    BehaviorProfile profile, {
    int? seed,
  }) async {
    lastProfile = profile;
    final plan = synthesizeBehavior(profile, 1, action);
    return BehaviorOutcome(
      verdict: BehaviorVerdict.complete,
      plan: plan,
      dispatched: const [],
    );
  }
}
