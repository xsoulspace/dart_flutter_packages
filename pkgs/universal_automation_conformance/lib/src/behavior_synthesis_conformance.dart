import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';

/// Synthesis-side behavior contract tests (ADR 0044).
///
/// These are hermetic — no driver, no transport, no wall clock. They pin
/// the properties every behavioral driver's *plans* must satisfy; wire
/// lowering is each driver package's own test suite.
void behaviorSynthesisConformanceTests() {
  group('behavior synthesis contract', () {
    test('same profile and seed synthesize byte-identical plans', () {
      final profile = BehaviorProfile.humanPrior(11);
      final a = synthesizeBehavior(
        profile,
        1,
        const ClickAction(css: '#go'),
        target: const AxBounds(left: 0, top: 0, width: 100, height: 40),
      );
      final b = synthesizeBehavior(
        profile,
        1,
        const ClickAction(css: '#go'),
        target: const AxBounds(left: 0, top: 0, width: 100, height: 40),
      );
      expect(a.hash, b.hash);
      expect(a.canonicalJsonl(), b.canonicalJsonl());
    });

    test('different seeds diverge', () {
      final profile = BehaviorProfile.humanPrior(11);
      final a = synthesizeBehavior(profile, 1, const ClickAction(css: '#go'));
      final b = synthesizeBehavior(profile, 2, const ClickAction(css: '#go'));
      expect(a.hash, isNot(b.hash));
    });

    test('agentImmediate survives synthesize and audit untouched', () {
      const action = ClickAction(css: '#go');
      final plan = synthesizeBehavior(
        BehaviorProfile.agentImmediate,
        1,
        action,
        target: const AxBounds(left: 0, top: 0, width: 100, height: 40),
      );
      expect(plan.totalDurationUs, 0);
      final report = auditBehavior(plan, BehaviorProfile.agentImmediate);
      expect(report.subFloorKeyGapCount, 0);
      expect(report.overCeilingSpeedCount, 0);
      // Explicit degenerate profile — not a special-cased bypass.
      expect(
        plan.steps.map((step) => step.kind).toList(),
        containsAll(['pointerMove', 'pointerDown', 'pointerUp']),
      );
    });

    test('humanPrior profiles validate and stay within declared ranges',
        () {
      for (var seed = 0; seed < 20; seed++) {
        final profile = BehaviorProfile.humanPrior(seed);
        expect(profile.validate(), isEmpty, reason: 'seed $seed');
        expect(profile.reaction.floorUs, inInclusiveRange(160_000, 420_000));
        expect(
          profile.rhythm.beforeAction.meanUs,
          inInclusiveRange(120_000, 1_500_000),
        );
      }
    });

    test('plans round-trip through canonical JSON with a stable hash', () {
      final profile = BehaviorProfile.humanPrior(11);
      final plan = synthesizeBehavior(
        profile,
        1,
        const TypeAction('Hello', css: '#field', submit: true),
        target: const AxBounds(left: 0, top: 0, width: 100, height: 40),
      );
      final restored = BehaviorPlan.fromJson(plan.toJson());
      expect(restored.hash, plan.hash);
      expect(BehaviorPlan.schemaId, 'behavior.plan/v1');
    });

    test('invalid profiles fail closed at construction', () {
      expect(
        () => BehaviorProfile(
          reaction: const ReactionDelay(floorUs: -1),
        ),
        throwsA(isA<SpecViolationException>()),
      );
    });

    test('typing cadence keeps inter-key gaps above the floor', () {
      final profile = BehaviorProfile.humanPrior(3);
      final plan = synthesizeBehavior(
        profile,
        3,
        const TypeAction('abcdef'),
      );
      final report = auditBehavior(plan, profile);
      expect(report.subFloorKeyGapCount, 0);
      expect(report.cadenceGaps.count, greaterThanOrEqualTo(5));
    });

    test('golden vector pins the canonical plan hash', () {
      final plan = synthesizeBehavior(
        BehaviorProfile.agentImmediate,
        1,
        const ClickAction(css: '#go'),
      );
      // Any change to synthesis output is a breaking contract change:
      // this vector must change only together with BehaviorPlan.schemaId.
      expect(
        plan.hash,
        '6b8f1014e8e5bd82acdb3c608d656b104ac5338bb98952868d338bcaafdbe17c',
      );
    });
  });
}
