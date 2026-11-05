/// Laws of seeded blinding (PROGRAM.md §3): determinism from a frozen seed,
/// and unblinding ONLY against a frozen verdict — every refusal NAMED.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_weightmap/src/blinding.dart';

void main() {
  // Probe scratch law: key files and verdict files live under $TMPDIR.
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('weightmap_blinding'));
  tearDown(() => tmp.deleteSync(recursive: true));
  File child(String name) => File('${tmp.path}/$name');

  // The A3 shape: K=8 planted obstacles + K=8 null plants.
  final arms = [
    for (var i = 0; i < 8; i++) 'planted-$i',
    for (var i = 0; i < 8; i++) 'null-$i',
  ];
  const seed = 20261105; // PREREG-A frozen blinding seed.

  group('BlindingPlan.fromSeed', () {
    test('is deterministic across instances', () {
      final p1 = BlindingPlan.fromSeed(seed, arms);
      final p2 = BlindingPlan.fromSeed(seed, arms);
      expect(p1.armToLabel, p2.armToLabel);
      expect(p1.labelToArm, p2.labelToArm);
      expect(p1.arms, arms);
    });

    test('labels are a permutation, and the shuffle is not the identity', () {
      final plan = BlindingPlan.fromSeed(seed, arms);
      expect(plan.armToLabel.keys.toList(), arms);
      expect(plan.armToLabel.values.toSet().length, arms.length);
      expect(
        plan.armToLabel.values.every((l) => l.startsWith('arm-')),
        isTrue,
      );
      // A shuffle that happened to be the identity would blind nobody.
      final positional = {
        for (var i = 0; i < arms.length; i++)
          arms[i]: 'arm-${i.toString().padLeft(3, '0')}',
      };
      expect(plan.armToLabel, isNot(equals(positional)));
      // labelToArm is exactly the inverse.
      for (final e in plan.armToLabel.entries) {
        expect(plan.labelToArm[e.value], e.key);
      }
    });

    test('a different frozen seed gives a different assignment', () {
      final p1 = BlindingPlan.fromSeed(seed, arms);
      final p2 = BlindingPlan.fromSeed(seed + 1, arms);
      expect(p2.armToLabel, isNot(equals(p1.armToLabel)));
    });

    test('rejects empty and duplicate arms, named', () {
      expect(
        () => BlindingPlan.fromSeed(seed, []),
        throwsA(
          isArgumentError.having(
            (e) => e.message,
            'message',
            contains('EMPTY_ARMS'),
          ),
        ),
      );
      expect(
        () => BlindingPlan.fromSeed(seed, ['a', 'a']),
        throwsA(
          isArgumentError.having(
            (e) => e.message,
            'message',
            contains('DUPLICATE_ARMS'),
          ),
        ),
      );
    });
  });

  group('key file', () {
    test('writeKeyFile writes canonical, re-readable json', () {
      final plan = BlindingPlan.fromSeed(seed, arms);
      final key = child('blinding-key.json')..createSync(recursive: true);
      plan.writeKeyFile(key);
      final decoded = jsonDecode(key.readAsStringSync()) as Map;
      expect(decoded['seed'], seed);
      expect(decoded['arms'], arms);
      expect(decoded['armToLabel'], plan.armToLabel);
      // Canonical wire format: keys sorted at the root.
      expect(key.readAsStringSync(), startsWith('{"armToLabel":'));

      final read = BlindingPlan.readKeyFile(key);
      expect(read.armToLabel, plan.armToLabel);
      expect(read.seed, seed);
    });

    test('a hand-edited key file is NAMED, not trusted', () {
      final plan = BlindingPlan.fromSeed(seed, arms);
      final key = child('blinding-key.json')..createSync(recursive: true);
      plan.writeKeyFile(key);
      final decoded = Map<String, Object?>.from(
        jsonDecode(key.readAsStringSync()) as Map,
      );
      final map = Map<String, Object?>.from(decoded['armToLabel']! as Map);
      map['planted-0'] = 'arm-015';
      decoded['armToLabel'] = map;
      key.writeAsStringSync(jsonEncode(decoded));
      expect(
        () => BlindingPlan.readKeyFile(key),
        throwsA(
          isArgumentError.having(
            (e) => e.message,
            'message',
            contains('KEY_FILE_TAMPERED'),
          ),
        ),
      );
    });

    test('malformed key json is NAMED', () {
      final key = child('bad-key.json')..createSync(recursive: true);
      key.writeAsStringSync('{{{ not json');
      expect(
        () => BlindingPlan.readKeyFile(key),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('KEY_FILE_MALFORMED'),
          ),
        ),
      );
    });
  });

  group('unblind gate', () {
    test('refuses VERDICT_NOT_FROZEN before freeze — even with no key', () {
      // The verdict gate is checked FIRST: "no frozen verdict" refuses
      // identically whether or not a key file exists.
      final r = unblind(
        child('missing-key.json'),
        verdictFrozen: child('missing-verdict.md'),
      );
      expect(r, isA<UnblindRefused>());
      final refused = r as UnblindRefused;
      expect(refused.reason, 'VERDICT_NOT_FROZEN');
      expect('$refused', startsWith('UNBLIND_REFUSED reason=VERDICT_NOT_FROZEN'));
    });

    test('refuses VERDICT_NOT_FROZEN before freeze — with a valid key', () {
      final plan = BlindingPlan.fromSeed(seed, arms);
      final key = child('blinding-key.json');
      plan.writeKeyFile(key);
      final r = unblind(key, verdictFrozen: child('verdict.md'));
      expect(r, isA<UnblindRefused>());
      expect((r as UnblindRefused).reason, 'VERDICT_NOT_FROZEN');
    });

    test('refuses KEY_FILE_MISSING after freeze', () {
      child('verdict.md').writeAsStringSync('VERDICT: frozen 2026-11-05\n');
      final r = unblind(
        child('missing-key.json'),
        verdictFrozen: child('verdict.md'),
      );
      expect(r, isA<UnblindRefused>());
      expect((r as UnblindRefused).reason, 'KEY_FILE_MISSING');
    });

    test('refuses KEY_FILE_MALFORMED and KEY_FILE_TAMPERED after freeze', () {
      child('verdict.md').writeAsStringSync('VERDICT: frozen\n');
      final bad = child('bad-key.json')..writeAsStringSync('not json{');
      expect(
        (unblind(bad, verdictFrozen: child('verdict.md')) as UnblindRefused)
            .reason,
        'KEY_FILE_MALFORMED',
      );

      final plan = BlindingPlan.fromSeed(seed, arms);
      final key = child('key.json');
      plan.writeKeyFile(key);
      final decoded = Map<String, Object?>.from(
        jsonDecode(key.readAsStringSync()) as Map,
      );
      decoded['seed'] = 1234; // seed no longer re-derives the stored map
      key.writeAsStringSync(jsonEncode(decoded));
      expect(
        (unblind(key, verdictFrozen: child('verdict.md')) as UnblindRefused)
            .reason,
        'KEY_FILE_TAMPERED',
      );
    });

    test('succeeds after the verdict file is frozen', () {
      final plan = BlindingPlan.fromSeed(seed, arms);
      final key = child('blinding-key.json');
      plan.writeKeyFile(key);
      final verdict = child('verdict.md');

      // Before: refused.
      expect(
        unblind(key, verdictFrozen: verdict),
        isA<UnblindRefused>(),
      );

      // Freeze the verdict, then unblind.
      verdict.writeAsStringSync('VERDICT: specificity 8/8, sensitivity 7/8\n');
      final r = unblind(key, verdictFrozen: verdict);
      expect(r, isA<Unblinded>());
      final map = (r as Unblinded).armToLabel;
      expect(map, plan.armToLabel);
      // The released map is read-only: analysis cannot rewrite the keying.
      expect(() => map['planted-0'] = 'arm-999', throwsUnsupportedError);
    });
  });
}
