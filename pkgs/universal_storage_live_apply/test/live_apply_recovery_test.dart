import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_live_apply/universal_storage_live_apply.dart';

import 'memory_provider.dart';

/// Fault at the provider-effect boundary, before the transaction can save
/// completion. The file changed even though the Future failed.
class InterruptedProvider extends MemoryStorageProvider {
  bool interruptNextUpdate = false;

  @override
  Future<FileOperationResult> updateFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) async {
    final result = await super.updateFile(path, content);
    if (interruptNextUpdate) {
      interruptNextUpdate = false;
      throw StateError('interrupted after provider effect');
    }
    return result;
  }
}

void main() {
  late Directory tmp;
  late InterruptedProvider inner;
  late LiveApplyJournalStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('live_apply_recovery_');
    inner = InterruptedProvider();
    store = LiveApplyJournalStore(storePath: '${tmp.path}/journal');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('empty content is present, and rollback restores its prior', () async {
    inner.files['a'] = 'original';
    final tx = await LiveApplyTransaction.begin(inner, store);
    await tx.writeFile('a', '');
    await tx.rollback();
    expect(inner.files['a'], 'original');
  });

  test('empty content cannot disappear without a drift refusal', () async {
    inner.files['a'] = 'original';
    final tx = await LiveApplyTransaction.begin(inner, store);
    await tx.writeFile('a', '');
    inner.files.remove('a');
    await expectLater(tx.rollback(), throwsA(isA<LiveApplyDriftException>()));
    expect(inner.files.containsKey('a'), isFalse);
  });

  test('reopen recovers effect before post-state completion', () async {
    inner.files['a'] = 'original';
    final tx = await LiveApplyTransaction.begin(inner, store);
    inner.interruptNextUpdate = true;
    await expectLater(tx.writeFile('a', 'candidate'), throwsStateError);
    expect(inner.files['a'], 'candidate');
    final recovered = await LiveApplyTransaction.reopen(inner, store, tx.runId);
    await recovered.rollback();
    expect(inner.files['a'], 'original');
  });

  test('provider exception after effect retains recoverable journal', () async {
    inner.files['a'] = 'original';
    final live = LiveApplyStorageProvider(
      inner: inner,
      journalStorePath: '${tmp.path}/journal',
    );
    inner.interruptNextUpdate = true;
    await expectLater(live.updateFile('a', 'candidate'), throwsStateError);
    final runs = await live.listRuns();
    expect(runs, hasLength(1));
    await live.rollbackLast(runId: runs.single.runId);
    expect(inner.files['a'], 'original');
  });

  test(
    'interrupted inverse resumes without treating restoration as drift',
    () async {
      inner.files.addAll({'a': 'a0', 'b': 'b0'});
      final tx = await LiveApplyTransaction.begin(inner, store);
      await tx.writeFile('a', 'a1');
      await tx.writeFile('b', 'b1');
      inner.interruptNextUpdate = true;
      await expectLater(tx.rollback(), throwsStateError);
      expect(inner.files['b'], 'b0');
      final recovered = await LiveApplyTransaction.reopen(
        inner,
        store,
        tx.runId,
      );
      await recovered.rollback();
      expect(inner.files, {'a': 'a0', 'b': 'b0'});
    },
  );
}
