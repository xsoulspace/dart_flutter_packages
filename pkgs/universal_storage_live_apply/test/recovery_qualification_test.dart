import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_live_apply/universal_storage_live_apply.dart';

import 'memory_provider.dart';

class _FaultProvider extends MemoryStorageProvider {
  bool ignoreDelete = false;
  bool failUpdate = false;

  @override
  Future<FileOperationResult> deleteFile(
    final String path, {
    final String? commitMessage,
  }) async {
    if (ignoreDelete) return FileOperationResult(path: path);
    return super.deleteFile(path);
  }

  @override
  Future<FileOperationResult> updateFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) {
    if (failUpdate) {
      return Future<FileOperationResult>.error(StateError('before effect'));
    }
    return super.updateFile(path, content);
  }
}

void main() {
  late Directory tmp;
  late _FaultProvider inner;
  late LiveApplyJournalStore store;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('live_apply_qualification_');
    inner = _FaultProvider();
    store = LiveApplyJournalStore(storePath: '${tmp.path}/journal');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('pending pre-state recovers a failure before effect', () async {
    inner.files['a'] = 'original';
    final tx = await LiveApplyTransaction.begin(inner, store);
    inner.failUpdate = true;
    await expectLater(tx.writeFile('a', 'candidate'), throwsStateError);
    inner.failUpdate = false;
    await (await LiveApplyTransaction.reopen(
      inner,
      store,
      tx.runId,
    )).rollback();
    expect(inner.files['a'], 'original');
  });

  test('pending unexplained drift refuses every inverse write', () async {
    inner.files.addAll({'a': 'a0', 'b': 'b0'});
    final tx = await LiveApplyTransaction.begin(inner, store);
    await tx.writeFile('a', 'a1');
    inner.failUpdate = true;
    await expectLater(tx.writeFile('b', 'b1'), throwsStateError);
    inner.files['b'] = 'external';
    await expectLater(tx.rollback(), throwsA(isA<LiveApplyDriftException>()));
    expect(inner.files, {'a': 'a1', 'b': 'external'});
  });

  test('inverse removal verifies absence and can resume', () async {
    final tx = await LiveApplyTransaction.begin(inner, store);
    await tx.writeFile('created', 'value');
    inner.ignoreDelete = true;
    await expectLater(tx.rollback(), throwsA(isA<LiveApplyDriftException>()));
    expect(
      (await store.read(tx.runId))!.status,
      LiveApplyRunStatus.rollingBack,
    );
    inner.ignoreDelete = false;
    await (await LiveApplyTransaction.reopen(
      inner,
      store,
      tx.runId,
    )).rollback();
    expect(inner.files, isEmpty);
  });

  test('stale handles cannot mutate or undo finalized runs', () async {
    final tx = await LiveApplyTransaction.begin(inner, store);
    await tx.writeFile('a', 'value');
    final stale = await LiveApplyTransaction.reopen(inner, store, tx.runId);
    await tx.commit();
    await expectLater(
      stale.writeFile('a', 'lost'),
      throwsA(isA<LiveApplyRefusalException>()),
    );
    await expectLater(
      stale.rollback(),
      throwsA(isA<LiveApplyRefusalException>()),
    );
    expect(inner.files['a'], 'value');
  });

  test('overlapping store instances refuse a second writer', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final first = store.withExclusive(() async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    try {
      final second = LiveApplyJournalStore(storePath: store.storePath);
      await expectLater(
        LiveApplyTransaction.begin(inner, second),
        throwsA(isA<LiveApplyRefusalException>()),
      );
    } finally {
      release.complete();
      await first;
    }
    await (await LiveApplyTransaction.begin(inner, store)).commit();
  });

  test('legacy ambiguous journal is retained and refuses', () async {
    final journal = LiveApplyJournal(
      runId: 'legacy',
      createdUtc: 'old',
      entries: [LiveApplyEntry(path: 'a', postSha256: liveApplyDeletedSha256)],
    );
    final map = journal.toMap()..remove('schema_version');
    final dir = store.runDirectory('legacy')..createSync(recursive: true);
    File('${dir.path}/journal.json').writeAsStringSync(jsonEncode(map));
    inner.files['a'] = '';
    await expectLater(
      LiveApplyTransaction.reopen(inner, store, 'legacy'),
      throwsA(isA<LiveApplyRefusalException>()),
    );
    expect(File('${dir.path}/journal.json').existsSync(), isTrue);
    expect(inner.files['a'], '');
  });

  test('unambiguous legacy journal restores its original', () async {
    final journal = LiveApplyJournal(
      runId: 'legacy',
      createdUtc: 'old',
      entries: [
        LiveApplyEntry(
          path: 'a',
          postSha256: liveApplySha256('new'),
          prior: LiveApplyPrior(sha256: liveApplySha256('old'), content: 'old'),
        ),
      ],
    );
    final map = journal.toMap()..remove('schema_version');
    final dir = store.runDirectory('legacy')..createSync(recursive: true);
    File('${dir.path}/journal.json').writeAsStringSync(jsonEncode(map));
    inner.files['a'] = 'new';
    await (await LiveApplyTransaction.reopen(
      inner,
      store,
      'legacy',
    )).rollback();
    expect(inner.files['a'], 'old');
  });

  test('UTF-8 snapshot limit counts bytes', () async {
    inner.files['a'] = 'éé';
    final tx = await LiveApplyTransaction.begin(
      inner,
      store,
      maxSnapshotFileBytes: 3,
    );
    await expectLater(
      tx.writeFile('a', 'x'),
      throwsA(isA<LiveApplyRefusalException>()),
    );
    expect(inner.files['a'], 'éé');
  });

  for (final mode in ['write', 'inverse', 'lock']) {
    test(
      'actual process termination at $mode boundary',
      () async {
        final fs = FileSystemStorageProvider();
        final data = '${tmp.path}/data';
        await fs.initWithConfig(
          FileSystemConfig(filePathConfig: FilePathConfig({'path': data})),
        );
        await fs.createFile('a', 'original');
        final child = await Process.start(Platform.resolvedExecutable, [
          '--packages=../../.dart_tool/package_config.json',
          'test/support/recovery_worker.dart',
          mode,
          data,
          store.storePath,
        ]);
        final errors = child.stderr.transform(utf8.decoder).join();
        final lines = StreamIterator(
          child.stdout.transform(utf8.decoder).transform(const LineSplitter()),
        );
        try {
          expect(
            await lines.moveNext().timeout(const Duration(seconds: 15)),
            isTrue,
          );
          final runId = lines.current;
          if (mode == 'lock') {
            await expectLater(
              LiveApplyTransaction.begin(fs, store),
              throwsA(isA<LiveApplyRefusalException>()),
            );
          }
          expect(child.kill(ProcessSignal.sigkill), isTrue);
          expect(
            await child.exitCode.timeout(const Duration(seconds: 10)),
            isNot(0),
          );
          if (mode != 'lock') {
            await (await LiveApplyTransaction.reopen(
              fs,
              store,
              runId,
            )).rollback();
            expect(await fs.getFile('a'), 'original');
          } else {
            await (await LiveApplyTransaction.begin(fs, store)).commit();
          }
        } finally {
          child.kill(ProcessSignal.sigkill);
          await child.exitCode;
          await lines.cancel();
          expect(await errors, isEmpty);
          await fs.dispose();
        }
      },
      skip: Platform.isWindows ? 'SIGKILL qualification is POSIX only' : false,
    );
  }
}
