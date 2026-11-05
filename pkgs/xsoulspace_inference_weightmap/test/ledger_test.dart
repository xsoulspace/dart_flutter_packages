/// Laws of the append-only hash-chained ledger: the denominator journal
/// (PROGRAM.md §3, ADR 0032). Tamper detection must NAME the broken index;
/// an empty ledger must verify; the digest law must recompute.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_weightmap/src/ledger.dart';

/// Rewrites one line of the ledger file from a mutated decoded row (keeps the
/// wire JSON valid so the tests exercise the CHAIN, not the parser).
void _mutateLine(File file, int index, void Function(Map<String, Object?>) m) {
  final lines = file.readAsLinesSync();
  final row = Map<String, Object?>.from(jsonDecode(lines[index]) as Map);
  m(row);
  lines[index] = jsonEncode(row);
  file.writeAsStringSync(lines.map((l) => '$l\n').join());
}

void main() {
  // Probe scratch law: test artifacts live under $TMPDIR, never in the tree.
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('weightmap_ledger'));
  tearDown(() => tmp.deleteSync(recursive: true));
  File ledgerFile() => File('${tmp.path}/verdicts.jsonl');

  group('canonicalJson', () {
    test('sorts keys recursively and strips whitespace', () {
      expect(
        canonicalJson({
          'b': 1,
          'a': {
            'd': [
              3,
              {'z': 1, 'y': 2},
            ],
            'c': 2,
          },
        }),
        '{"a":{"c":2,"d":[3,{"y":2,"z":1}]},"b":1}',
      );
    });

    test('names values JSON cannot carry', () {
      expect(
        () => canonicalJson({'a': DateTime.now()}),
        throwsA(
          isArgumentError.having(
            (e) => e.message,
            'message',
            contains('NON_CANONICALIZABLE'),
          ),
        ),
      );
      expect(
        () => canonicalJson({1: 'x'}),
        throwsA(
          isArgumentError.having(
            (e) => e.message,
            'message',
            contains('NON_STRING_KEY'),
          ),
        ),
      );
    });
  });

  group('append / readAll / verifyChain', () {
    test('empty ledger verifies (rows = 0)', () {
      final f = ledgerFile()..createSync(recursive: true);
      expect(readAll(f), isEmpty);
      final v = verifyChain(f);
      expect(v, isA<ChainIntact>());
      expect((v as ChainIntact).rows, 0);
      expect(v.label, 'CHAIN_INTACT');
    });

    test('a missing file is a named FileSystemException, not empty', () {
      expect(() => readAll(ledgerFile()), throwsA(isA<FileSystemException>()));
    });

    test('append creates, links, and reads back rows', () {
      final f = ledgerFile();
      final r0 = append(f, 'direction_proposed', {
        'direction': 'planted-0',
        'rank': 1,
      });
      final r1 = append(f, 'run', {'arm': 'arm-003', 'score': 0.75});
      final r2 = append(f, 'failure', {'reason': 'STALE_PRECONDITION'});

      expect(r0.seq, 0);
      expect(r0.prevDigest, genesisPrevDigest);
      expect(genesisPrevDigest, '0' * 64);
      expect(r1.prevDigest, r0.digest);
      expect(r2.prevDigest, r1.digest);
      expect(r1.seq, 1);

      final rows = readAll(f);
      expect(rows.length, 3);
      expect(
        rows.map((r) => r.kind),
        ['direction_proposed', 'run', 'failure'],
      );
      expect(rows[1].payload, {'arm': 'arm-003', 'score': 0.75});

      // The frozen chain law recomputes from the row content.
      for (final r in rows) {
        expect(
          r.digest,
          LedgerRow.computeDigest(
            prevDigest: r.prevDigest,
            seq: r.seq,
            ts: r.ts,
            kind: r.kind,
            payload: r.payload,
          ),
        );
      }

      expect(verifyChain(f), isA<ChainIntact>());

      // The wire format is canonical json: first key is the sorted-first one.
      expect(f.readAsLinesSync().first, startsWith('{"digest":'));
    });

    test('tamper: one character mid-file names CHAIN_BROKEN_AT=2', () {
      final f = ledgerFile();
      for (var i = 0; i < 5; i++) {
        append(f, 'run', {'tag': 'row-$i'});
      }
      // Flip one payload character in the middle row ('2' -> 'X').
      _mutateLine(f, 2, (row) {
        (row['payload'] as Map<String, Object?>)['tag'] = 'row-X';
      });
      final v = verifyChain(f);
      expect(v, isA<ChainBroken>());
      final broken = v as ChainBroken;
      expect(broken.index, 2);
      expect(broken.label, 'CHAIN_BROKEN_AT=2');
      expect(broken.cause, contains('DIGEST_MISMATCH'));
      expect('$broken', startsWith('CHAIN_BROKEN_AT=2'));
    });

    test('tamper: each broken link names its own cause', () {
      final f = ledgerFile();
      for (var i = 0; i < 5; i++) {
        append(f, 'run', {'tag': 'row-$i'});
      }

      _mutateLine(f, 3, (row) => row['digest'] = 'f' * 64);
      var v = verifyChain(f) as ChainBroken;
      expect(v.index, 3);
      expect(v.cause, contains('DIGEST_MISMATCH'));

      // A broken prev-link earlier in the chain is reported FIRST (index 2),
      // even though row 3's digest is still tampered beyond it.
      _mutateLine(f, 2, (row) => row['prevDigest'] = 'a' * 64);
      v = verifyChain(f) as ChainBroken;
      expect(v.index, 2);
      expect(v.cause, contains('PREV_LINK_MISMATCH'));

      final f2 = File('${tmp.path}/seq.jsonl');
      for (var i = 0; i < 3; i++) {
        append(f2, 'run', {'tag': 'row-$i'});
      }
      _mutateLine(f2, 1, (row) => row['seq'] = 7);
      v = verifyChain(f2) as ChainBroken;
      expect(v.index, 1);
      expect(v.cause, contains('SEQ_GAP'));
    });

    test('malformed wire line names CHAIN_BROKEN_AT=1', () {
      final f = ledgerFile();
      for (var i = 0; i < 3; i++) {
        append(f, 'run', {'tag': 'row-$i'});
      }
      final lines = f.readAsLinesSync();
      lines[1] = '{{{ not json';
      f.writeAsStringSync(lines.map((l) => '$l\n').join());

      expect(
        () => readAll(f),
        throwsA(
          isA<LedgerFormatException>()
              .having((e) => e.index, 'index', 1)
              .having(
                (e) => e.toString(),
                'toString',
                startsWith('MALFORMED_ROW_AT=1'),
              ),
        ),
      );
      final v = verifyChain(f) as ChainBroken;
      expect(v.index, 1);
      expect(v.label, 'CHAIN_BROKEN_AT=1');
      expect(v.cause, contains('MALFORMED_ROW'));
    });

    test('a row missing a field is named, not defaulted', () {
      final f = ledgerFile();
      append(f, 'run', {'tag': 'row-0'});
      _mutateLine(f, 0, (row) => row.remove('kind'));
      expect(
        () => readAll(f),
        throwsA(
          isA<LedgerFormatException>().having(
            (e) => e.detail,
            'detail',
            contains('MISSING_FIELD=kind'),
          ),
        ),
      );
    });
  });

  group('denominators', () {
    test('counts every row by kind (the denominator law)', () {
      final f = ledgerFile();
      append(f, 'direction_proposed', {'direction': 'planted-0'});
      append(f, 'direction_proposed', {'direction': 'null-0'});
      append(f, 'run', {'arm': 'arm-000'});
      append(f, 'failure', {'reason': 'OVERLAP'});
      expect(denominators(f), {
        'direction_proposed': 2,
        'run': 1,
        'failure': 1,
      });
      // "1 win of 2 attempts" is structurally readable from the ledger.
    });

    test('empty ledger has empty denominators', () {
      final f = ledgerFile()..createSync(recursive: true);
      expect(denominators(f), isEmpty);
    });
  });
}
