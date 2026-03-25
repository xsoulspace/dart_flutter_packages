import 'dart:io';

import 'package:test/test.dart';

void main() {
  final packageRoot = Directory.current.path;
  final rawPath = '$packageRoot/lib/src/raw/ysdk_raw.g.dart';

  test('generated raw contains key symbols', () {
    final content = File(rawPath).readAsStringSync();
    expect(content, contains('external YaGamesGlobalRaw get yaGames;'));
    expect(content, contains('extension type SDKRaw'));
    expect(content, contains('extension type MultiplayerRaw'));
    expect(content, contains('extension type YLeaderboardsRaw'));
    expect(content, contains('extension type PaymentsRaw'));
  });

  test(
    'generator is deterministic across runs',
    () async {
      final before = File(rawPath).readAsStringSync();

      final run1 = await Process.run('dart', <String>[
        'run',
        'tool/generate.dart',
      ], workingDirectory: packageRoot);
      expect(run1.exitCode, 0, reason: '${run1.stdout}\n${run1.stderr}');

      final run2 = await Process.run('dart', <String>[
        'run',
        'tool/generate.dart',
      ], workingDirectory: packageRoot);
      expect(run2.exitCode, 0, reason: '${run2.stdout}\n${run2.stderr}');

      final after = File(rawPath).readAsStringSync();
      expect(after, equals(before));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'check mode fails on stale generated file and passes after restore',
    () async {
      final file = File(rawPath);
      final original = file.readAsStringSync();

      file.writeAsStringSync('$original\n// stale marker\n');

      final staleCheck = await Process.run('dart', <String>[
        'run',
        'tool/generate.dart',
        '--check',
      ], workingDirectory: packageRoot);

      expect(staleCheck.exitCode, isNot(0));

      file.writeAsStringSync(original);

      final cleanCheck = await Process.run('dart', <String>[
        'run',
        'tool/generate.dart',
        '--check',
      ], workingDirectory: packageRoot);

      expect(
        cleanCheck.exitCode,
        0,
        reason: '${cleanCheck.stdout}\n${cleanCheck.stderr}',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
