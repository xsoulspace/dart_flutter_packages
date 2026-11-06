/// WS-1 live-replay fixture tests: the verdict/drift vocabulary of
/// `tool/runs/ws1_replay.dart` and the ReplayReceipt behavior the live driver
/// depends on — a drifted mirror digest yields `reproduced: false` with the
/// NAMED refusal REPLAY_DIGEST_DRIFT, never a fudged pass.
///
/// NO real checkpoints, NO python, NO device: fixtures are tiny synthetic
/// specs and $TMPDIR ledgers (probe scratch law). The live bit-identity run
/// itself is receipted in receipts/WS1-replay.jsonl + receipts/WS1-summary.md.
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_weightmap/xsoulspace_inference_weightmap.dart';

import '../tool/runs/ws1_replay.dart';

/// A removal-shaped fixture spec (frozen sidecar key set; negative scale like
/// the A3 arm-002 repair edit; sorted columns; 0.25-grid direction so every
/// materialization is bit-exact).
Map<String, Object?> removalFixtureSpec() => {
      'tensor': 'model.layers.15.mlp.down_proj.weight',
      'columns': [2, 5],
      'direction': [0.5, -0.25, 1.0, 0.75],
      'scale': -4.8,
    };

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('weightmap_ws1'));
  tearDown(() => tmp.deleteSync(recursive: true));
  File ledgerFile() => File('${tmp.path}/WS1-replay.jsonl');

  group('ws1DigestDrift: the falsifier vocabulary', () {
    test('agreement returns null (no drift, no name)', () {
      expect(
        ws1DigestDrift(
            label: 'MIRROR_SHARD_M', recorded: 'aa11', rebuilt: 'aa11'),
        isNull,
      );
    });

    test('mismatch returns NAMED REPLAY_DIGEST_DRIFT carrying BOTH digests',
        () {
      final drift = ws1DigestDrift(
          label: 'MIRROR_SHARD_M', recorded: 'aa11', rebuilt: 'bb22');
      expect(drift, isNotNull);
      expect(drift!, startsWith('REPLAY_DIGEST_DRIFT'));
      expect(drift, contains('MIRROR_SHARD_M'));
      expect(drift, contains('recorded=aa11'));
      expect(drift, contains('rebuilt=bb22'));
    });
  });

  group('ws1VerdictOf: PASS only with zero drift and every receipt reproduced',
      () {
    test('clean -> PASS', () {
      expect(ws1VerdictOf(const [], const [true, true]), 'PASS');
    });
    test('any drift -> FAIL(REPLAY_DIGEST_DRIFT)', () {
      expect(
        ws1VerdictOf(const ['REPLAY_DIGEST_DRIFT X recorded=a rebuilt=b'],
            const [true, true]),
        'FAIL(REPLAY_DIGEST_DRIFT)',
      );
    });
    test('any non-reproduced receipt -> FAIL(REPLAY_DIGEST_DRIFT)', () {
      expect(ws1VerdictOf(const [], const [true, false]),
          'FAIL(REPLAY_DIGEST_DRIFT)');
    });
  });

  group('typed removal patch: bridge round trip stays exact', () {
    test('sidecarDeltaToPatch -> patchToSidecarSpec canonicalizes losslessly',
        () {
      const recordedMirrorFp =
          '22e52d07164ca45f379ccb7ddc42e52a39ec719f73e3d043a3551baa931f02e7';
      final spec = removalFixtureSpec();
      final entry = sidecarDeltaToPatch(spec, baseFingerprint: recordedMirrorFp);
      // The base fingerprint IS the recorded plant-mirror digest, also as a
      // named precondition (provenance travels with the patch).
      expect(entry.expectedOldFingerprint, recordedMirrorFp);
      expect(entry.preconditions,
          [baseFingerprintPrecondition(recordedMirrorFp)]);
      final canonical = patchToSidecarSpec(entry);
      expect(canonical['tensor'], spec['tensor']);
      expect(canonical['columns'], [2, 5]);
      expect(canonical['direction'], [0.5, -0.25, 1.0, 0.75]);
      expect(canonical['scale'], -4.8);
      // The patch digest is stable across the round trip (commitment law).
      expect(patchDigestOf(canonical), patchDigestOf(spec));
    });
  });

  group('live-replay receipt law (fixture-level, no real checkpoints)', () {
    LedgerRow appendEdit({
      required String mirrorDigest,
      String batteryDigest = 'battery-R-digest',
    }) {
      return append(
        ledgerFile(),
        ReplayReceipt.editRowKind,
        editRowPayload(
          patch: removalFixtureSpec(),
          mirrorDigest: mirrorDigest,
          batteryDigest: batteryDigest,
        ),
      );
    }

    test('rebuilt mirror digest == recorded -> reproduced:true, PASS', () {
      const recorded = 'recorded-post-repair-tensor-digest';
      final row = appendEdit(mirrorDigest: recorded);
      final receipt =
          ReplayReceipt.replay(row, mirrorDigest: recorded); // rebuilt == recorded
      expect(receipt.reproduced, isTrue);
      expect(receipt.refusal, isNull);
      expect(receipt.patchDigest, patchDigestOf(removalFixtureSpec()));
      expect(receipt.batteryDigest, 'battery-R-digest');
      expect(ws1VerdictOf(const [], [receipt.reproduced]), 'PASS');
    });

    test('DRIFTED mirror digest -> reproduced:false with NAMED '
        'REPLAY_DIGEST_DRIFT (the WS-1 falsifier)', () {
      const recorded = 'recorded-post-repair-tensor-digest';
      const drifted = 'drifted-rebuilt-mirror-digest';
      final row = appendEdit(mirrorDigest: recorded);
      final receipt = ReplayReceipt.replay(row, mirrorDigest: drifted);
      expect(receipt.reproduced, isFalse);
      expect(receipt.refusal, isNotNull);
      expect(receipt.refusal!, startsWith(ReplayReceipt.digestDrift));
      expect(receipt.refusal!, contains('MIRROR_RECEIPT'));
      expect(receipt.refusal!, contains('recorded=$recorded'));
      expect(receipt.refusal!, contains('live=$drifted'));
      // The receipt still reports what the replay OBSERVED (never fudged).
      expect(receipt.mirrorDigest, drifted);
      // The driver-level verdict turns the drift into FAIL, and the same
      // drift string the falsifier law requires is produced by ws1DigestDrift.
      expect(ws1VerdictOf(const [], [receipt.reproduced]),
          'FAIL(REPLAY_DIGEST_DRIFT)');
      final drift = ws1DigestDrift(
          label: 'POST_REPAIR_TENSOR_F32', recorded: recorded, rebuilt: drifted);
      expect(drift, startsWith('REPLAY_DIGEST_DRIFT'));
    });

    test('a refusal row keeps the ledger chain intact (denominator law)', () {
      // What the driver writes when bit-identity fails mid-run: a NAMED
      // ws1-refusal row, then STOP.
      append(ledgerFile(), 'ws1-refusal', {
        'ws': 'WS-1',
        'mode': 'live',
        'code': 'REPLAY_DIGEST_DRIFT',
        'detail': ws1DigestDrift(
            label: 'MIRROR_SHARD_M', recorded: 'aa', rebuilt: 'bb'),
        'wall_ms_claim': false,
      });
      final verdict = verifyChain(ledgerFile());
      expect(verdict, isA<ChainIntact>());
      final rows = readAll(ledgerFile());
      expect(rows.single.kind, 'ws1-refusal');
      expect(rows.single.payload['code'], 'REPLAY_DIGEST_DRIFT');
      expect(rows.single.payload['detail'], contains('recorded=aa'));
    });
  });
}
