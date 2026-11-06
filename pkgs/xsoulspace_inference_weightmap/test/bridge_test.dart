/// Laws of the WS-1 bridge (lib/src/bridge.dart), as tests: the frozen
/// sidecar spec shape, the rank-1 column-window encoding, round-trip
/// stability within Tolerance.exact for representable values, the named
/// unrepresentable refusals, stale-fingerprint STALE_PRECONDITION through
/// apply, and the replay record's digest-drift refusal.
///
/// Probe scratch law: ledger fixtures live under $TMPDIR, never in the tree.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_weightmap/src/bridge.dart';
import 'package:xsoulspace_inference_weightmap/src/ledger.dart';
import 'package:xsoulspace_inference_weightmap/src/patch_algebra.dart';

/// The canonical fixture spec (apply_delta.py shape; sorted columns, doubles,
/// 0.25-grid direction so every materialization below is bit-exact).
Map<String, Object?> fixtureSpec({
  String tensor = 'model.layers.15.mlp.down_proj.weight',
  List<int> columns = const [1, 3],
  List<double> direction = const [0.5, 0.25, -0.5, 1.0],
  double scale = 2.0,
}) =>
    {
      'tensor': tensor,
      'columns': columns,
      'direction': direction,
      'scale': scale,
    };

void main() {
  const baseFp = 'base-fingerprint-observed';
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('weightmap_bridge'));
  tearDown(() => tmp.deleteSync(recursive: true));
  File ledgerFile() => File('${tmp.path}/verdicts.jsonl');

  group('sidecarDeltaToPatch: frozen spec shape', () {
    test('converts to a rank-1 column-window patch carrying the fingerprint',
        () {
      final entry =
          sidecarDeltaToPatch(fixtureSpec(), baseFingerprint: baseFp);
      expect(entry.delta.rank, 1);
      expect(entry.delta.scale, 2.0);
      expect(entry.address.tensor,
          'model.layers.15.mlp.down_proj.weight');
      expect(entry.address.directionId, sidecarDirectionId);
      // Window = the columns: full rows, half-open [min, max + 1).
      expect(entry.address.rowStart, isNull);
      expect(entry.address.rowEnd, isNull);
      expect(entry.address.colStart, 1);
      expect(entry.address.colEnd, 4);
      // Row-major over the 4x3 window; unchosen offset (col 2) is exact 0.0.
      expect(entry.delta.elementCount, 12);
      expect(entry.delta.vectors.single, [
        0.5, 0.0, 0.5, // row 0: cols 1,2,3 (col 2 unchosen)
        0.25, 0.0, 0.25,
        -0.5, 0.0, -0.5,
        1.0, 0.0, 1.0,
      ]);
      // Provenance: expectedOldFingerprint AND the named precondition.
      expect(entry.expectedOldFingerprint, baseFp);
      expect(entry.preconditions, [baseFingerprintPrecondition(baseFp)]);
      expect(entry.preconditions.single, 'BASE_FINGERPRINT=$baseFp');
      // Nobody observed the post state: no committed new fingerprint.
      expect(entry.expectedNewFingerprint, isNull);
    });

    test('refuses malformed specs with the apply_delta.py vocabulary, NAMED',
        () {
      final bad = <String, Map<String, Object?>>{
        'missing key': {'tensor': 't.weight', 'columns': [1], 'scale': 1.0},
        'extra key': {
          ...fixtureSpec(),
          'extra': true,
        },
        'empty tensor': fixtureSpec(tensor: ''),
        'columns not list': {
          ...fixtureSpec(),
          'columns': 'nope',
        },
        'empty columns': fixtureSpec(columns: []),
        'duplicate columns': fixtureSpec(columns: [3, 3]),
        'negative columns': fixtureSpec(columns: [-1, 2]),
        'empty direction': fixtureSpec(direction: []),
        'scale not number': {
          ...fixtureSpec(),
          'scale': 'two',
        },
      };
      bad.forEach((name, spec) {
        expect(
          () => sidecarDeltaToPatch(spec, baseFingerprint: baseFp),
          throwsA(isArgumentError.having(
              (e) => e.message, 'message [$name]', contains('SPEC_SHAPE_MISMATCH'))),
          reason: name,
        );
      });
    });

    test('non-finite material is refused downstream, NAMED', () {
      expect(
        () => sidecarDeltaToPatch(fixtureSpec(direction: [0.5, double.nan, -0.5, 1.0]),
            baseFingerprint: baseFp),
        throwsA(isArgumentError.having(
            (e) => e.message, 'message', contains('NON_FINITE_DELTA'))),
      );
      expect(
        () => sidecarDeltaToPatch(fixtureSpec(scale: double.infinity),
            baseFingerprint: baseFp),
        throwsA(isArgumentError.having(
            (e) => e.message, 'message', contains('NON_FINITE_SCALE'))),
      );
      expect(
        () => sidecarDeltaToPatch(fixtureSpec(), baseFingerprint: ''),
        throwsA(isArgumentError.having(
            (e) => e.message, 'message', contains('EMPTY_FINGERPRINT'))),
      );
    });
  });

  group('sidecarDeltaToPatch through apply: semantics and staleness', () {
    // 4 rows x 6 cols on the 0.25 grid: every applied delta below is exact.
    final base = Tensor.fromRows([
      [1, 2, 3, 4, 5, 6],
      [0.5, 0.25, 0.75, 1.25, 1.5, 1.75],
      [0, 0, 0, 0, 0, 0],
      [-1, -2, -3, -4, -5, -6],
    ]);
    final entry =
        sidecarDeltaToPatch(fixtureSpec(), baseFingerprint: baseFp);

    test('law: apply writes scale*direction into the chosen columns only', () {
      final honest = windowFingerprint(base, entry.address);
      final fresh = sidecarDeltaToPatch(fixtureSpec(), baseFingerprint: honest);
      final result =
          apply(base, fresh, tol: Tolerance.exact, actualFingerprint: honest);
      expect(result, isA<Applied>());
      final out = (result as Applied).tensor;
      // Chosen columns 1 and 3: base + scale(2.0) * direction[row].
      const scaled = [1.0, 0.5, -1.0, 2.0]; // 2.0 * [0.5, 0.25, -0.5, 1.0]
      for (var r = 0; r < 4; r++) {
        expect(out.get(r, 1), base.get(r, 1) + scaled[r]);
        expect(out.get(r, 3), base.get(r, 3) + scaled[r]);
        // Unchosen column INSIDE the window (col 2): +0.0, untouched.
        expect(out.get(r, 2), base.get(r, 2));
        // Columns outside the window: untouched.
        expect(out.get(r, 0), base.get(r, 0));
        expect(out.get(r, 4), base.get(r, 4));
        expect(out.get(r, 5), base.get(r, 5));
      }
      // Propose-only: the base itself never moved.
      expect(windowFingerprint(base, entry.address), honest);
    });

    test('law: a stale fingerprint refuses with NAMED STALE_PRECONDITION', () {
      final moved = base.clone()..set(0, 1, 99); // the base moved under us
      final r = apply(
        moved,
        entry,
        actualFingerprint: windowFingerprint(moved, entry.address),
      );
      expect(r, isA<Conflict>());
      final conflict = r as Conflict;
      expect(conflict.reason, ConflictReason.stalePrecondition);
      expect(conflict.reason.label, 'STALE_PRECONDITION');
      expect(conflict.detail, contains('FINGERPRINT_MISMATCH'));
    });
  });

  group('patchToSidecarSpec: round-trip stability (Tolerance.exact)', () {
    test('law: canonical spec round-trips bit-for-bit', () {
      final spec = fixtureSpec();
      final back = patchToSidecarSpec(
          sidecarDeltaToPatch(spec, baseFingerprint: baseFp));
      expect(back.keys.toSet(), sidecarSpecKeys); // strict frozen key set
      expect(back['tensor'], spec['tensor']);
      expect(back['columns'], [1, 3]);
      expect(back['direction'], [0.5, 0.25, -0.5, 1.0]);
      expect(back['scale'], 2.0);
      // Exact stability: a second round trip is identical to the first.
      final again = patchToSidecarSpec(
          sidecarDeltaToPatch(back, baseFingerprint: baseFp));
      expect(again, equals(back));
      // Every representable value survives within Tolerance.exact.
      for (var i = 0; i < 4; i++) {
        expect(
          Tolerance.exact.allows((spec['direction']! as List)[i] as double,
              (back['direction']! as List)[i] as double),
          isTrue,
        );
      }
    });

    test('json-decoded spec: int numbers and unsorted columns canonicalize',
        () {
      // The exact wire shape jsonDecode produces: ints where the writer
      // omitted '.0', columns in the spec's own order.
      final decoded = jsonDecode('{"tensor": "t.weight", "columns": [3, 1], '
          '"direction": [1, 2, 0.5, -1], "scale": 2}') as Map<String, Object?>;
      final back =
          patchToSidecarSpec(sidecarDeltaToPatch(decoded, baseFingerprint: baseFp));
      // Canonical form: columns sorted ascending, numbers as doubles.
      expect(back['tensor'], 't.weight');
      expect(back['columns'], [1, 3]);
      expect(back['direction'], [1.0, 2.0, 0.5, -1.0]);
      expect(back['scale'], 2.0);
      // Numeric-equality law: a JSON int round-trips as an equal double.
      expect(back['scale'] == decoded['scale'], isTrue); // 2.0 == 2
      expect(back, equals({
        'tensor': 't.weight',
        'columns': [1, 3],
        'direction': [1, 2, 0.5, -1], // deep equality: 1.0 == 1
        'scale': 2,
      }));
    });

    test('law: rank and scale are preserved through the round trip', () {
      for (final scale in [0.0, -1.5, 0.25, 3.0]) {
        final entry = sidecarDeltaToPatch(fixtureSpec(scale: scale),
            baseFingerprint: baseFp);
        expect(entry.delta.rank, 1, reason: 'scale=$scale');
        expect(entry.delta.scale, scale, reason: 'scale=$scale');
        final back = patchToSidecarSpec(entry);
        expect(back['scale'], scale, reason: 'scale=$scale');
        expect(back['columns'], [1, 3], reason: 'scale=$scale');
      }
      // scale=0 is representable: the raw direction (not scale*direction)
      // lives in the vector, so the columns stay recoverable.
      final zero = sidecarDeltaToPatch(fixtureSpec(scale: 0), baseFingerprint: baseFp);
      expect(zero.delta.at(0), 0.0); // the applied delta is zero...
      expect(patchToSidecarSpec(zero)['direction'], [0.5, 0.25, -0.5, 1.0]);
      // ...but the spec still names its direction exactly.
    });

    test('unrepresentable entries refuse by name, never guess', () {
      final delta2 = DeltaSpec(rank: 2, vectors: [
        [1, 1],
        [1, 1],
      ], scale: 1);
      // Rank != 1: the sidecar format carries exactly one direction.
      expect(
        () => patchToSidecarSpec(PatchEntry(
          address: TensorAddress(
              tensor: 't.weight', directionId: 'd', colStart: 0, colEnd: 2),
          expectedOldFingerprint: baseFp,
          delta: delta2,
        )),
        throwsA(isArgumentError.having((e) => e.message, 'message',
            contains('SIDECAR_RANK_UNREPRESENTABLE'))),
      );
      // Bounded row window: a sidecar direction spans ALL rows.
      expect(
        () => patchToSidecarSpec(PatchEntry(
          address: TensorAddress(
              tensor: 't.weight',
              directionId: 'd',
              rowStart: 0,
              rowEnd: 1,
              colStart: 0,
              colEnd: 2),
          expectedOldFingerprint: baseFp,
          delta: DeltaSpec(rank: 1, vectors: [
            [1, 1]
          ], scale: 1),
        )),
        throwsA(isArgumentError.having((e) => e.message, 'message',
            contains('SIDECAR_ROW_WINDOW_UNREPRESENTABLE'))),
      );
      // Unbounded column window (e.g. a diff() entry): columns must be
      // explicit indices.
      final a = Tensor.fromRows([
        [1, 2],
      ]);
      final b = Tensor.fromRows([
        [1.5, 2],
      ]);
      final diffEntry = (diff(a, b, tensorName: 't.weight') as Proposal)
          .entries
          .single;
      expect(
        () => patchToSidecarSpec(diffEntry),
        throwsA(isArgumentError.having((e) => e.message, 'message',
            contains('SIDECAR_COL_WINDOW_UNBOUNDED'))),
      );
      // Vector length not rows * width.
      expect(
        () => patchToSidecarSpec(PatchEntry(
          address: TensorAddress(
              tensor: 't.weight', directionId: 'd', colStart: 0, colEnd: 2),
          expectedOldFingerprint: baseFp,
          delta: DeltaSpec(rank: 1, vectors: [
            [1, 1, 1]
          ], scale: 1),
        )),
        throwsA(isArgumentError.having((e) => e.message, 'message',
            contains('SIDECAR_WINDOW_AREA_MISMATCH'))),
      );
      // Chosen columns whose slices differ: one direction per spec is the
      // frozen format.
      expect(
        () => patchToSidecarSpec(PatchEntry(
          address: TensorAddress(
              tensor: 't.weight', directionId: 'd', colStart: 0, colEnd: 2),
          expectedOldFingerprint: baseFp,
          delta: DeltaSpec(rank: 1, vectors: [
            [1, 2]
          ], scale: 1), // col 0 slice [1], col 1 slice [2]
        )),
        throwsA(isArgumentError.having((e) => e.message, 'message',
            contains('SIDECAR_COLUMN_DRIFT'))),
      );
      // All-zero delta: a zero edit cannot name its columns.
      expect(
        () => patchToSidecarSpec(PatchEntry(
          address: TensorAddress(
              tensor: 't.weight', directionId: 'd', colStart: 0, colEnd: 2),
          expectedOldFingerprint: baseFp,
          delta: DeltaSpec(rank: 1, vectors: [
            [0, 0]
          ], scale: 1),
        )),
        throwsA(isArgumentError.having((e) => e.message, 'message',
            contains('SIDECAR_ZERO_DELTA'))),
      );
    });
  });

  group('patchDigestOf / editRowPayload', () {
    test('digest is sha256 of the canonical json, key-order independent', () {
      final spec = fixtureSpec();
      final expected = sha256
          .convert(utf8.encode(canonicalJson(spec)))
          .toString();
      expect(patchDigestOf(spec), expected);
      final reordered = <String, Object?>{
        'scale': spec['scale']!,
        'direction': spec['direction']!,
        'columns': spec['columns']!,
        'tensor': spec['tensor']!,
      };
      expect(patchDigestOf(reordered), expected);
    });

    test('editRowPayload commits the digest and validates before building',
        () {
      final spec = fixtureSpec();
      final payload = editRowPayload(
          patch: spec, mirrorDigest: 'mirror-1', batteryDigest: 'battery-1');
      expect(payload.keys.toSet(),
          {'patch', 'patch_digest', 'mirror_digest', 'battery_digest'});
      expect(payload['patch_digest'], patchDigestOf(spec));
      expect(
        () => editRowPayload(
            patch: {'tensor': 't.weight'},
            mirrorDigest: 'm',
            batteryDigest: 'b'),
        throwsA(isArgumentError.having((e) => e.message, 'message',
            contains('SPEC_SHAPE_MISMATCH'))),
      );
      expect(
        () => editRowPayload(
            patch: spec, mirrorDigest: '', batteryDigest: 'b'),
        throwsA(isArgumentError.having(
            (e) => e.message, 'message', contains('EMPTY_DIGEST'))),
      );
      expect(
        () => editRowPayload(
            patch: spec, mirrorDigest: 'm', batteryDigest: ''),
        throwsA(isArgumentError.having(
            (e) => e.message, 'message', contains('EMPTY_DIGEST'))),
      );
    });
  });

  group('ReplayReceipt: WS-1 replay record', () {
    const mirrorDigest = 'mirror-receipt-digest';
    const batteryDigest = 'battery-digest-frozen';

    LedgerRow appendEdit(Map<String, Object?> patch,
        {String mirror = mirrorDigest, String battery = batteryDigest}) {
      return append(
        ledgerFile(),
        ReplayReceipt.editRowKind,
        editRowPayload(
            patch: patch, mirrorDigest: mirror, batteryDigest: battery),
      );
    }

    test('an agreeing replay produces the frozen record shape', () {
      final spec = fixtureSpec();
      final row = appendEdit(spec);
      // The row survived the chain: read it back from the file.
      final reloaded = readAll(ledgerFile()).single;
      expect(reloaded.digest, row.digest);
      final receipt =
          ReplayReceipt.replay(reloaded, mirrorDigest: mirrorDigest);
      expect(receipt.reproduced, isTrue);
      expect(receipt.refusal, isNull);
      expect(receipt.patchDigest, patchDigestOf(spec));
      expect(receipt.mirrorDigest, mirrorDigest);
      expect(receipt.batteryDigest, batteryDigest);
      final json = receipt.toJson();
      expect(json.keys.toList(),
          ['patch_digest', 'mirror_digest', 'battery_digest', 'reproduced']);
      expect(json['reproduced'], isTrue);
      // The record is canonical-json-able (ledger-ready, textual evidence).
      expect(() => canonicalJson(json), returnsNormally);
    });

    test('live mirror drift: reproduced=false with NAMED REPLAY_DIGEST_DRIFT',
        () {
      final row = appendEdit(fixtureSpec());
      final receipt =
          ReplayReceipt.replay(row, mirrorDigest: 'a-different-mirror');
      expect(receipt.reproduced, isFalse);
      expect(receipt.refusal, isNotNull);
      expect(receipt.refusal!, startsWith(ReplayReceipt.digestDrift));
      expect(receipt.refusal!, contains('MIRROR_RECEIPT'));
      expect(receipt.refusal!, contains(mirrorDigest)); // recorded
      expect(receipt.refusal!, contains('a-different-mirror')); // live
      // The record still carries what the replay OBSERVED.
      expect(receipt.mirrorDigest, 'a-different-mirror');
      expect(receipt.toJson()['refusal'], receipt.refusal);
    });

    test('patch commitment drift is named PATCH_COMMITMENT with the '
        'recomputed digest', () {
      // A row that lies about its own patch: payload carries a digest that
      // does not match its patch content.
      final spec = fixtureSpec();
      final lying = append(
        ledgerFile(),
        'edit',
        {
          'patch': spec,
          'patch_digest': 'not-the-real-digest',
          'mirror_digest': mirrorDigest,
          'battery_digest': batteryDigest,
        },
      );
      final receipt =
          ReplayReceipt.replay(lying, mirrorDigest: mirrorDigest);
      expect(receipt.reproduced, isFalse);
      expect(receipt.refusal!, contains('REPLAY_DIGEST_DRIFT'));
      expect(receipt.refusal!, contains('PATCH_COMMITMENT'));
      expect(receipt.refusal!, contains(patchDigestOf(spec)));
      expect(receipt.patchDigest, patchDigestOf(spec)); // recomputed, honest
    });

    test('both drifts are listed in one refusal (never just the first)', () {
      final lying = append(ledgerFile(), 'edit', {
        'patch': fixtureSpec(),
        'patch_digest': 'wrong',
        'mirror_digest': 'wrong-too',
        'battery_digest': batteryDigest,
      });
      final receipt =
          ReplayReceipt.replay(lying, mirrorDigest: mirrorDigest);
      expect(receipt.reproduced, isFalse);
      expect(receipt.refusal!, contains('PATCH_COMMITMENT'));
      expect(receipt.refusal!, contains('MIRROR_RECEIPT'));
    });

    test('structural problems refuse loudly with named errors', () {
      final runRow = append(ledgerFile(), 'run', {'arm': 'A3'});
      expect(
        () => ReplayReceipt.replay(runRow, mirrorDigest: mirrorDigest),
        throwsA(isArgumentError.having((e) => e.message, 'message',
            contains('REPLAY_ROW_KIND_MISMATCH'))),
      );
      final noBattery = append(ledgerFile(), 'edit', {
        'patch': fixtureSpec(),
        'patch_digest': patchDigestOf(fixtureSpec()),
        'mirror_digest': mirrorDigest,
      });
      expect(
        () => ReplayReceipt.replay(noBattery, mirrorDigest: mirrorDigest),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('MISSING_FIELD=battery_digest'))),
      );
      final badType = append(ledgerFile(), 'edit', {
        'patch': fixtureSpec(),
        'patch_digest': 42,
        'mirror_digest': mirrorDigest,
        'battery_digest': batteryDigest,
      });
      expect(
        () => ReplayReceipt.replay(badType, mirrorDigest: mirrorDigest),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('MALFORMED_FIELD=patch_digest'))),
      );
      final row = appendEdit(fixtureSpec());
      expect(
        () => ReplayReceipt.replay(row, mirrorDigest: ''),
        throwsA(isArgumentError.having((e) => e.message, 'message',
            contains('EMPTY_MIRROR_DIGEST'))),
      );
    });

    test('end-to-end WS-1 chain: spec -> typed patch -> ledger row -> replay',
        () {
      // 1. The A3 arm's spec, converted and materialized against an honest
      //    fingerprint (the algebra's own laws, exercised above).
      final spec = fixtureSpec();
      final base = Tensor.fromRows([
        [0, 0, 0, 0, 0, 0],
        [1, 1, 1, 1, 1, 1],
        [0.5, 0.5, 0.5, 0.5, 0.5, 0.5],
        [2, 2, 2, 2, 2, 2],
      ]);
      final entry = sidecarDeltaToPatch(spec,
          baseFingerprint: windowFingerprint(
              base,
              TensorAddress(
                  tensor: spec['tensor']! as String,
                  directionId: sidecarDirectionId,
                  colStart: 1,
                  colEnd: 4)));
      final applied = apply(base, entry,
          actualFingerprint: entry.expectedOldFingerprint);
      expect(applied, isA<Applied>());
      // 2. The edit is journaled as a typed artifact with its commitments.
      final mirror = 'mirror-receipt:spec_digest=deadbeef';
      final row = appendEdit(spec, mirror: mirror);
      // 3. Replay against the live mirror receipt agrees...
      expect(
          ReplayReceipt.replay(row, mirrorDigest: mirror).reproduced, isTrue);
      // ...and a moved mirror is caught by name.
      final drifted =
          ReplayReceipt.replay(row, mirrorDigest: 'mirror-receipt:moved');
      expect(drifted.reproduced, isFalse);
      expect(drifted.refusal!, contains('REPLAY_DIGEST_DRIFT'));
      // The ledger chain stayed intact through all of it.
      expect(verifyChain(ledgerFile()), isA<ChainIntact>());
    });
  });
}
