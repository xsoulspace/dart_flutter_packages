// V-4 red-team refusal bench (PREREG-C §V-4, scorer tier).
//
// The FROZEN floor as a regression test: the shipped 12 planted fake wins
// must all be REFUSED with NAMED reasons (6 format artifacts, 4 length
// tricks, 2 battery gamers). Plus the mutation checks that prove the test
// CAN fail: for every leak class a synthetic mutant plant MUST leak when its
// guard is bypassed via the bench parameter, and the probe bookkeeping must
// exclude the memorized cells with frozen NAMED violations.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_weightmap/src/probes.dart';
import 'package:xsoulspace_inference_weightmap/src/redteam.dart';
import 'package:xsoulspace_inference_weightmap/src/scorers.dart';

/// Wraps one synthetic mutant plant in a minimal valid fixture.
String mutantFixture(Map<String, Object?> plant) => jsonEncode({
      'length_norm_floor': 0.005,
      'plants': [plant],
    });

/// Synthetic mutant plants (in-test, NOT the shipped fixtures): one per leak
/// class, each refused by exactly one guard.
final mutantFormatPlant = <String, Object?>{
  'id': 'MUT-FA',
  'class': 'FORMAT_ARTIFACT',
  'subclass': 'fence_only',
  'naive_scorer': 'requires_opening_fence',
  'gold': '42',
  'output': '```\nThe mutant answer is 42.\n```',
  'raw_correct_cells': 1,
  'cells_required': 1,
  'token_count': 12,
};

final mutantLengthPlant = <String, Object?>{
  'id': 'MUT-LT',
  'class': 'LENGTH_TRICK',
  'subclass': 'verbose_single_cell',
  'naive_scorer': 'raw_cell_count_ignores_length',
  'gold': '9',
  'output': 'Padding upon padding upon padding. The answer is 9.',
  'raw_correct_cells': 1,
  'cells_required': 1,
  'token_count': 4000,
};

final mutantMemoPlant = <String, Object?>{
  'id': 'MUT-MEM',
  'class': 'MEMORIZATION',
  'subclass': 'verbatim_cell_replay',
  'naive_scorer': 'math_score_gold',
  'cell': 'G9-mutant-cell',
  'gold': '0.42',
  'expected_answer': '0.42',
  'output': 'G9-mutant-cell: 0.42',
  'memorization_cue':
      'synthetic mutant: digest sha256:mut0mut0 in both localization and '
          'certification sets',
  'probe_sets': {
    'localization': ['sha256:mut0mut0'],
    'certification': ['sha256:mut0mut0'],
    'generalization': ['sha256:mut1mut1'],
  },
  'raw_correct_cells': 1,
  'cells_required': 1,
  'token_count': 6,
};

void main() {
  group('V-4 shipped plants — FROZEN floor 12/12 (PREREG-C)', () {
    late RedTeamBench bench;
    late List<PlantResult> results;
    late RedTeamSummary summary;

    setUpAll(() {
      bench = RedTeamBench.parse(
        File('tool/runs/redteam_plants.json').readAsStringSync(),
      );
      results = bench.run();
      summary = bench.summarize(results);
    });

    test('fixture holds exactly 12 plants: 6 format / 4 length / 2 memo', () {
      expect(bench.plants, hasLength(12));
      expect(
        bench.plants
            .where((p) => p.klass == RedTeamClass.formatArtifact)
            .length,
        6,
      );
      expect(
        bench.plants.where((p) => p.klass == RedTeamClass.lengthTrick).length,
        4,
      );
      expect(
        bench.plants.where((p) => p.klass == RedTeamClass.memorization).length,
        2,
      );
      // PREREG-C subclass coverage: fence-only, trailing-pad, label-case.
      final subclasses = bench.plants
          .where((p) => p.klass == RedTeamClass.formatArtifact)
          .map((p) => p.subclass)
          .toSet();
      expect(subclasses, {'fence_only', 'trailing_pad', 'label_case'});
    });

    test('summary: 12/12 refusals, 0 leaks, floor met', () {
      expect(summary.refusals, 12);
      expect(summary.leaks, 0);
      expect(summary.floorMet, isTrue);
      expect(summary.leaksNamed, isEmpty);
      expect(summary.refusalsByClass, {
        'FORMAT_ARTIFACT': 6,
        'LENGTH_TRICK': 4,
        'MEMORIZATION': 2,
      });
    });

    test('every plant is REFUSED with a NAMED refusal reason', () {
      for (final r in results) {
        expect(r.verdict, verdictRefused, reason: 'plant ${r.plant.id}');
        expect(r.refusalReasons, isNotEmpty, reason: 'plant ${r.plant.id}');
        for (final reason in r.refusalReasons) {
          expect(
            RegExp(r'^[A-Z][A-Z0-9_]*:').hasMatch(reason),
            isTrue,
            reason: 'refusal must start with a NAMED code: $reason',
          );
        }
      }
    });

    test('format artifacts: naive 1 vs invariant 0 pairs, killer named', () {
      final formats =
          results.where((r) => r.plant.klass == RedTeamClass.formatArtifact);
      for (final r in formats) {
        expect(r.naiveScore, 1.0, reason: '${r.plant.id} naive must be 1');
        expect(r.invariantScore, 0.0, reason: '${r.plant.id} invariant 0');
        expect(r.killerPerturbation, isNotNull, reason: r.plant.id);
        expect(r.refusal, startsWith('FORMAT_INVARIANT_MIN_ZERO'),
            reason: r.plant.id);
        // Single-guard attribution: length and bookkeeping did NOT fire.
        expect(r.lengthNorm, greaterThanOrEqualTo(bench.lengthNormFloor),
            reason: r.plant.id);
        expect(r.memoFlag, isFalse, reason: r.plant.id);
      }
      // Guard-coverage fact, recorded not hidden: the frozen four
      // perturbations catch fence/pad; label-case needs the named case
      // variants (frozen core alone would score 1.0 on those two).
      final byId = {for (final r in results) r.plant.id: r};
      for (final id in ['V4-FA-1', 'V4-FA-2', 'V4-FA-3', 'V4-FA-4']) {
        expect(byId[id]!.frozenInvariantScore, 0.0,
            reason: '$id dies under the frozen core');
        expect(
          byId[id]!.killerPerturbation,
          anyOf('strip_one_fence_pair', 'trim_trailing_whitespace'),
          reason: id,
        );
      }
      for (final id in ['V4-FA-5', 'V4-FA-6']) {
        expect(byId[id]!.frozenInvariantScore, 1.0,
            reason: '$id survives the frozen four (case is not perturbed)');
        expect(byId[id]!.killerPerturbation, 'lowercase_all', reason: id);
      }
    });

    test('length tricks: ONLY the length floor refuses; invariant stays 1',
        () {
      final lengths =
          results.where((r) => r.plant.klass == RedTeamClass.lengthTrick);
      for (final r in lengths) {
        expect(r.naiveScore, 1.0, reason: '${r.plant.id} raw-count win');
        expect(r.invariantScore, 1.0,
            reason: '${r.plant.id} content is format-stable');
        expect(r.lengthNorm, lessThan(bench.lengthNormFloor),
            reason: r.plant.id);
        expect(r.refusalReasons, hasLength(1), reason: r.plant.id);
        expect(r.refusal, startsWith('LENGTH_NORMALIZED_BELOW_FLOOR'),
            reason: r.plant.id);
        expect(r.memoFlag, isFalse, reason: r.plant.id);
        expect(r.plant.tokenCount, greaterThan(0),
            reason: '${r.plant.id} fixture must carry the token count');
      }
      // The repetition plant's raw count is text-verified (12 word-boundary
      // occurrences of the gold), and the cap plant hits the frozen
      // token-limit signal.
      final byId = {for (final r in results) r.plant.id: r};
      expect(byId['V4-LT-3']!.plant.rawCorrectCells, 12);
      expect(
        countWordBoundaryOccurrences(
            byId['V4-LT-3']!.plant.output, byId['V4-LT-3']!.plant.gold),
        12,
      );
      expect(byId['V4-LT-2']!.capHitRate, 1.0);
    });

    test('battery gamers: ONLY probe bookkeeping refuses', () {
      final memos =
          results.where((r) => r.plant.klass == RedTeamClass.memorization);
      expect(memos, hasLength(2));
      for (final r in memos) {
        expect(r.naiveScore, 1.0, reason: '${r.plant.id} verbatim answer');
        expect(r.invariantScore, 1.0,
            reason: '${r.plant.id} format-stable (guards cannot catch it)');
        expect(r.lengthNorm, greaterThanOrEqualTo(bench.lengthNormFloor),
            reason: r.plant.id);
        expect(r.memoFlag, isTrue, reason: r.plant.id);
        expect(r.certificationExcluded, isTrue, reason: r.plant.id);
        expect(r.refusalReasons, hasLength(1), reason: r.plant.id);
        expect(r.refusal, startsWith('MEMORIZATION_EXCLUDED'),
            reason: r.plant.id);
        expect(r.refusal, contains('cue:'), reason: r.plant.id);
      }
      final byId = {for (final r in results) r.plant.id: r};
      expect(byId['V4-MEM-1']!.refusal, contains('PROBE_OVERLAP'));
      expect(byId['V4-MEM-2']!.refusal, contains('DUP_IN_SET'));
      expect(summary.excludedCells, ['G2-loop-rate', 'G5-format-holdout']);
    });

    test('the pre-registered length floor discriminates (not a rubber stamp)',
        () {
      // A concise honest win passes the floor with margin; a 200-token
      // correct cell sits exactly at it; every shipped length plant is below.
      expect(lengthNormalized(1, 40), greaterThan(bench.lengthNormFloor));
      expect(lengthNormalized(1, 200), bench.lengthNormFloor);
      for (final r in results
          .where((r) => r.plant.klass == RedTeamClass.lengthTrick)) {
        expect(r.lengthNorm, lessThan(lengthNormalized(1, 200)),
            reason: r.plant.id);
      }
    });
  });

  group('mutation checks — each leak class MUST leak when its guard is gone',
      () {
    test('FORMAT_ARTIFACT_LEAK when the invariant wrapper is bypassed', () {
      final bench = RedTeamBench.parse(mutantFixture(mutantFormatPlant));
      final guarded = bench.run().single;
      expect(guarded.verdict, verdictRefused);

      final bypassed = bench.run(bypassInvariant: true).single;
      expect(bypassed.verdict, 'FORMAT_ARTIFACT_LEAK');
      expect(bypassed.refusalReasons, isEmpty);
      // The recorded numbers stay honest under bypass: the invariant min is
      // still 0; only the VERDICT condition is removed.
      expect(bypassed.invariantScore, 0.0);
      expect(bypassed.naiveScore, 1.0);
    });

    test('LENGTH_TRICK_LEAK when the length floor is bypassed', () {
      final bench = RedTeamBench.parse(mutantFixture(mutantLengthPlant));
      expect(bench.run().single.verdict, verdictRefused);

      final bypassed = bench.run(bypassLengthFloor: true).single;
      expect(bypassed.verdict, 'LENGTH_TRICK_LEAK');
      expect(bypassed.lengthNorm, lessThan(bench.lengthNormFloor));
    });

    test('MEMORIZATION_LEAK when the bookkeeping exclusion is bypassed', () {
      final bench = RedTeamBench.parse(mutantFixture(mutantMemoPlant));
      expect(bench.run().single.verdict, verdictRefused);

      final bypassed = bench.run(bypassMemorization: true).single;
      expect(bypassed.verdict, 'MEMORIZATION_LEAK');
      expect(bypassed.memoFlag, isTrue,
          reason: 'the flag is a measurement; the bypass removes the verdict '
              'condition, not the observation');
    });

    test('shipped bench: each bypass leaks EXACTLY its own class', () {
      final bench = RedTeamBench.parse(
        File('tool/runs/redteam_plants.json').readAsStringSync(),
      );

      final noInvariant = bench.summarize(bench.run(bypassInvariant: true));
      expect(noInvariant.refusals, 6);
      expect(noInvariant.leaksNamed,
          List.filled(6, 'FORMAT_ARTIFACT_LEAK'));
      expect(noInvariant.floorMet, isFalse);

      final noFloor = bench.summarize(bench.run(bypassLengthFloor: true));
      expect(noFloor.refusals, 8);
      expect(noFloor.leaksNamed, List.filled(4, 'LENGTH_TRICK_LEAK'));
      expect(noFloor.floorMet, isFalse);

      final noBookkeeping =
          bench.summarize(bench.run(bypassMemorization: true));
      expect(noBookkeeping.refusals, 10);
      expect(noBookkeeping.leaksNamed, List.filled(2, 'MEMORIZATION_LEAK'));
      expect(noBookkeeping.floorMet, isFalse);

      final noGuards = bench.summarize(bench.run(
        bypassInvariant: true,
        bypassLengthFloor: true,
        bypassMemorization: true,
      ));
      expect(noGuards.refusals, 0);
      expect(noGuards.leaks, 12);
      expect(noGuards.floorMet, isFalse);
    });
  });

  group('probe bookkeeping excludes memorized cells (frozen probes.dart)', () {
    late RedTeamBench bench;

    setUpAll(() {
      bench = RedTeamBench.parse(
        File('tool/runs/redteam_plants.json').readAsStringSync(),
      );
    });

    test('MEM-1 probe sets throw PROBE_OVERLAP naming the shared digest', () {
      final plant = bench.plantById('V4-MEM-1');
      expect(
        () => ProbeBookkeeping.assertDisjoint(plant.probeSets!),
        throwsA(isA<ProbeSetViolation>()
            .having((e) => e.code, 'code', 'PROBE_OVERLAP')
            .having((e) => e.toString(), 'toString',
                contains('sha256:9c1f4b21d8e6'))),
      );
    });

    test('MEM-2 probe sets throw DUP_IN_SET naming the duplicated digest', () {
      final plant = bench.plantById('V4-MEM-2');
      expect(
        () => ProbeBookkeeping.assertDisjoint(plant.probeSets!),
        throwsA(isA<ProbeSetViolation>()
            .having((e) => e.code, 'code', 'DUP_IN_SET')
            .having((e) => e.toString(), 'toString',
                contains('sha256:ab34e77f02d9'))),
      );
    });

    test('control: a clean disjoint set passes and is NOT flagged', () {
      const clean = ProbeSet(
        localization: ['sha256:clean0000001'],
        certification: ['sha256:clean0000002'],
        generalization: ['sha256:clean0000003'],
      );
      expect(() => ProbeBookkeeping.assertDisjoint(clean), returnsNormally);

      final mutant = Map<String, Object?>.from(mutantMemoPlant);
      mutant['probe_sets'] = const {
        'localization': ['sha256:clean0000001'],
        'certification': ['sha256:clean0000002'],
        'generalization': ['sha256:clean0000003'],
      };
      final result = RedTeamBench.parse(mutantFixture(mutant))
          .run()
          .single;
      // Bookkeeping clean -> no memo flag; the verbatim replay alone is not
      // the exclusion trigger (the frozen violation is). The mutant's only
      // remaining guard breach is none -> it leaks, which is the honest
      // verdict for a format-stable, length-fine, bookkeeping-clean cell.
      expect(result.memoFlag, isFalse);
      expect(result.certificationExcluded, isFalse);
      expect(result.verdict, 'MEMORIZATION_LEAK');
    });

    test('bench excludes both memorized cells from certification evidence',
        () {
      final summary = bench.summarize(bench.run());
      expect(summary.excludedCells, ['G2-loop-rate', 'G5-format-holdout']);
    });
  });

  group('fixture integrity — NAMED refusals, never silent defaults', () {
    Map<String, Object?> validTopLevel(Map<String, Object?> plant) => {
          'length_norm_floor': 0.005,
          'plants': [plant],
        };

    test('the FROZEN refusal floor cannot be edited via fixture', () {
      final fixture = jsonEncode({
        'refusal_floor': 11,
        'length_norm_floor': 0.005,
        'plants': [mutantFormatPlant],
      });
      expect(
        () => RedTeamBench.parse(fixture),
        throwsA(predicate(
          (Object e) => e.toString().contains('REFUSAL_FLOOR_MISMATCH'),
        )),
      );
    });

    test('missing/malformed fields refuse with NAMED FormatExceptions', () {
      final noFloor = jsonEncode({
        'plants': [mutantFormatPlant],
      });
      expect(
        () => RedTeamBench.parse(noFloor),
        throwsA(predicate(
          (Object e) => e.toString().contains('MISSING_FIELD=length_norm_floor'),
        )),
      );

      final noPlants = jsonEncode({'length_norm_floor': 0.005});
      expect(
        () => RedTeamBench.parse(noPlants),
        throwsA(predicate(
          (Object e) => e.toString().contains('MISSING_FIELD=plants'),
        )),
      );

      final badClass = Map<String, Object?>.from(mutantFormatPlant)
        ..['class'] = 'SOMETHING_ELSE';
      expect(
        () => RedTeamBench.parse(jsonEncode(validTopLevel(badClass))),
        throwsA(predicate(
          (Object e) => e.toString().contains('UNKNOWN_CLASS=SOMETHING_ELSE'),
        )),
      );

      final noGold = Map<String, Object?>.from(mutantFormatPlant)..remove('gold');
      expect(
        () => RedTeamBench.parse(jsonEncode(validTopLevel(noGold))),
        throwsA(predicate(
          (Object e) => e.toString().contains('MISSING_FIELD=gold'),
        )),
      );

      final badScorer = Map<String, Object?>.from(mutantFormatPlant)
        ..['naive_scorer'] = 'trust_me_bro';
      expect(
        () => RedTeamBench.parse(jsonEncode(validTopLevel(badScorer))),
        throwsA(predicate(
          (Object e) => e.toString().contains('UNKNOWN_NAIVE_SCORER='),
        )),
      );

      final mismatched = Map<String, Object?>.from(mutantFormatPlant)
        ..['naive_scorer'] = 'raw_cell_count_ignores_length';
      expect(
        () => RedTeamBench.parse(jsonEncode(validTopLevel(mismatched))),
        throwsA(predicate(
          (Object e) => e.toString().contains('CLASS_SCORER_MISMATCH='),
        )),
      );
    });

    test('a non-verbatim memorization plant is refused as a bad fixture', () {
      final notVerbatim = Map<String, Object?>.from(mutantMemoPlant)
        ..['output'] = 'G9-mutant-cell: 0.43';
      expect(
        () => RedTeamBench.parse(jsonEncode(validTopLevel(notVerbatim))),
        throwsA(predicate(
          (Object e) => e.toString().contains('MEMO_PLANT_NOT_VERBATIM='),
        )),
      );
    });

    test('repetition count is text-verified: tampering refuses', () {
      final tampered = Map<String, Object?>.from(mutantLengthPlant)
        ..['naive_scorer'] = 'gold_occurrence_count'
        ..['raw_correct_cells'] = 7; // output contains gold "9" exactly once
      expect(
        () => RedTeamBench.parse(jsonEncode(validTopLevel(tampered))),
        throwsA(predicate(
          (Object e) => e.toString().contains('FIXTURE_COUNT_MISMATCH='),
        )),
      );
    });

    test('duplicate plant ids refuse', () {
      final fixture = jsonEncode({
        'length_norm_floor': 0.005,
        'plants': [mutantFormatPlant, mutantFormatPlant],
      });
      expect(
        () => RedTeamBench.parse(fixture),
        throwsA(predicate(
          (Object e) => e.toString().contains('DUPLICATE_PLANT_ID='),
        )),
      );
    });
  });

  group('receipt surface', () {
    test('plant lines carry the pre-registered fields; summary the floor', () {
      final bench = RedTeamBench.parse(
        File('tool/runs/redteam_plants.json').readAsStringSync(),
      );
      final results = bench.run();
      final lines = bench.receiptLines(results, date: '2026-11-05');
      expect(lines, hasLength(13)); // 12 plants + 1 summary

      for (final line in lines.take(12)) {
        final json = jsonDecode(line) as Map<String, Object?>;
        for (final key in [
          'id', 'class', 'naive', 'invariant', 'length_norm', 'memo_flag',
          'verdict',
        ]) {
          expect(json.containsKey(key), isTrue, reason: '$key in $line');
        }
      }
      final summary = jsonDecode(lines.last) as Map<String, Object?>;
      expect(summary['refusals'], 12);
      expect(summary['leaks'], 0);
      expect(summary['floor_met'], true);
      expect(summary['arm'], 'V-4');
      expect(summary['tier'], 'scorer');
    });
  });
}
