import 'dart:convert';

import 'package:test/test.dart';
import 'package:xsoulspace_materialization_core/xsoulspace_materialization_core.dart';

TextChangeCandidate candidate({
  String workspace = '/workspace/project',
  Map<String, String?>? observed,
  Map<String, String?>? changes,
  Map<String, Object?> evidence = const {},
  int budget = 1 << 20,
}) => TextChangeCandidate(
  workspaceIdentity: workspace,
  originTaskId: 'task:1',
  originActorRef: 'actor:1',
  observedSource: observed ?? {'src/main.dart': 'old\n'},
  intendedChanges: changes ?? {'src/main.dart': 'new\n'},
  verificationDescription: 'native frozen checks passed',
  checkEvidence: evidence,
  maxDecodedBytes: budget,
);

void main() {
  test(
    'snapshot preserves absent, empty and exact text across canonical roundtrip',
    () {
      final snapshot = candidate(
        observed: {'new.txt': null, 'empty.txt': '', 'deleted.txt': 'old\r\n'},
        changes: {'new.txt': '', 'empty.txt': ' ', 'deleted.txt': null},
        evidence: {
          'utf8': 'emoji 🐬',
          'number': 1,
          'passed': true,
          'missing': null,
        },
      );
      final restored = TextChangeCandidate.decode(
        snapshot.canonicalJson,
        maxDecodedBytes: 4096,
      );
      expect(restored.observedSource['new.txt'], isNull);
      expect(restored.observedSource['empty.txt'], '');
      expect(restored.observedSource['deleted.txt'], 'old\r\n');
      expect(restored.intendedChanges['new.txt'], '');
      expect(restored.intendedChanges['empty.txt'], ' ');
      expect(restored.intendedChanges['deleted.txt'], isNull);
      expect(restored.canonicalJson, snapshot.canonicalJson);
      expect(restored.originTaskId, 'task:1');
      expect(restored.originActorRef, 'actor:1');
    },
  );

  test(
    'input maps, nested evidence and exported JSON cannot mutate snapshot',
    () {
      final observed = <String, String?>{'file': 'old'};
      final changes = <String, String?>{'file': 'new'};
      final nested = <String, Object?>{'result': 'original'};
      final list = <Object?>[nested];
      final evidence = <String, Object?>{'checks': list};
      final snapshot = candidate(
        observed: observed,
        changes: changes,
        evidence: evidence,
      );
      final original = snapshot.canonicalJson;
      observed['file'] = 'changed';
      changes.clear();
      nested['result'] = 'tampered';
      list.clear();
      evidence.clear();
      expect(snapshot.canonicalJson, original);
      expect(snapshot.observedSource['file'], 'old');
      expect(snapshot.intendedChanges['file'], 'new');
      expect(
        () => snapshot.observedSource['file'] = 'x',
        throwsUnsupportedError,
      );
      final checks = snapshot.checkEvidence['checks']! as List<Object?>;
      expect(() => checks.add(null), throwsUnsupportedError);
      expect(
        () => (checks.single! as Map<String, Object?>)['result'] = 'x',
        throwsUnsupportedError,
      );
      final exported = snapshot.toJson();
      (exported['intendedChanges'] as Map)['file'] = 'edited';
      ((exported['checkEvidence'] as Map)['checks'] as List).clear();
      expect(snapshot.canonicalJson, original);
    },
  );

  test(
    'every object sorts keys; insertion order cannot change canonical artifact',
    () {
      final first = candidate(
        observed: {'z': null, 'a': 'old'},
        changes: {'z': 'new', 'a': null},
        evidence: {
          'z': [
            {'z': 2, 'a': 1},
          ],
          'a': false,
        },
      );
      final second = candidate(
        observed: {'a': 'old', 'z': null},
        changes: {'a': null, 'z': 'new'},
        evidence: {
          'a': false,
          'z': [
            {'a': 1, 'z': 2},
          ],
        },
      );
      expect(first.canonicalJson, second.canonicalJson);
      expect(first.canonicalJson, contains('"a":1,"z":2'));
      expect(
        first.canonicalJson,
        contains('"observedSource":{"a":"old","z":null}'),
      );
    },
  );

  test('rejects traversal, aliases, absolute and malformed relative paths', () {
    for (final path in [
      '',
      '/abs',
      '../x',
      'a/../x',
      './x',
      'a//x',
      'a/',
      r'a\x',
      'C:x',
      'C:/x',
      ' x',
      'x ',
      'a\nfile',
      'a\u0000file',
    ]) {
      expect(
        () => candidate(observed: {path: null}, changes: {path: 'new'}),
        throwsFormatException,
        reason: path,
      );
    }
    expect(
      candidate(
        observed: {'my dir/file 🐬.txt': null},
        changes: {'my dir/file 🐬.txt': 'new'},
      ).intendedChanges.keys.single,
      'my dir/file 🐬.txt',
    );
  });

  test('unobserved changes, empty changes and all per-file no-ops refuse', () {
    expect(
      () => candidate(changes: {'different': 'new'}),
      throwsFormatException,
    );
    expect(() => candidate(changes: {}), throwsFormatException);
    for (final value in <String?>[null, '', 'same']) {
      expect(
        () => candidate(observed: {'file': value}, changes: {'file': value}),
        throwsFormatException,
      );
    }
    expect(
      () => candidate(
        observed: {'ok': null, 'noop': 'same'},
        changes: {'ok': 'new', 'noop': 'same'},
      ),
      throwsFormatException,
    );
  });

  test('strict required/unknown fields, value shapes and version', () {
    final valid = candidate().toJson();
    for (final key in [
      'version',
      'workspaceIdentity',
      'originTaskId',
      'observedSource',
      'intendedChanges',
      'verificationDescription',
      'checkEvidence',
    ]) {
      final missing = Map<String, Object?>.from(valid)..remove(key);
      expect(
        () => TextChangeCandidate.fromJson(missing, maxDecodedBytes: 4096),
        throwsFormatException,
      );
    }
    for (final bad in <Map<String, Object?>>[
      {...valid, 'authority': true},
      {...valid, 'version': 2},
      {...valid, 'version': 1.0},
      {
        ...valid,
        'observedSource': {'src/main.dart': 42},
      },
      {
        ...valid,
        'intendedChanges': {
          'src/main.dart': [1, 2],
        },
      },
      {...valid, 'checkEvidence': []},
      {...valid, 'originActorRef': false},
      {...valid, 'originTaskId': ' '},
      {...valid, 'verificationDescription': ''},
    ]) {
      expect(
        () => TextChangeCandidate.fromJson(bad, maxDecodedBytes: 4096),
        throwsFormatException,
      );
    }
    final optional = Map<String, Object?>.from(valid)..remove('originActorRef');
    expect(
      TextChangeCandidate.fromJson(
        optional,
        maxDecodedBytes: 4096,
      ).originActorRef,
      isNull,
    );
  });

  test(
    'budget is exact UTF8 canonical size and applies before JSON parsing',
    () {
      final snapshot = candidate(evidence: {'unicode': '🐬\n"'});
      final size = utf8.encode(snapshot.canonicalJson).length;
      expect(
        candidate(evidence: {'unicode': '🐬\n"'}, budget: size).canonicalJson,
        snapshot.canonicalJson,
      );
      expect(
        () => candidate(evidence: {'unicode': '🐬\n"'}, budget: size - 1),
        throwsFormatException,
      );
      expect(
        () => TextChangeCandidate.decode(
          snapshot.canonicalJson,
          maxDecodedBytes: size - 1,
        ),
        throwsFormatException,
      );
      expect(
        () => TextChangeCandidate.decode('x' * 1000, maxDecodedBytes: 10),
        throwsFormatException,
      );
      expect(() => candidate(budget: 0), throwsFormatException);
    },
  );

  test('unsupported evidence, nonfinite values, cycles and depth refuse', () {
    final cycle = <Object?>[];
    cycle.add(cycle);
    Object? deep;
    for (var i = 0; i < 70; i++) {
      deep = [deep];
    }
    for (final value in [
      Object(),
      BigInt.one,
      double.nan,
      double.infinity,
      {1: 'bad'},
      cycle,
      deep,
    ]) {
      expect(() => candidate(evidence: {'bad': value}), throwsFormatException);
    }
    expect(
      () => candidate(changes: {'src/main.dart': String.fromCharCode(0xD800)}),
      throwsFormatException,
    );
  });

  test('canonical decode rejects whitespace and duplicate JSON fields', () {
    final snapshot = candidate();
    expect(
      () => TextChangeCandidate.decode(
        ' ${snapshot.canonicalJson}',
        maxDecodedBytes: 4096,
      ),
      throwsFormatException,
    );
    final duplicate = snapshot.canonicalJson.replaceFirst('{', '{"version":1,');
    expect(
      () => TextChangeCandidate.decode(duplicate, maxDecodedBytes: 4096),
      throwsFormatException,
    );
    expect(
      () => TextChangeCandidate.decode('[]', maxDecodedBytes: 4096),
      throwsFormatException,
    );
  });

  test(
    'workspace lexical shape is checked without pretending native resolution',
    () {
      for (final path in [
        'relative',
        '/a/../b',
        '/a//b',
        '/a/',
        ' /a',
        '/a\n',
      ]) {
        expect(() => candidate(workspace: path), throwsFormatException);
      }
      expect(
        candidate(workspace: r'C:\work\project').workspaceIdentity,
        r'C:\work\project',
      );
      expect(
        candidate(workspace: r'\\server\share\project').workspaceIdentity,
        r'\\server\share\project',
      );
      expect(candidate(workspace: '/').workspaceIdentity, '/');
    },
  );
}
