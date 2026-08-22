import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_git_offline/universal_storage_git_offline.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

void main() {
  Future<Directory> tempDir(final String prefix) =>
      Directory.systemTemp.createTemp(prefix);

  Future<String> gitLog(final Directory dir) async {
    final result = await Process.run('git', [
      '-C',
      dir.path,
      'log',
      '--pretty=format:%s',
    ]);
    return result.stdout.toString();
  }

  Future<OfflineGitStorageProvider> providerFor(
    final Directory dir, {
    final GitCommitBatching? batching,
  }) async {
    final provider = OfflineGitStorageProvider(commitBatching: batching);
    await provider.initWithConfig(
      OfflineGitConfig(
        localPath: dir.path,
        authorName: 'Batch Test',
        authorEmail: 'batch@test.local',
      ),
    );
    return provider;
  }

  group('GitCommitBatching', () {
    test('disabled (null) commits synchronously per write', () async {
      final dir = await tempDir('batch_off_');
      final provider = await providerFor(dir);
      try {
        final result = await provider.createFile('a.txt', 'one');
        // Legacy path returns a real commit hash.
        expect(result.revisionId, isNot(contains('pending')));
        expect(result.revisionId, isNot(contains('batched')));
      } finally {
        await provider.dispose();
        if (dir.existsSync()) await dir.delete(recursive: true);
      }
    });

    test('enabled: mutations coalesce into one batched commit', () async {
      final dir = await tempDir('batch_on_');
      final provider = await providerFor(
        dir,
        batching: const GitCommitBatching(),
      );
      try {
        for (var i = 0; i < 10; i++) {
          await provider.createFile('b/file-$i.txt', 'content-$i');
        }

        // All content readable immediately (write-through).
        expect(await provider.getFile('b/file-3.txt'), 'content-3');

        // Flush and verify a single commit captured everything.
        await provider.flushPendingCommits();
        final log = await gitLog(dir);
        final batchLines = log
            .split('\n')
            .where((final line) => line.startsWith('Batch update:'))
            .toList();
        expect(batchLines, hasLength(1));
        expect(batchLines.single, contains('10 file(s)'));
      } finally {
        await provider.dispose();
        if (dir.existsSync()) await dir.delete(recursive: true);
      }
    });

    test('maxPendingOperations triggers early flush', () async {
      final dir = await tempDir('batch_max_');
      final provider = await providerFor(
        dir,
        batching: const GitCommitBatching(maxPendingOperations: 5),
      );
      try {
        for (var i = 0; i < 12; i++) {
          await provider.createFile('c/file-$i.txt', 'x$i');
        }
        await provider.flushPendingCommits();

        // 12 writes with flush every 5 → at least 2 batched commits.
        final log = await gitLog(dir);
        final batchCount = log
            .split('\n')
            .where((final line) => line.startsWith('Batch update:'))
            .length;
        expect(batchCount, greaterThanOrEqualTo(2));
      } finally {
        await provider.dispose();
        if (dir.existsSync()) await dir.delete(recursive: true);
      }
    });

    test('sync flushes pending commits before push', () async {
      final remoteDir = await tempDir('batch_sync_remote_');
      await Process.run('git', ['init', '--bare', remoteDir.path]);
      // Seed main branch so pull has a ref.
      final seedDir = await tempDir('batch_sync_seed_');
      await Process.run('git', ['init', seedDir.path]);
      await Process.run('git', [
        '-C',
        seedDir.path,
        'commit',
        '--allow-empty',
        '-m',
        'seed',
      ]);
      await Process.run('git', ['-C', seedDir.path, 'branch', '-M', 'main']);
      await Process.run('git', [
        '-C',
        seedDir.path,
        'push',
        remoteDir.path,
        'main',
      ]);
      await seedDir.delete(recursive: true);

      final dir = await tempDir('batch_sync_repo_');
      final provider = OfflineGitStorageProvider(
        commitBatching: const GitCommitBatching(),
      );
      await provider.initWithConfig(
        OfflineGitConfig(
          localPath: dir.path,
          authorName: 'Batch Sync',
          authorEmail: 'batch@test.local',
          remoteUrl: VcUrl(remoteDir.path),
        ),
      );
      try {
        for (var i = 0; i < 5; i++) {
          await provider.createFile('sync/file-$i.txt', 's$i');
        }
        // No explicit flush — sync must handle it.
        await provider.sync();

        // Verify remote received the files.
        final lsResult = await Process.run('git', [
          '-C',
          remoteDir.path,
          'ls-tree',
          '-r',
          '--name-only',
          'main',
        ]);
        expect(lsResult.stdout.toString(), contains('sync/file-0.txt'));
        expect(lsResult.stdout.toString(), contains('sync/file-4.txt'));
      } finally {
        await provider.dispose();
        if (dir.existsSync()) await dir.delete(recursive: true);
        if (remoteDir.existsSync()) await remoteDir.delete(recursive: true);
      }
    });

    test('dispose flushes uncommitted batch (no data loss)', () async {
      final dir = await tempDir('batch_disp_');
      final provider = await providerFor(
        dir,
        batching: const GitCommitBatching(),
      );
      for (var i = 0; i < 3; i++) {
        await provider.createFile('d/file-$i.txt', 'd$i');
      }
      await provider.dispose();

      // Reopen and verify all files committed.
      final reopened = await providerFor(dir);
      try {
        expect(await reopened.getFile('d/file-1.txt'), 'd1');
        final log = await gitLog(dir);
        expect(
          log.split('\n').where((final l) => l.startsWith('Batch update:')),
          hasLength(1),
        );
      } finally {
        await reopened.dispose();
        if (dir.existsSync()) await dir.delete(recursive: true);
      }
    });
  });
}
