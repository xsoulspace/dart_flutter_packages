import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_live_apply/universal_storage_live_apply.dart';

import 'memory_provider.dart';

void main() {
  late Directory tmp;
  late MemoryStorageProvider inner;
  late LiveApplyJournalStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('live_apply_tx_test');
    inner = MemoryStorageProvider();
    store = LiveApplyJournalStore(storePath: '${tmp.path}/journal');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('rollback restores updated and created files byte-exactly', () async {
    await inner.createFile('a.txt', 'original');
    final tx = await LiveApplyTransaction.begin(inner, store);
    await tx.writeFile('a.txt', 'changed');
    await tx.writeFile('new.txt', 'brand new');
    await tx.markApplied();
    expect(inner.files['a.txt'], 'changed');
    expect(inner.files['new.txt'], 'brand new');

    await tx.rollback();
    expect(inner.files['a.txt'], 'original');
    expect(inner.files.containsKey('new.txt'), isFalse);
    final journal = await store.read(tx.runId);
    expect(journal!.status, LiveApplyRunStatus.rolledBack);
  });

  test('rollback restores deleted files', () async {
    await inner.createFile('gone.txt', 'precious');
    final tx = await LiveApplyTransaction.begin(inner, store);
    await tx.deleteFile('gone.txt');
    expect(inner.files.containsKey('gone.txt'), isFalse);
    await tx.rollback();
    expect(inner.files['gone.txt'], 'precious');
  });

  test('commit prunes the journal and freezes the state', () async {
    final tx = await LiveApplyTransaction.begin(inner, store);
    await tx.writeFile('kept.txt', 'stays');
    await tx.commit();
    expect(inner.files['kept.txt'], 'stays');
    expect(await store.read(tx.runId), isNull);
    expect(
      tx.rollback,
      throwsA(isA<LiveApplyRefusalException>()),
    );
  });

  test('rollback refuses on external drift and mutates nothing', () async {
    await inner.createFile('a.txt', 'original');
    final tx = await LiveApplyTransaction.begin(inner, store);
    await tx.writeFile('a.txt', 'changed');
    await tx.markApplied();
    // External edit bypassing the run:
    inner.files['a.txt'] = 'externally edited';

    await expectLater(
      tx.rollback(),
      throwsA(
        isA<LiveApplyDriftException>()
            .having((final e) => e.paths, 'paths', contains('a.txt')),
      ),
    );
    expect(inner.files['a.txt'], 'externally edited');
  });

  test('double rollback is refused', () async {
    await inner.createFile('a.txt', 'v1');
    final tx = await LiveApplyTransaction.begin(inner, store);
    await tx.writeFile('a.txt', 'v2');
    await tx.markApplied();
    await tx.rollback();
    expect(
      tx.rollback,
      throwsA(isA<LiveApplyRefusalException>()),
    );
  });

  test(
      'a prior larger than maxSnapshotFileBytes refuses before any mutation',
      () async {
    await inner.createFile('big.txt', 'x' * 100);
    final tx = await LiveApplyTransaction.begin(inner, store,
        maxSnapshotFileBytes: 10);
    await expectLater(
      tx.writeFile('big.txt', 'smaller'),
      throwsA(isA<LiveApplyRefusalException>()),
    );
    expect(inner.files['big.txt'], 'x' * 100, reason: 'nothing may mutate');
  });

  test(
      'reopen recovers an open run from its journal alone (crash recovery)',
      () async {
    await inner.createFile('a.txt', 'original');
    final tx = await LiveApplyTransaction.begin(inner, store);
    await tx.writeFile('a.txt', 'crashed mid-apply');
    // No commit, no markApplied: a crash left the run `open`.

    final recovered = await LiveApplyTransaction.reopen(inner, store, tx.runId);
    await recovered.rollback();
    expect(inner.files['a.txt'], 'original');
    expect((await store.read(tx.runId))!.status, LiveApplyRunStatus.rolledBack);
  });

  test('deleteFile of a file the run created rolls back to absent', () async {
    final tx = await LiveApplyTransaction.begin(inner, store);
    await tx.writeFile('ephemeral.txt', 'temp');
    await tx.deleteFile('ephemeral.txt');
    await tx.markApplied();
    expect(inner.files.containsKey('ephemeral.txt'), isFalse);
    await tx.rollback();
    expect(inner.files.containsKey('ephemeral.txt'), isFalse,
        reason: 'the inverse of create-then-delete is absent, not recreate');
  });
}
