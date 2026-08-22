import 'dart:io';
import 'package:test/test.dart';

void main() {
  test('seed push then ls-remote via origin name', () async {
    final remoteDir = await Directory.systemTemp.createTemp('sync2_remote_');
    await Process.run('git', ['init', '--bare', remoteDir.path]);
    final seedDir = await Directory.systemTemp.createTemp('sync2_seed_');
    await Process.run('git', ['init', seedDir.path]);
    await Process.run('git', ['-C', seedDir.path, 'config', 'user.email', 's@t']);
    await Process.run('git', ['-C', seedDir.path, 'config', 'user.name', 'S']);
    await Process.run('git', ['-C', seedDir.path, 'commit', '--allow-empty', '-m', 'seed']);
    await Process.run('git', ['-C', seedDir.path, 'branch', '-M', 'main']);
    final push = await Process.run('git', ['-C', seedDir.path, 'push', remoteDir.path, 'main']);
    // ignore: avoid_print
    print('PUSH exit=${push.exitCode}');
    // Now check the remote still has HEAD:
    // ignore: avoid_print
    print('HEAD exists=${File('${remoteDir.path}/HEAD').existsSync()}');
    final entries = remoteDir.listSync().map((e) => e.path.split('/').last).toList();
    // ignore: avoid_print
    print('ENTRIES=$entries');
    await seedDir.delete(recursive: true);
    if (remoteDir.existsSync()) await remoteDir.delete(recursive: true);
  });
}
