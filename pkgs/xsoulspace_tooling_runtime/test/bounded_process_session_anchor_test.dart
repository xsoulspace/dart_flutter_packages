@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'abandoned host anchor kills the admitted group',
    () async {
      final directory = Directory.systemTemp.createTempSync('anchor-orphan-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final packageConfig = File(
        '.dart_tool/package_config.json',
      ).absolute.uri;
      final script = File('${directory.path}/driver.dart')
        ..writeAsStringSync('''
import 'dart:io';
import 'package:xsoulspace_tooling_runtime/xsoulspace_tooling_runtime.dart';

Future<void> main() async {
  await runBounded(
    'sh',
    ['-c', r'sleep 120 & echo \$! > sleeper.pid; wait'],
    deadline: const Duration(hours: 1),
  );
}
''');
      final driver = await Process.start(
        Platform.resolvedExecutable,
        ['--packages=$packageConfig', script.path],
        workingDirectory: directory.path,
        environment: Platform.environment,
      );
      final childPidFile = File('${directory.path}/sleeper.pid');
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (!childPidFile.existsSync() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(childPidFile.existsSync(), isTrue);
      final childPid = int.parse(childPidFile.readAsStringSync());
      driver.kill();
      await driver.exitCode.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(
        (await Process.run('kill', ['-0', '$childPid'])).exitCode,
        isNot(0),
        reason: 'supervisor must tear down the group when the host anchor vanishes',
      );
    },
    skip: Platform.isWindows ? 'POSIX session ownership' : null,
  );
}
