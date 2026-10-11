import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_live_apply/universal_storage_live_apply.dart';

import 'memory_provider.dart';

class _FailingStore extends LiveApplyJournalStore {
  _FailingStore({required super.storePath});
  int writes = 0;
  int? failAt;

  @override
  Future<void> write(final LiveApplyJournal journal) async {
    if (++writes == failAt) throw const FileSystemException('journal fault');
    await super.write(journal);
  }
}

void main() {
  late Directory tmp;
  late MemoryStorageProvider inner;
  late _FailingStore store;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('live_apply_checkpoint_');
    inner = MemoryStorageProvider()..files['a'] = 'original';
    store = _FailingStore(storePath: '${tmp.path}/journal');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  for (final checkpoint in [3, 4]) {
    test('journal fault at forward checkpoint $checkpoint recovers', () async {
      final tx = await LiveApplyTransaction.begin(inner, store);
      store.failAt =
          checkpoint; // intent before effect, completion after effect
      await expectLater(
        tx.writeFile('a', 'candidate'),
        throwsA(isA<FileSystemException>()),
      );
      expect(inner.files['a'], checkpoint == 3 ? 'original' : 'candidate');
      final recovered = await LiveApplyTransaction.reopen(
        inner,
        store,
        tx.runId,
      );
      await recovered.rollback();
      expect(inner.files['a'], 'original');
    });
  }

  test(
    'failed inverse completion checkpoint resumes restored content',
    () async {
      final tx = await LiveApplyTransaction.begin(inner, store);
      await tx.writeFile('a', 'candidate');
      store.failAt = store.writes + 3; // rollingBack, inverseStarted, restored
      await expectLater(tx.rollback(), throwsA(isA<FileSystemException>()));
      expect(inner.files['a'], 'original');
      await (await LiveApplyTransaction.reopen(
        inner,
        store,
        tx.runId,
      )).rollback();
      expect(inner.files['a'], 'original');
    },
  );

  test('settlement refuses drift and preserves the recovery journal', () async {
    final tx = await LiveApplyTransaction.begin(inner, store);
    await tx.writeFile('a', 'candidate');
    inner.files['a'] = 'external';
    await expectLater(
      tx.markApplied(),
      throwsA(isA<LiveApplyDriftException>()),
    );
    await expectLater(tx.commit(), throwsA(isA<LiveApplyDriftException>()));
    expect((await store.read(tx.runId))!.status, LiveApplyRunStatus.open);
    expect(inner.files['a'], 'external');
  });

  test(
    'unknown journal versions and statuses refuse without deletion',
    () async {
      final tx = await LiveApplyTransaction.begin(inner, store);
      final file = File('${store.runDirectory(tx.runId).path}/journal.json');
      final map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      file.writeAsStringSync(jsonEncode({...map, 'schema_version': 999}));
      await expectLater(
        LiveApplyTransaction.reopen(inner, store, tx.runId),
        throwsA(isA<LiveApplyRefusalException>()),
      );
      file.writeAsStringSync(jsonEncode({...map, 'status': 'unknown'}));
      await expectLater(
        LiveApplyTransaction.reopen(inner, store, tx.runId),
        throwsA(isA<LiveApplyRefusalException>()),
      );
      expect(file.existsSync(), isTrue);
    },
  );

  test(
    'failed create preserves provider exception and previous undo',
    () async {
      final live = LiveApplyStorageProvider(
        inner: inner,
        journalStorePath: store.storePath,
      );
      await live.updateFile('a', 'candidate');
      final priorId = live.lastRunId;
      await expectLater(live.createFile('a', 'overwrite'), throwsException);
      expect(live.lastRunId, priorId);
      expect(await live.listRuns(), hasLength(1));
      await live.rollbackLast();
      expect(inner.files['a'], 'original');
    },
  );
}
