import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_live_apply/universal_storage_live_apply.dart';

import 'memory_provider.dart';

class StateProvider extends MemoryStorageProvider
    implements StorageFileStatePort {
  final modes = <String, int>{};
  String? profile = storagePosixRwxProfile;
  int restorations = 0;
  bool interruptAfterInverse = false;
  bool failBeforeInverse = false;

  @override
  String? get fileStateProfile => profile;

  @override
  Future<StorageFileState> readFileState(String path) async =>
      StorageFileState(content: files[path], mode: modes[path]);

  @override
  StorageFileState intendedFileState(
    StorageFileState before,
    String? content,
  ) => StorageFileState(
    content: content,
    mode: content == null ? null : before.mode ?? 0x1a4,
  );

  @override
  Future<FileOperationResult> createFile(
    String path,
    String content, {
    String? commitMessage,
  }) async {
    final result = await super.createFile(path, content);
    modes[path] = 0x1a4;
    return result;
  }

  @override
  Future<FileOperationResult> deleteFile(
    String path, {
    String? commitMessage,
  }) async {
    final result = await super.deleteFile(path);
    modes.remove(path);
    return result;
  }

  @override
  Future<FileOperationResult> restoreFileState(
    String path,
    StorageFileState state,
  ) async {
    state.validatePosix();
    if (failBeforeInverse) throw StateError('metadata publication failed');
    restorations++;
    if (state.content == null) {
      files.remove(path);
      modes.remove(path);
    } else {
      files[path] = state.content!;
      modes[path] = state.mode!;
    }
    if (interruptAfterInverse) {
      interruptAfterInverse = false;
      throw StateError('inverse publication before checkpoint');
    }
    return FileOperationResult(path: path);
  }
}

void main() {
  late Directory tmp;
  late StateProvider inner;
  late LiveApplyJournalStore store;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('file_state_recovery_');
    inner = StateProvider();
    store = LiveApplyJournalStore(storePath: '${tmp.path}/journal');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  void seed(String path, String content, int mode) {
    inner.files[path] = content;
    inner.modes[path] = mode;
  }

  test(
    'metadata-aware reopen refuses missing legacy modes without guessing',
    () async {
      final legacy = LiveApplyJournal(
        runId: 'legacy',
        createdUtc: '2026-10-13T00:00:00Z',
      );
      await store.write(legacy);
      final file = File('${store.runDirectory('legacy').path}/journal.json');
      final before = await file.readAsString();
      await expectLater(
        LiveApplyTransaction.reopen(inner, store, 'legacy'),
        throwsA(isA<LiveApplyRefusalException>()),
      );
      expect(await file.readAsString(), before);
      expect(inner.restorations, 0);
      // A genuinely content-only provider retains its unchanged legacy route.
      expect(
        await LiveApplyTransaction.reopen(
          MemoryStorageProvider(),
          store,
          'legacy',
        ),
        isNotNull,
      );
    },
  );

  test(
    'mode drift before dispatch refuses without calling the effect',
    () async {
      seed('a', 'old', 0x180);
      final tx = await LiveApplyTransaction.begin(inner, store);
      await tx.snapshot('a');
      inner.modes['a'] = 0x1a4;
      var effects = 0;
      await expectLater(
        tx.mutate('a', 'new', () {
          effects++;
          return Future.value(const FileOperationResult(path: 'a'));
        }),
        throwsA(isA<LiveApplyDriftException>()),
      );
      expect(effects, 0);
      expect(inner.files['a'], 'old');
      expect(inner.modes['a'], 0x1a4);
    },
  );

  test(
    'unrealized forward mode remains pending and cannot hide drift',
    () async {
      seed('a', 'old', 0x180);
      final tx = await LiveApplyTransaction.begin(inner, store);
      await expectLater(
        tx.mutate('a', 'new', () {
          seed('a', 'new', 0x1a4);
          return Future.value(const FileOperationResult(path: 'a'));
        }),
        throwsA(isA<LiveApplyDriftException>()),
      );
      expect((await store.read(tx.runId))!.entries.single.pending, isTrue);
      final reopened = await LiveApplyTransaction.reopen(
        inner,
        store,
        tx.runId,
      );
      await expectLater(
        reopened.rollback(),
        throwsA(isA<LiveApplyDriftException>()),
      );
      expect(inner.restorations, 0);
      expect(inner.files['a'], 'new');
      expect(inner.modes['a'], 0x1a4);
    },
  );

  test(
    'v3 records exact mode before forward dispatch and restores deletion',
    () async {
      seed('private', 'private bytes', 0x180);
      final tx = await LiveApplyTransaction.begin(inner, store);
      await tx.deleteFile('private');
      await tx.markApplied();
      final recorded = (await store.read(tx.runId))!;
      expect(recorded.toMap()['schema_version'], 3);
      expect(recorded.fileStateProfile, storagePosixRwxProfile);
      expect(recorded.entries.single.prior!.mode, 0x180);
      expect(recorded.entries.single.postMode, isNull);
      final reopened = await LiveApplyTransaction.reopen(
        inner,
        store,
        tx.runId,
      );
      await reopened.rollback();
      expect(inner.files['private'], 'private bytes');
      expect(inner.modes['private'], 0x180);
    },
  );

  test(
    'mixed modes update and created-file inverse preserve compound state',
    () async {
      for (final entry in {
        'private': 0x180,
        'source': 0x1a4,
        'executable': 0x1ed,
      }.entries) {
        seed(entry.key, 'before', entry.value);
      }
      final tx = await LiveApplyTransaction.begin(inner, store);
      for (final path in inner.files.keys.toList()) {
        await tx.writeFile(path, 'after');
      }
      await tx.writeFile('new', 'new');
      await tx.markApplied();
      await tx.rollback();
      expect(inner.files, {
        'private': 'before',
        'source': 'before',
        'executable': 'before',
      });
      expect(inner.modes, {
        'private': 0x180,
        'source': 0x1a4,
        'executable': 0x1ed,
      });
    },
  );

  test(
    'mode-only drift refuses whole footprint before inverse and finalization',
    () async {
      seed('a', 'old a', 0x1a4);
      seed('b', 'old b', 0x180);
      final tx = await LiveApplyTransaction.begin(inner, store);
      await tx.writeFile('a', 'new a');
      await tx.writeFile('b', 'new b');
      await tx.markApplied();
      inner.modes['a'] = 0x180;
      await expectLater(tx.rollback(), throwsA(isA<LiveApplyDriftException>()));
      await expectLater(
        tx.commit(requireApplied: true),
        throwsA(isA<LiveApplyDriftException>()),
      );
      expect(inner.restorations, 0);
      expect(inner.files, {'a': 'new a', 'b': 'new b'});
      expect((await store.read(tx.runId))!.status, LiveApplyRunStatus.applied);
    },
  );

  test(
    'snapshot-only mode drift cannot discard retained recovery evidence',
    () async {
      seed('a', 'old', 0x180);
      final tx = await LiveApplyTransaction.begin(inner, store);
      await tx.snapshot('a');
      inner.modes['a'] = 0x1a4;
      expect(await tx.discardIfUnchanged(), isFalse);
      expect(await store.read(tx.runId), isNotNull);
    },
  );

  test(
    'complete atomic inverse after interruption is recognized without replay',
    () async {
      seed('a', 'private', 0x180);
      final tx = await LiveApplyTransaction.begin(inner, store);
      await tx.deleteFile('a');
      await tx.markApplied();
      inner.interruptAfterInverse = true;
      await expectLater(tx.rollback(), throwsStateError);
      expect(inner.files['a'], 'private');
      expect(inner.modes['a'], 0x180);
      final reopened = await LiveApplyTransaction.reopen(
        inner,
        store,
        tx.runId,
      );
      await reopened.rollback();
      expect(inner.restorations, 1);
      expect(reopened.status, LiveApplyRunStatus.rolledBack);
    },
  );

  test(
    'partial inverse with recorded bytes but unexplained mode refuses',
    () async {
      seed('a', 'private', 0x180);
      final tx = await LiveApplyTransaction.begin(inner, store);
      await tx.deleteFile('a');
      inner.failBeforeInverse = true;
      await expectLater(tx.rollback(), throwsStateError);
      seed('a', 'private', 0x1a4);
      inner.failBeforeInverse = false;
      final reopened = await LiveApplyTransaction.reopen(
        inner,
        store,
        tx.runId,
      );
      await expectLater(
        reopened.rollback(),
        throwsA(isA<LiveApplyDriftException>()),
      );
      expect(inner.restorations, 0);
      expect(inner.modes['a'], 0x1a4);
      expect((await store.read(tx.runId))!.entries.single.restored, isFalse);
    },
  );

  test('pending forward recognizes only recorded content and mode', () async {
    seed('a', 'old', 0x180);
    final tx = await LiveApplyTransaction.begin(inner, store);
    await expectLater(
      tx.mutate('a', 'new', () {
        inner.files['a'] = 'new';
        return Future<FileOperationResult>.error(
          StateError('after forward effect'),
        );
      }),
      throwsStateError,
    );
    final reopened = await LiveApplyTransaction.reopen(inner, store, tx.runId);
    await reopened.rollback();
    expect(inner.files['a'], 'old');
    expect(inner.modes['a'], 0x180);
  });

  test(
    'missing or mismatched adapter refuses reopen with journal unchanged',
    () async {
      seed('a', 'old', 0x180);
      final tx = await LiveApplyTransaction.begin(inner, store);
      await tx.writeFile('a', 'new');
      final file = File('${store.runDirectory(tx.runId).path}/journal.json');
      final before = await file.readAsString();
      await expectLater(
        LiveApplyTransaction.reopen(MemoryStorageProvider(), store, tx.runId),
        throwsA(isA<LiveApplyRefusalException>()),
      );
      inner.profile = 'incompatible';
      await expectLater(
        LiveApplyTransaction.reopen(inner, store, tx.runId),
        throwsA(isA<LiveApplyRefusalException>()),
      );
      expect(await file.readAsString(), before);
      expect(inner.files['a'], 'new');
      expect(inner.restorations, 0);
    },
  );
}
