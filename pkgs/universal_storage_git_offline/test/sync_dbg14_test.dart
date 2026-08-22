import 'dart:io';
import 'package:test/test.dart';

void main() {
  test('does git init --bare fail silently in test env', () async {
    final remoteDir = await Directory.systemTemp.createTemp('sync2_remote_');
    final init = await Process.run('git', ['init', '--bare', remoteDir.path]);
    // ignore: avoid_print
    print('INIT exit=${init.exitCode} stdout=${init.stdout}');
    // Check what's actually inside:
    final entries = remoteDir.listSync().map((e) => e.path.split('/').last).toList();
    // ignore: avoid_print
    print('ENTRIES=$entries');
    // Try ls-remote directly on it:
    final lr = await Process.run('git', ['ls-remote', '--heads', remoteDir.path]);
    // ignore: avoid_print
    print('LSREMOTE exit=${lr.exitCode} err=${lr.stderr}');
    await remoteDir.delete(recursive: true);
  });
}
