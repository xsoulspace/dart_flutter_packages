import 'dart:io';
import 'package:test/test.dart';
import 'package:universal_storage_git_offline/universal_storage_git_offline.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

void main() {
  test('two providers - does B init break it', () async {
    final remoteDir = await Directory.systemTemp.createTemp('sync2_remote_');
    await Process.run('git', ['init', '--bare', remoteDir.path]);
    final seedDir = await Directory.systemTemp.createTemp('sync2_seed_');
    await Process.run('git', ['init', seedDir.path]);
    await Process.run('git', ['-C', seedDir.path, 'config', 'user.email', 'seed@test.local']);
    await Process.run('git', ['-C', seedDir.path, 'config', 'user.name', 'Seed']);
    await Process.run('git', ['-C', seedDir.path, 'commit', '--allow-empty', '-m', 'seed']);
    await Process.run('git', ['-C', seedDir.path, 'branch', '-M', 'main']);
    await Process.run('git', ['-C', seedDir.path, 'push', remoteDir.path, 'main']);
    await seedDir.delete(recursive: true);

    final dirA = await Directory.systemTemp.createTemp('sync2_a_');
    final dirB = await Directory.systemTemp.createTemp('sync2_b_');
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
    print('A1 sync start');
    Object? e1;
    try { await deviceA.sync(); } catch (e) { e1 = e; }
    // ignore: avoid_print
    print('A1 sync err=$e1');

    final deviceB = OfflineGitStorageProvider(
      commitBatching: const GitCommitBatching(),
    );
    await deviceB.initWithConfig(
      OfflineGitConfig(
        localPath: dirB.path,
        authorName: 'Device B',
        authorEmail: 'b@test.local',
        remoteUrl: VcUrl(remoteDir.path),
      ),
    );
    // ignore: avoid_print
    print('B init done');
    Object? e2;
    try { await deviceB.sync(); } catch (e) { e2 = e; }
    // ignore: avoid_print
    print('B1 sync err=$e2');
    await dirA.delete(recursive: true);
    await dirB.delete(recursive: true);
    if (remoteDir.existsSync()) await remoteDir.delete(recursive: true);
  });
}
