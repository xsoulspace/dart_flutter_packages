// Probe-set bookkeeping fixtures: disjoint sets pass, any cross-set overlap
// refuses with the NAMED code PROBE_OVERLAP (detail quotes "a∩b={digests}"),
// duplicates within one set refuse with DUP_IN_SET, and CellRef stays a pure
// string value type (this package must not depend on engine packages).
import 'package:test/test.dart';
import 'package:xsoulspace_inference_weightmap/src/probes.dart';

ProbeSet _set({
  List<String> localization = const ['loc-1', 'loc-2'],
  List<String> certification = const ['cert-1', 'cert-2'],
  List<String> generalization = const ['gen-1', 'gen-2'],
}) =>
    ProbeSet(
      localization: localization,
      certification: certification,
      generalization: generalization,
    );

void main() {
  group('ProbeBookkeeping.assertDisjoint', () {
    test('disjoint sets: ok (returns normally)', () {
      expect(() => ProbeBookkeeping.assertDisjoint(_set()), returnsNormally);
    });

    test('empty sets are trivially ok', () {
      expect(
        () => ProbeBookkeeping.assertDisjoint(
          _set(localization: [], certification: [], generalization: []),
        ),
        returnsNormally,
      );
    });

    test('localization∩certification overlap refuses, NAMED', () {
      expect(
        () => ProbeBookkeeping.assertDisjoint(_set(
          localization: ['shared-digest', 'loc-2'],
          certification: ['cert-1', 'shared-digest'],
        )),
        throwsA(isA<ProbeSetViolation>()
            .having((e) => e.code, 'code', 'PROBE_OVERLAP')
            .having((e) => e.detail, 'detail',
                contains('localization∩certification'))
            .having((e) => e.detail, 'detail', contains('shared-digest'))
            .having((e) => e.toString(), 'toString',
                startsWith('PROBE_OVERLAP:'))),
      );
    });

    test('localization∩generalization overlap refuses, NAMED', () {
      expect(
        () => ProbeBookkeeping.assertDisjoint(_set(
          localization: ['x', 'loc-2'],
          generalization: ['x', 'gen-2'],
        )),
        throwsA(isA<ProbeSetViolation>()
            .having((e) => e.code, 'code', 'PROBE_OVERLAP')
            .having(
                (e) => e.detail, 'detail', contains('localization∩generalization'))),
      );
    });

    test('certification∩generalization overlap refuses, NAMED', () {
      expect(
        () => ProbeBookkeeping.assertDisjoint(_set(
          certification: ['cert-1', 'y'],
          generalization: ['y', 'gen-2'],
        )),
        throwsA(isA<ProbeSetViolation>()
            .having((e) => e.code, 'code', 'PROBE_OVERLAP')
            .having((e) => e.detail, 'detail',
                contains('certification∩generalization'))),
      );
    });

    test('duplicate within one set refuses, NAMED DUP_IN_SET', () {
      expect(
        () => ProbeBookkeeping.assertDisjoint(
          _set(certification: ['cert-1', 'cert-1']),
        ),
        throwsA(isA<ProbeSetViolation>()
            .having((e) => e.code, 'code', 'DUP_IN_SET')
            .having((e) => e.detail, 'detail', contains('certification'))
            .having((e) => e.detail, 'detail', contains('cert-1'))
            .having((e) => e.toString(), 'toString', startsWith('DUP_IN_SET:'))),
      );
    });

    test('DUP_IN_SET is checked before PROBE_OVERLAP (never masked)', () {
      // localization has a duplicate AND overlaps certification: the
      // bookkeeping error in one set is reported first.
      expect(
        () => ProbeBookkeeping.assertDisjoint(_set(
          localization: ['d', 'd'],
          certification: ['d', 'cert-2'],
        )),
        throwsA(isA<ProbeSetViolation>()
            .having((e) => e.code, 'code', 'DUP_IN_SET')),
      );
    });

    test('overlap detail lists every shared digest, sorted', () {
      try {
        ProbeBookkeeping.assertDisjoint(_set(
          localization: ['b', 'a'],
          certification: ['a', 'b'],
        ));
        fail('expected a PROBE_OVERLAP refusal');
      } on ProbeSetViolation catch (e) {
        expect(e.code, 'PROBE_OVERLAP');
        expect(e.detail, contains('{a, b}'));
      }
    });
  });

  group('CellRef', () {
    test('frozen G-cell names are pure strings with value equality', () {
      const a = CellRef('G2-loop-rate');
      const b = CellRef('G2-loop-rate');
      const c = CellRef('G0-task-success');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a.toString(), 'CellRef(G2-loop-rate)');
      expect(a.name, 'G2-loop-rate');
    });
  });
}
