import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_live_apply/universal_storage_live_apply.dart';

class InterruptedNative extends FileSystemStorageProvider {
  bool interrupt = false;
  int restores = 0;
  @override
  Future<FileOperationResult> restoreFileState(
    String path,
    StorageFileState state,
  ) async {
    final result = await super.restoreFileState(path, state);
    restores++;
    if (interrupt) {
      interrupt = false;
      throw StateError('native atomic inverse before checkpoint');
    }
    return result;
  }
}

void main() {
  late Directory tmp;
  late Directory workspace;
  late InterruptedNative inner;
  late LiveApplyJournalStore store;
  late FileSystemConfig config;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('native_file_state_');
    workspace = await Directory('${tmp.path}/workspace').create();
    config = FileSystemConfig(
      filePathConfig: FilePathConfig({'path': workspace.path}),
    );
    inner = InterruptedNative();
    await inner.initWithConfig(config);
    store = LiveApplyJournalStore(storePath: '${tmp.path}/journal');
  });
  tearDown(() => tmp.deleteSync(recursive: true));
  Future<void> mode(String path, String value) async {
    final child = await Process.run('/bin/chmod', [
      value,
      '${workspace.path}/$path',
    ]);
    expect(child.exitCode, 0, reason: '${child.stderr}');
  }

  Future<void> seed(String path, String value) async {
    await inner.createFile(path, 'private original');
    await mode(path, value);
  }

  for (final entry in {'0600': 0x180, '0644': 0x1a4, '0755': 0x1ed}.entries) {
    test(
      'native deletion and fresh-owner Undo restores ${entry.key}',
      () async {
        await seed('a', entry.key);
        final tx = await LiveApplyTransaction.begin(inner, store);
        await tx.deleteFile('a');
        await tx.markApplied();
        final fresh = FileSystemStorageProvider();
        await fresh.initWithConfig(config);
        await (await LiveApplyTransaction.reopen(
          fresh,
          store,
          tx.runId,
        )).rollback();
        final restored = await fresh.readFileState('a');
        expect(restored.content, 'private original');
        expect(restored.mode, entry.value);
      },
      skip: !(Platform.isMacOS || Platform.isLinux),
    );

    test('native update and Undo preserves ${entry.key}', () async {
      await seed('a', entry.key);
      final tx = await LiveApplyTransaction.begin(inner, store);
      await tx.writeFile('a', 'new bytes');
      expect((await inner.readFileState('a')).mode, entry.value);
      await tx.markApplied();
      await tx.rollback();
      expect((await inner.readFileState('a')).content, 'private original');
      expect((await inner.readFileState('a')).mode, entry.value);
    }, skip: !(Platform.isMacOS || Platform.isLinux));
  }

  test(
    'native mode-only drift blocks all inverse effects and finalization',
    () async {
      await seed('a', '0644');
      await seed('b', '0600');
      final tx = await LiveApplyTransaction.begin(inner, store);
      await tx.writeFile('a', 'new a');
      await tx.writeFile('b', 'new b');
      await tx.markApplied();
      await mode('a', '0600');
      await expectLater(tx.rollback(), throwsA(isA<LiveApplyDriftException>()));
      await expectLater(
        tx.commit(requireApplied: true),
        throwsA(isA<LiveApplyDriftException>()),
      );
      expect(inner.restores, 0);
      expect((await inner.readFileState('a')).content, 'new a');
      expect((await inner.readFileState('a')).mode, 0x180);
      expect((await inner.readFileState('b')).content, 'new b');
    },
    skip: !(Platform.isMacOS || Platform.isLinux),
  );

  test(
    'fresh native owner recognizes compound inverse after interruption',
    () async {
      await seed('a', '0600');
      final tx = await LiveApplyTransaction.begin(inner, store);
      await tx.deleteFile('a');
      inner.interrupt = true;
      await expectLater(tx.rollback(), throwsStateError);
      expect((await store.read(tx.runId))!.entries.single.restored, isFalse);
      final fresh = InterruptedNative();
      await fresh.initWithConfig(config);
      final resumed = await LiveApplyTransaction.reopen(fresh, store, tx.runId);
      await resumed.rollback();
      expect(fresh.restores, 0);
      expect((await fresh.readFileState('a')).mode, 0x180);
      expect(resumed.status, LiveApplyRunStatus.rolledBack);
    },
    skip: !(Platform.isMacOS || Platform.isLinux),
  );
}
