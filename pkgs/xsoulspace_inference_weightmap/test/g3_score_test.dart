// g3_score_test.dart — pins the G-3 scorer's frozen logic (PREREG-G §3-§6):
// the Dart detector twin against the SAME hand-computed golden vectors the
// python suite uses (cross-language pin), the movement/guard/kill/verdict
// rules on synthetic arm metrics, scoreArmRows dedup + inconsistency naming,
// and the hash-chained ledger integration.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_weightmap/xsoulspace_inference_weightmap.dart';

import '../tool/runs/g3_score.dart' as g3;
import '../tool/runs/g3_score.dart' show ArmMetrics;

Map<String, Object?> goldenDoc() =>
    jsonDecode(File('tool/runs/g3_detector_golden.json').readAsStringSync())
        as Map<String, Object?>;

ArmMetrics metrics(
  String arm, {
  int g2CapHit = 0,
  int g2Total = 12,
  int g2Ls = 0,
  int g0Pass = 8,
  int g0Total = 8,
}) =>
    ArmMetrics(
      arm: arm,
      cellsScored: g2Total + g0Total,
      duplicates: 0,
      inconsistentRows: 0,
      g2CapHit: g2CapHit,
      g2Total: g2Total,
      g2LsCells: g2Ls,
      g0Pass: g0Pass,
      g0Total: g0Total,
      medianTokensG2: 256,
      medianTokensG0: 32,
      interventions: 0,
      forwards: 0,
    );

void main() {
  group('frozen detector (golden-pinned, cross-language)', () {
    test('params match PREREG-G constants', () {
      final doc = goldenDoc();
      final p = (doc['params']! as Map).cast<String, Object?>();
      expect([p['n'], p['window'], p['threshold']],
          [g3.detN, g3.detWindow, g3.detThreshold]);
    });
    test('loopTriggers reproduces every hand-computed vector', () {
      for (final v in (goldenDoc()['vectors']! as List)) {
        final vec = (v as Map).cast<String, Object?>();
        final ids = (vec['ids']! as List).cast<int>();
        final want = (vec['triggers']! as List).cast<int>();
        expect(g3.loopTriggers(ids), want,
            reason: 'vector ${vec['name']}');
      }
    });
    test('runtime form agrees with offline form on goldens', () {
      for (final v in (goldenDoc()['vectors']! as List)) {
        final vec = (v as Map).cast<String, Object?>();
        final ids = (vec['ids']! as List).cast<int>();
        final runtime = <int>[
          for (var t = 0; t < ids.length; t++)
            if (g3.detectorFiresAt(ids.sublist(0, t + 1))) t,
        ];
        expect(runtime, (vec['triggers']! as List).cast<int>(),
            reason: 'vector ${vec['name']}');
      }
    });
  });

  group('movement rule (§6.2)', () {
    final r0 = metrics('R0', g2CapHit: 11, g2Ls: 11);
    test('large same-direction movement => moves', () {
      final mv = g3.movementRule(metrics('R3', g2CapHit: 5, g2Ls: 5), r0);
      expect(mv['moves'], isTrue);
      expect(mv['reason'], 'BOTH_CLAUSES');
    });
    test('cap clause alone is not movement', () {
      // cap-hit drops 6 cells but loop-signature unchanged => clause2 fails
      final mv = g3.movementRule(metrics('R2', g2CapHit: 5, g2Ls: 11), r0);
      expect(mv['moves'], isFalse);
      expect(mv['reason'], 'DIRECTION_ZERO');
    });
    test('direction mismatch => no movement', () {
      // R0: 10/12 cap-hit, 6/12 loop-sig; Rx: cap-hit DROPS 6 cells but
      // loop-signature RISES => clause2 fails on direction, named.
      final base = metrics('R0', g2CapHit: 10, g2Ls: 6);
      final mv = g3.movementRule(metrics('R1', g2CapHit: 4, g2Ls: 10), base);
      expect(mv['moves'], isFalse);
      expect(mv['reason'], 'DIRECTION_MISMATCH');
    });
    test('below cap floor => no movement', () {
      final mv = g3.movementRule(metrics('R1', g2CapHit: 9, g2Ls: 9), r0);
      expect(mv['moves'], isFalse);
      expect(mv['cap_hit_diff_cells'], 2);
    });
    test('LS_BASE_ZERO named when R0 has no loop signatures', () {
      final base = metrics('R0', g2CapHit: 10, g2Ls: 0);
      final mv = g3.movementRule(metrics('R3', g2CapHit: 4, g2Ls: 0), base);
      expect(mv['moves'], isFalse);
      expect(mv['reason'], 'LS_BASE_ZERO_NO_MOVEMENT');
    });
  });

  group('kill rule (§6.4)', () {
    test('R1 moves, R2/R3 within 1 => SAMPLER_GENERIC', () {
      final m = {
        'R0': metrics('R0', g2CapHit: 11, g2Ls: 11),
        'R1': metrics('R1', g2CapHit: 4, g2Ls: 4),
        'R2': metrics('R2', g2CapHit: 5, g2Ls: 5),
        'R3': metrics('R3', g2CapHit: 4, g2Ls: 4),
      };
      expect(g3.killRule(m, {}, {'R1': true, 'R2': true, 'R3': true}),
          'SAMPLER_GENERIC');
    });
    test('R2 blocked variant is named, never full kill', () {
      final m = {
        'R0': metrics('R0', g2CapHit: 11, g2Ls: 11),
        'R1': metrics('R1', g2CapHit: 4, g2Ls: 4),
        'R3': metrics('R3', g2CapHit: 5, g2Ls: 5),
      };
      expect(
          g3.killRule(m, {'R2'}, {'R1': true, 'R3': true}),
          'SAMPLER_GENERIC_PARTIAL_R2_BLOCKED');
    });
    test('R1 not moving => no kill', () {
      final m = {
        'R0': metrics('R0', g2CapHit: 11, g2Ls: 11),
        'R1': metrics('R1', g2CapHit: 10, g2Ls: 10),
        'R3': metrics('R3', g2CapHit: 4, g2Ls: 4),
      };
      expect(g3.killRule(m, {}, {'R3': true}), isNull);
    });
  });

  group('stage verdict precedence (§6.6)', () {
    test('determinism drift caps everything', () {
      expect(
          g3.stageVerdict(
            r0DeterminismReproduced: false,
            determinismRowPresent: true,
            r0G2CapHit: 12,
            r0Present: true,
            armsPresent: g3.armsFrozen.toSet(),
            blocked: {},
            kill: 'SAMPLER_GENERIC',
          ),
          'INSTRUMENT_UNVALIDATED_DETERMINISM_DRIFT');
    });
    test('headroom below floor => HEADROOM_REJECTED', () {
      expect(
          g3.stageVerdict(
            r0DeterminismReproduced: true,
            determinismRowPresent: true,
            r0G2CapHit: 7,
            r0Present: true,
            armsPresent: g3.armsFrozen.toSet(),
            blocked: {},
            kill: null,
          ),
          'HEADROOM_REJECTED');
    });
    test('blocked arm accounted, missing arm => PARTIAL named', () {
      final v = g3.stageVerdict(
        r0DeterminismReproduced: true,
        determinismRowPresent: true,
        r0G2CapHit: 11,
        r0Present: true,
        armsPresent: {'R0', 'R1', 'R3'},
        blocked: {'R2'},
        kill: null,
      );
      expect(v, 'PARTIAL_WITH_DENOMINATOR_ARMS_MISSING(NULLA)');
    });
    test('all present + gates green => INSTRUMENT_VALIDATED', () {
      expect(
          g3.stageVerdict(
            r0DeterminismReproduced: true,
            determinismRowPresent: true,
            r0G2CapHit: 10,
            r0Present: true,
            armsPresent: g3.armsFrozen.toSet(),
            blocked: {},
            kill: null,
          ),
          'INSTRUMENT_VALIDATED');
    });
  });

  group('scoreArmRows', () {
    final cellsById = <String, Map<String, Object?>>{
      'g2-a': {
        'id': 'g2-a',
        'group': 'G2',
        'cap': 256,
        'scorer': 'token_limit_cap',
        'gold': null,
      },
      'g2-b': {
        'id': 'g2-b',
        'group': 'G2',
        'cap': 256,
        'scorer': 'token_limit_cap',
        'gold': null,
      },
      'g0-a': {
        'id': 'g0-a',
        'group': 'G0',
        'cap': 64,
        'scorer': 'label_first_line',
        'gold': 'allow',
      },
    };
    Map<String, Object?> row(String cell, List<int> ids, String finish,
            {String output = '', int? forwards}) =>
        {
          'cell_id': cell,
          'generated_ids': ids,
          'output_tokens': ids.length,
          'cap_hit': finish == 'length',
          'finish_reason': finish,
          'output': output,
          'interventions': <Object?>[],
          'total_forward_tokens': forwards ?? ids.length,
        };
    test('counts, loop-signature and guard', () {
      final loopIds = List<int>.generate(256, (i) => 7); // constant loop
      final cleanIds = List<int>.generate(40, (i) => 100 + i);
      final m = g3.scoreArmRows('R0', [
        row('g2-a', loopIds, 'length'),
        row('g2-b', cleanIds, 'eos'),
        row('g0-a', [1, 2, 3], 'eos', output: 'Allow\nbecause'),
      ], cellsById);
      expect(m.g2CapHit, 1);
      expect(m.g2Total, 2);
      expect(m.g2LsCells, 1); // constant loop fires; distinct tokens do not
      expect(m.g0Pass, 1);
      expect(m.inconsistentRows, 0);
      expect(m.medianTokensG2, 148.0); // (256+40)/2
    });
    test('duplicate rows dedup last-wins and are counted', () {
      final m = g3.scoreArmRows('R0', [
        row('g2-a', List<int>.generate(10, (i) => i), 'eos'),
        row('g2-a', List<int>.generate(256, (i) => 7), 'length'),
        row('g2-b', List<int>.generate(10, (i) => i), 'eos'),
        row('g0-a', [1], 'eos', output: 'allow'),
      ], cellsById);
      expect(m.duplicates, 1);
      expect(m.g2CapHit, 1); // last row wins
    });
    test('inconsistent row is named, scored from raw fields', () {
      final bad = row('g2-a', List<int>.generate(256, (i) => 7), 'length');
      bad['output_tokens'] = 17; // inconsistent with ids length
      final m = g3.scoreArmRows('R0', [
        bad,
        row('g2-b', List<int>.generate(5, (i) => i), 'eos'),
        row('g0-a', [1], 'eos', output: 'allow'),
      ], cellsById);
      expect(m.inconsistentRows, 1);
      expect(m.g2CapHit, 1); // finish_reason == 'length' governs
    });
  });

  group('ledger integration', () {
    test('append + verifyChain round trip', () async {
      final dir = await Directory.systemTemp.createTemp('g3_ledger_test');
      try {
        final f = File('${dir.path}/G3-test.jsonl');
        append(f, 'g3_test_row', {'a': 1, 'b': [2, 3]});
        append(f, 'g3_test_row2', {'verdict': 'INSTRUMENT_VALIDATED'});
        final v = verifyChain(f);
        expect(v.label, contains('INTACT'));
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
