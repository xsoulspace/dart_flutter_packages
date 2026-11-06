/// Laws of WS-2 cross-engine certification (lib/src/cross_engine.dart), as
/// tests: the frozen bundle schema with NAMED MALFORMED_BUNDLE refusals, the
/// Python-first role law (python_mlxlm reference, rust candidate, argument
/// order irrelevant), the pre-registered edge-INCLUSIVE tolerance rule, and
/// the mismatch-lists-every-cell denominator law.
library;

import 'package:test/test.dart';
import 'package:xsoulspace_inference_weightmap/src/cross_engine.dart';
import 'package:xsoulspace_inference_weightmap/src/patch_algebra.dart'
    show Tolerance;

Map<String, Object?> cell(
  String name, {
  double value = 0.5,
  String logits = 'logits-digest',
  String behavior = 'behavior-digest',
}) =>
    {
      'cell': name,
      'logits_digest': logits,
      'behavior_digest': behavior,
      'behavior_value': value,
    };

Map<String, Object?> bundle(String engine, List<Object?> cells) =>
    {'engine': engine, 'cells': cells};

DigestBundle py(List<Object?> cells) =>
    DigestBundle.fromJson(bundle('python_mlxlm', cells));

DigestBundle rust(List<Object?> cells) =>
    DigestBundle.fromJson(bundle('rust', cells));

void main() {
  group('CrossEngine wire vocabulary', () {
    test('engine fields are the frozen pair', () {
      expect(CrossEngine.rust.wire, 'rust');
      expect(CrossEngine.pythonMlxlm.wire, 'python_mlxlm');
      expect(CrossEngine.fromWire('rust'), CrossEngine.rust);
      expect(CrossEngine.fromWire('python_mlxlm'), CrossEngine.pythonMlxlm);
      expect(
        () => CrossEngine.fromWire('tensorflow'),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('ENGINE_UNKNOWN=tensorflow'))),
      );
    });
  });

  group('DigestBundle parser: MALFORMED_BUNDLE is named, never defaulted', () {
    test('a valid bundle parses and round-trips through json', () {
      final json = bundle('rust', [
        cell('g0-task', value: 0.75, logits: 'la', behavior: 'ba'),
        cell('g2-loop', value: 0.25, logits: 'lb', behavior: 'bb'),
      ]);
      final parsed = DigestBundle.fromJson(json);
      expect(parsed.engine, CrossEngine.rust);
      expect(parsed.cells.length, 2);
      expect(parsed.cells.first.cell, 'g0-task');
      expect(parsed.cells.first.behaviorValue, 0.75);
      expect(parsed.cellsByName.keys, ['g0-task', 'g2-loop']);
      expect(parsed.toJson(), equals(json));
    });

    test('top-level shape refusals', () {
      final cases = <String, Map<String, Object?>>{
        'missing engine': {'cells': [cell('c')]},
        'missing cells': {'engine': 'rust'},
        'extra key': {...bundle('rust', [cell('c')]), 'extra': 1},
      };
      cases.forEach((name, json) {
        expect(
          () => DigestBundle.fromJson(json),
          throwsA(isA<FormatException>().having((e) => e.message, 'message',
              allOf(contains('MALFORMED_BUNDLE'), contains('keys mismatch')))),
          reason: name,
        );
      });
      expect(
        () => DigestBundle.fromJson({'engine': 7, 'cells': [cell('c')]}),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('MALFORMED_FIELD=engine'))),
      );
      expect(
        () => DigestBundle.fromJson({'engine': 'rust', 'cells': 'nope'}),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('MALFORMED_FIELD=cells'))),
      );
      expect(
        () => DigestBundle.fromJson(bundle('onnx', [cell('c')])),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('ENGINE_UNKNOWN'))),
      );
      expect(
        () => DigestBundle.fromJson(bundle('rust', [])),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('EMPTY_CELLS'))),
      );
    });

    test('cell-level refusals name the offending index', () {
      expect(
        () => DigestBundle.fromJson(bundle('rust', ['not-an-object'])),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('cells[0] CELL_NOT_OBJECT'))),
      );
      final missing = cell('c')..remove('logits_digest');
      expect(
        () => DigestBundle.fromJson(bundle('rust', [missing])),
        throwsA(isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('cells[0] keys mismatch'),
                contains('logits_digest')))),
      );
      final extra = {...cell('c'), 'surprise': true};
      expect(
        () => DigestBundle.fromJson(bundle('rust', [extra])),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('keys mismatch'))),
      );
      expect(
        () => DigestBundle.fromJson(
            bundle('rust', [cell(''), cell('ok', value: 1)])),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('MALFORMED_FIELD=cell'))),
      );
      expect(
        () => DigestBundle.fromJson(bundle('rust', [
          {'cell': 'c', 'logits_digest': '', 'behavior_digest': 'b', 'behavior_value': 1.0}
        ])),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('MALFORMED_FIELD=logits_digest'))),
      );
      // bool is not a number, and the second cell's index is named.
      expect(
        () => DigestBundle.fromJson(bundle('rust', [
          cell('fine'),
          {'cell': 'c2', 'logits_digest': 'l', 'behavior_digest': 'b', 'behavior_value': true},
        ])),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('cells[1] MALFORMED_FIELD=behavior_value'))),
      );
      expect(
        () => DigestBundle.fromJson(bundle('rust', [cell('dup'), cell('dup')])),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('DUPLICATE_CELL=dup'))),
      );
    });

    test('constructor guards duplicates and empties independently of json', () {
      final c = CellDigest(
          cell: 'x', logitsDigest: 'l', behaviorDigest: 'b', behaviorValue: 0);
      expect(
        () => DigestBundle(engine: CrossEngine.rust, cells: [c, c]),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('DUPLICATE_CELL=x'))),
      );
      expect(
        () => DigestBundle(engine: CrossEngine.rust, cells: []),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('EMPTY_CELLS'))),
      );
    });
  });

  group('certify: Python-first role law', () {
    final pyBundle = py([cell('g2-loop', value: 0.30, logits: 'same')]);
    // 0.305 not 0.31: the IEEE delta 0.31 - 0.30 is 0.010000000000000009,
    // one float step PAST the registered 0.01 edge — the inclusive rule would
    // (correctly) refuse it. 0.305 - 0.30 = 0.005 is honestly within.
    final rustBundle = rust([cell('g2-loop', value: 0.305, logits: 'same')]);
    final tol = Tolerance(abs: 0.01, rel: 0);

    test('roles come from engine fields, not argument order', () {
      final ab = CrossEngineCertification.certify(
          a: pyBundle, b: rustBundle, tolerance: tol);
      final ba = CrossEngineCertification.certify(
          a: rustBundle, b: pyBundle, tolerance: tol);
      expect(ab, isA<Agree>());
      expect(ba, isA<Agree>());
      expect((ab as Agree).cellsCompared, 1);
      expect(ab.logitsBitwiseEqual, 1);
      expect((ba as Agree).cellsCompared, 1);
    });

    test('a pair without exactly one reference + one candidate is REFUSED, '
        'named', () {
      final twoRust = CrossEngineCertification.certify(
          a: rustBundle,
          b: rust([cell('other', value: 0.31)]),
          tolerance: tol);
      expect(twoRust, isA<CertificationRefused>());
      final refused = twoRust as CertificationRefused;
      expect(refused.reason, CertificationRefused.enginePairInvalid);
      expect(refused.reason, 'ENGINE_PAIR_INVALID');
      expect(refused.detail, contains('python_mlxlm'));
      expect(refused.label, 'CERTIFICATION_REFUSED');
      final twoPy = CrossEngineCertification.certify(
          a: pyBundle, b: py([cell('other')]), tolerance: tol);
      expect(twoPy, isA<CertificationRefused>());
      expect((twoPy as CertificationRefused).reason, 'ENGINE_PAIR_INVALID');
    });

    test('mismatch details always attribute expected=python_mlxlm, '
        'actual=rust (rust must match python, never the reverse)', () {
      final v = CrossEngineCertification.certify(
        a: rust([cell('g2-loop', value: 0.45)]),
        b: py([cell('g2-loop', value: 0.30)]),
        tolerance: tol,
      );
      expect(v, isA<Mismatch>());
      final detail = (v as Mismatch).cells.single.detail;
      expect(detail, contains('expected(python_mlxlm)=0.3'));
      expect(detail, contains('actual(rust)=0.45'));
    });
  });

  group('certify: pre-registered tolerance rule (edge-inclusive)', () {
    test('within the per-cell absolute bound: AGREE despite digest drift', () {
      // Different logits/behavior digests (different kernel float order) but
      // behavior values within the registered bound: digests key, numbers
      // decide.
      final v = CrossEngineCertification.certify(
        a: py([
          cell('g0-task', value: 0.80, logits: 'py-a', behavior: 'py-ba'),
          cell('g2-loop', value: 0.30, logits: 'py-b', behavior: 'py-bb'),
        ]),
        b: rust([
          cell('g0-task', value: 0.805, logits: 'rs-a', behavior: 'rs-ba'),
          cell('g2-loop', value: 0.295, logits: 'rs-b', behavior: 'rs-bb'),
        ]),
        tolerance: Tolerance(abs: 0.01, rel: 0),
      );
      expect(v, isA<Agree>());
      final agree = v as Agree;
      expect(agree.label, 'AGREE');
      expect(agree.cellsCompared, 2);
      expect(agree.logitsBitwiseEqual, 0); // recorded evidence, not a criterion
    });

    test('delta exactly at the registered edge passes; one step beyond fails',
        () {
      final atEdge = CrossEngineCertification.certify(
        a: py([cell('c', value: 0.5)]),
        b: rust([cell('c', value: 0.75)]),
        tolerance: Tolerance(abs: 0.25, rel: 0),
      );
      expect(atEdge, isA<Agree>());
      final pastEdge = CrossEngineCertification.certify(
        a: py([cell('c', value: 0.5)]),
        b: rust([cell('c', value: 0.7500000000000001)]),
        tolerance: Tolerance(abs: 0.25, rel: 0),
      );
      expect(pastEdge, isA<Mismatch>());
      expect((pastEdge as Mismatch).cells.single.reason,
          Mismatch.behaviorDelta);
      expect(pastEdge.cells.single.reason,
          'BEHAVIOR_DELTA_OUT_OF_TOLERANCE');
    });

    test('rel term scales by the larger magnitude (same rule as Tolerance)',
        () {
      final tol = Tolerance(abs: 0, rel: 0.1);
      expect(
        CrossEngineCertification.certify(
            a: py([cell('c', value: 100)]),
            b: rust([cell('c', value: 110)]),
            tolerance: tol),
        isA<Agree>(),
      ); // 10 <= 0.1 * 110
      expect(
        CrossEngineCertification.certify(
            a: py([cell('c', value: 100)]),
            b: rust([cell('c', value: 112)]),
            tolerance: tol),
        isA<Mismatch>(),
      ); // 12 > 0.1 * 112
    });

    test('Tolerance.exact: only bit-equal values agree', () {
      expect(
        CrossEngineCertification.certify(
            a: py([cell('c', value: 0.25)]),
            b: rust([cell('c', value: 0.25)]),
            tolerance: Tolerance.exact),
        isA<Agree>(),
      );
      expect(
        CrossEngineCertification.certify(
            a: py([cell('c', value: 0.25)]),
            b: rust([cell('c', value: 0.25000000000000006)]),
            tolerance: Tolerance.exact),
        isA<Mismatch>(),
      );
    });
  });

  group('certify: mismatch lists every offending cell, named', () {
    test('all out-of-tolerance cells appear, in reference order', () {
      final v = CrossEngineCertification.certify(
        a: py([
          cell('g0-task', value: 0.80),
          cell('g1-format', value: 0.50),
          cell('g2-loop', value: 0.30),
        ]),
        b: rust([
          cell('g0-task', value: 0.95), // out
          cell('g1-format', value: 0.505), // within
          cell('g2-loop', value: 0.10), // out
        ]),
        tolerance: Tolerance(abs: 0.01, rel: 0),
      );
      expect(v, isA<Mismatch>());
      final m = v as Mismatch;
      expect(m.label, 'MISMATCH');
      expect(m.cellsCompared, 3);
      expect(m.cells.map((c) => c.cell), ['g0-task', 'g2-loop']);
      expect(m.cells.every((c) => c.reason == 'BEHAVIOR_DELTA_OUT_OF_TOLERANCE'),
          isTrue);
      expect('$m', contains('g0-task'));
      expect('$m', contains('g2-loop'));
    });

    test('cell-set drift is named per side', () {
      final v = CrossEngineCertification.certify(
        a: py([cell('shared', value: 0.5), cell('only-in-python')]),
        b: rust([cell('shared', value: 0.5), cell('only-in-rust')]),
        tolerance: Tolerance(abs: 0.01, rel: 0),
      );
      expect(v, isA<Mismatch>());
      final m = v as Mismatch;
      expect(m.cellsCompared, 1); // only the shared cell was evaluated
      expect(m.cells.length, 2);
      final byCell = {for (final c in m.cells) c.cell: c.reason};
      expect(byCell['only-in-python'], 'CELL_MISSING_IN_CANDIDATE');
      expect(byCell['only-in-rust'], 'CELL_MISSING_IN_REFERENCE');
      expect(byCell['only-in-python'], Mismatch.missingInCandidate);
      expect(byCell['only-in-rust'], Mismatch.missingInReference);
    });
  });

  group('verdict records are ledger-ready json', () {
    test('AGREE / MISMATCH / CERTIFICATION_REFUSED wire shapes', () {
      final tol = Tolerance(abs: 0.01, rel: 0);
      final agree = CrossEngineCertification.certify(
          a: py([cell('c', value: 0.5, logits: 'same')]),
          b: rust([cell('c', value: 0.5, logits: 'same')]),
          tolerance: tol) as Agree;
      expect(agree.toJson(), {
        'verdict': 'AGREE',
        'reference_engine': 'python_mlxlm',
        'candidate_engine': 'rust',
        'cells_compared': 1,
        'logits_bitwise_equal': 1,
        'mismatches': [],
      });
      final mismatch = CrossEngineCertification.certify(
          a: py([cell('c', value: 0.5)]),
          b: rust([cell('c', value: 0.9)]),
          tolerance: tol) as Mismatch;
      final mj = mismatch.toJson();
      expect(mj['verdict'], 'MISMATCH');
      expect(mj['reference_engine'], 'python_mlxlm');
      expect(mj['candidate_engine'], 'rust');
      final row = (mj['mismatches']! as List).single as Map<String, Object?>;
      expect(row.keys.toList(), ['cell', 'reason', 'detail']);
      expect(row['cell'], 'c');
      expect(row['reason'], 'BEHAVIOR_DELTA_OUT_OF_TOLERANCE');
      expect(row['detail']! as String, contains('expected(python_mlxlm)=0.5'));
      expect(row['detail']! as String, contains('actual(rust)=0.9'));
      final refused = CrossEngineCertification.certify(
          a: py([cell('c')]), b: py([cell('c')]), tolerance: tol)
          as CertificationRefused;
      expect(refused.toJson(), {
        'verdict': 'CERTIFICATION_REFUSED',
        'reason': 'ENGINE_PAIR_INVALID',
        'detail': refused.detail,
      });
    });
  });
}
