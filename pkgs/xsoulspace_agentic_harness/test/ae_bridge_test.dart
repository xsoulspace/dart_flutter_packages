// ignore_for_file: lines_longer_than_80_chars

/// M4 bridge tests — pure fixtures in AE's `VerifyEntry.toJson()` wire
/// shape (now consumed via `agentic_executables_wire`, Stage G3); no AE
/// install, no subprocess.
library;

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/src/tooling/ae_bridge.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

const _fixture = {
  'entries': [
    {
      'tier': 3,
      'tier_code': 'partial_feature',
      'artifact': 'pkg:harness',
      'canonical': 'ae-core',
      'feature_id': 'F004',
      'message': 'verify_pack tool exists but evidence not linked',
      'reason': 'no_evidence_link',
    },
    {
      'tier': 1,
      'tier_code': 'invariant_violation',
      'artifact': 'pkg:harness',
      'canonical': 'ae-core',
      'feature_id': 'F001',
      'message': 'snapshot restore must reproduce projections byte-for-byte',
    },
    {
      'tier': 2,
      'tier_code': 'upstream_blocker',
      'artifact': 'pkg:harness',
      'canonical': 'ae-core',
      'feature_id': 'F002',
      'message': 'upstream schema change pending',
      'accepted_drift': true,
    },
  ],
};

void main() {
  test('parses tiered gaps from AE verify JSON (typed wire port)', () {
    final gaps = parseVerifyEntries(_fixture);
    expect(gaps, hasLength(3));
    expect(gaps.map((g) => g.tier), containsAll([
      AeTier.invariantViolation,
      AeTier.upstreamBlocker,
      AeTier.partialFeature,
    ]));
  });

  test('blocking = T1/T2 and NOT accepted-drift', () {
    final gaps = parseVerifyEntries(_fixture);
    final blocking = gaps.where((g) => g.blocking).toList();
    expect(blocking, hasLength(1));
    expect(blocking.single.featureId, 'F001');
    expect(hasBlockingGaps(gaps), isTrue);
  });

  test('beat rendering: blocking first, then by tier; compact one-liners',
      () {
    final text = renderGapBeats(parseVerifyEntries(_fixture));
    final lines = text.split('\n');
    expect(lines.first, contains('1 blocking / 3 total'));
    expect(lines[1], contains('[T1 invariant_violation] F001:'));
    expect(lines[1].length, lessThan(160));
    // Accepted drift is labelled, not hidden — failures remain data.
    expect(text, contains('(accepted)'));
    expect(text, contains('no_evidence_link'));
  });

  test('clean report renders a single line', () {
    expect(renderGapBeats(const []), 'verify: clean');
  });

  test('long messages are clipped to keep the cut tiny-context safe', () {
    final long = List.filled(80, 'word').join(' ');
    final text = renderGapBeats([
      VerifyEntryWire(
        tier: AeTier.invariantViolation,
        artifact: 'a',
        canonical: 'c',
        message: long,
      ),
    ]);
    final line = text.split('\n').last;
    expect(line.length, lessThan(180));
    expect(line.endsWith('…'), isTrue);
  });
}
