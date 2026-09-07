// ignore_for_file: lines_longer_than_80_chars

/// ADR 0033 §1 — the derived context equation, unit-bound.
///
/// The wave-gate lesson: four constants in four layers (ProjectionBudget
/// 4,000, pre-flight 3,800, native window 4,096, reserve 1,024) with no
/// derivation. The equation is the single derivation; these rows pin its
/// arithmetic so a constant change is a named, reviewed event.
library;

import 'package:test/test.dart';

import 'package:xsoulspace_agentic_host/src/derived_context.dart';

void main() {
  test('measured constants pin the published row (R9.1 + finding 18)', () {
    expect(afmNativeWindowTokens, 4096);
    expect(afmOutputReserveTokens, 1024);
    expect(nativeTruthFactor, 1.45);
    expect(minCutBudgetTokens, 600);
  });

  test('the wave-gate row: overhead 2,268 chars/4 → the profile does NOT '
      'fund a cut', () {
    // The wave runs' measured overhead (9 verbs + write_review).
    final row = deriveContextRow(overheadTokens: 2268);
    expect(row.nativeOverhead, 3289); // ceil(2268 × 1.45)
    expect(row.derivedBudget, 0); // 4096 − 3289 − 1024 < 0
    expect(row.fits, isFalse);
  });

  test('a tiny overhead funds a cut, minus margin', () {
    // overhead 300 → native 435 → remainder 4096−435−1024 = 2637 →
    // margin 263 → native budget 2374 → estimator floor(2374/1.45) = 1637.
    final row = deriveContextRow(overheadTokens: 300);
    expect(row.nativeOverhead, 435);
    expect(row.margin, 263);
    expect(row.derivedBudget, 1637);
    expect(row.fits, isTrue);
  });

  test('a derived budget below the min-cut floor is NOT a fit', () {
    // overhead 2,000 → native 2,900 → remainder 172 → margin 17 →
    // native budget 155 → estimator 106 < 600 → fits false (named), even
    // though a naive ">0" check would claim a 106-token "fit".
    final row = deriveContextRow(overheadTokens: 2000);
    expect(row.derivedBudget, inExclusiveRange(100, 112));
    expect(row.fits, isFalse);
  });
}
