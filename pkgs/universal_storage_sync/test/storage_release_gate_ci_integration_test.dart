import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('storage_release_gate_ci.dart', () {
    test('writes passed artifact and exits with code 0', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'storage_release_gate_ci_pass_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final artifactPath = '${tempDir.path}/g6_pass.json';

      final result = await Process.run('dart', <String>[
        'run',
        'tool/storage_release_gate_ci.dart',
        '--output',
        artifactPath,
        '--scenario',
        'pass',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final artifact = jsonDecode(
        await File(artifactPath).readAsString(),
      ) as Map<String, dynamic>;
      expect(artifact['status'], 'passed');
      expect(artifact['passed'], isTrue);
    });

    test('writes failed artifact and exits with code 1 on blocking findings', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'storage_release_gate_ci_fail_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final artifactPath = '${tempDir.path}/g6_fail.json';

      final result = await Process.run('dart', <String>[
        'run',
        'tool/storage_release_gate_ci.dart',
        '--output',
        artifactPath,
        '--scenario',
        'fail',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 1, reason: '${result.stdout}\n${result.stderr}');
      final artifact = jsonDecode(
        await File(artifactPath).readAsString(),
      ) as Map<String, dynamic>;
      expect(artifact['status'], 'failed');
      expect(artifact['passed'], isFalse);
      expect((artifact['blocking_findings'] as List).isNotEmpty, isTrue);
    });
  });
}
