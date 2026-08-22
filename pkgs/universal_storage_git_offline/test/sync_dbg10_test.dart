import 'dart:io';
import 'package:test/test.dart';
import 'package:universal_storage_git_offline/universal_storage_git_offline.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

void main() {
  test('exact two-repo test flow', () async {
    final remoteDir = await Directory.systemTemp.createTemp('sync2_remote_');
    final dirA = await Directory.systemTemp.createTemp('sync2_a_');
    final dirB = await Directory.systemTemp.createTemp('sync2_b_');
    final seedDir = await Directory.systemTemp.createTemp('sync2_seed_');
    await Process.run('git', ['init', seedDir.path]);
    await Process.run('git', ['-C', seedDir.path, 'config', 'user.email', 'seed@test.local']);
    await Process.run('git', ['-C', seedDir.path, 'config', 'user.name', 'Seed']);
    await Process.run('git', ['-C', seedDir.path, 'commit', '--allow-empty', '-m', 'seed']);
    await Process.run('git', ['-C', seedDir.path, 'branch', '-M', 'main']);
    final push = await Process.run('git', ['-C', seedDir.path, 'push', remoteDir.path, 'main']);
    // ignore: avoid_print
    print('PUSH exit=${push.exitCode} err=${push.stderr}');
    await seedDir.delete(recursive: true);

    final deviceA = OfflineGitStorageProvider(
      commitBatching: const GitCommitBatching(),
    );
    await deviceA.initWithConfig(
      OfflineGitConfig(
        localPath: dirA.path,
        authorName: 'Device A',
        authorEmail: 'a@test.local',
        remoteUrl: VcUrl(remoteDir.path),
      ),
    );
    // ignore: avoid_print
    print('REMOTE before A createFile: exists=${remoteDir.existsSync()}');
    await deviceA.createFile('docs/from-a.json', '{"author":"a"}');
    // ignore: avoid_print
    print('REMOTE after A createFile: exists=${remoteDir.existsSync()}');
    Object? error;
    try {
      await deviceA.sync();
    } catch (e) {
      error = e;
    }
    // ignore: avoid_print
    print('A SYNC ERR=$error REMOTE exists=${remoteDir.existsSync()}');
    await dirA.delete(recursive: true);
    await dirB.delete(recursive: true);
    if (remoteDir.existsSync()) await remoteDir.delete(recursive: true);
  });
}
