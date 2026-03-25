import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('clone guard audit passes for current workspace usage', () async {
    final result = await Process.run('bash', <String>[
      '../../tool/universal_storage_clone_guard_audit.sh',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}
