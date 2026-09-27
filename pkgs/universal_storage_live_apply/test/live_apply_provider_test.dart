import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_live_apply/universal_storage_live_apply.dart';

import 'memory_provider.dart';

void main() {
  late Directory tmp;
  late MemoryStorageProvider inner;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('live_apply_provider_test');
    inner = MemoryStorageProvider();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  LiveApplyStorageProvider provider() => LiveApplyStorageProvider(
        inner: inner,
        journalStorePath: '${tmp.path}/journal',
      );

  test('per-operation mutations are rollback-window undoable', () async {
    final live = provider();
    await live.createFile('doc.txt', 'v1');
    await live.updateFile('doc.txt', 'v2');
    expect(inner.files['doc.txt'], 'v2');

    await live.rollbackLast();
    expect(inner.files['doc.txt'], 'v1');
  });

  test('rollbackLast restores a deleted file', () async {
    final live = provider();
    await live.createFile('doc.txt', 'data');
    await live.deleteFile('doc.txt');
    expect(inner.files.containsKey('doc.txt'), isFalse);
    await live.rollbackLast();
    expect(inner.files['doc.txt'], 'data');
  });

  test('commitLast prunes; the applied state sticks', () async {
    final live = provider();
    await live.createFile('doc.txt', 'final');
    await live.commitLast();
    expect(inner.files['doc.txt'], 'final');
    expect(await live.listRuns(), isEmpty);
    await expectLater(
      live.rollbackLast(),
      throwsA(isA<LiveApplyRefusalException>()),
    );
  });

  test('a batch is one transaction with all-or-nothing rollback', () async {
    final live = provider();
    final tx = await live.beginTransaction();
    await tx.writeFile('one.txt', '1');
    await tx.writeFile('two.txt', '2');
    await tx.rollback();
    expect(inner.files, isEmpty, reason: 'neither write survives the inverse');
  });

  test('inner failure leaves no retained run (nothing mutated)', () async {
    final live = provider();
    await expectLater(
      live.updateFile('missing.txt', 'x'),
      throwsA(isA<FileNotFoundException>()),
    );
    expect(await live.listRuns(), isEmpty,
        reason: 'a failed per-op run never left open — it is discarded');
  });

  test('restore with a retained run id rolls that run back', () async {
    final live = provider();
    await live.createFile('doc.txt', 'v1');
    await live.updateFile('doc.txt', 'v2');
    // v0 scope: a run's rollback window covers only ITS post state — an
    // EARLIER run is invalidated by a later write over the same path (the
    // drift check refuses). Restoring therefore targets the latest run.
    final latestRunId = live.lastRunId!;
    expect(inner.files['doc.txt'], 'v2');
    await live.restore('doc.txt', versionId: latestRunId);
    expect(inner.files['doc.txt'], 'v1');
  });

  test('declared capabilities expose journal-backed history', () async {
    final live = provider();
    expect(live.declaredCapabilities.supportsHistory, isTrue);
  });

  test('integration: filesystem provider end to end', () async {
    final fsInner = FileSystemStorageProvider();
    await fsInner.initWithConfig(
      FileSystemConfig(
        filePathConfig: FilePathConfig({'path': '${tmp.path}/store'}),
      ),
    );
    final live = LiveApplyStorageProvider(
      inner: fsInner,
      journalStorePath: '${tmp.path}/journal',
    );
    await live.createFile('notes/first.md', '# v1');
    await live.updateFile('notes/first.md', '# v2');
    final onDisk = File('${tmp.path}/store/notes/first.md');
    expect(await onDisk.readAsString(), '# v2');

    await live.rollbackLast();
    expect(await onDisk.readAsString(), '# v1');
  });
}
