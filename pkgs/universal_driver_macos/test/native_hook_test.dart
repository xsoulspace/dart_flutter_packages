import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

// Opt-in real Swift/native-assets test. The fixture owns all mutable inputs;
// it never edits the repository's bridge or launches/activates an application.
void main() {
  test(
    'native hook builds, reuses outputs, and rebuilds changed Swift input',
    () async {
      final package = Directory.current.absolute;
      final fixture = await Directory.systemTemp.createTemp('macos-hook-');
      addTearDown(() => fixture.delete(recursive: true));
      final driver = Directory('${fixture.path}/driver')..createSync();
      for (final name in ['lib', 'hook', 'bridge']) {
        final source = Directory('${package.path}/$name');
        for (final entry in source.listSync(recursive: true)) {
          final relative = entry.path.substring(source.path.length);
          final target = '${driver.path}/$name$relative';
          if (entry is Directory) {
            Directory(target).createSync(recursive: true);
          } else if (entry is File) {
            File(target).parent.createSync(recursive: true);
            entry.copySync(target);
          }
        }
      }
      final pubspec = File('${package.path}/pubspec.yaml')
          .readAsStringSync()
          .split('dev_dependencies:')
          .first
          .replaceAll('resolution: workspace\n', '');
      File('${driver.path}/pubspec.yaml').writeAsStringSync(pubspec);
      final consumer = Directory('${fixture.path}/consumer')..createSync();
      final interface = Directory(
        '${package.parent.path}/universal_automation_interface',
      );
      File('${consumer.path}/pubspec.yaml').writeAsStringSync('''
name: native_hook_fixture
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  universal_driver_macos:
    path: ${driver.path}
dependency_overrides:
  universal_automation_interface:
    path: ${interface.path}
''');
    File('${consumer.path}/main.dart').writeAsStringSync(r'''
import 'package:universal_driver_macos/universal_driver_macos.dart';
Future<void> main() async {
  final driver = MacosDriver();
  try {
    print('native-pid:${(await driver.frontmost()).pid}');
  } finally {
    await driver.close();
  }
}
''');
      Future<ProcessResult> run(List<String> args) async {
        final result = await Process.run(
          Platform.resolvedExecutable,
          args,
          workingDirectory: consumer.path,
        );
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(
          '${result.stdout}${result.stderr}',
          isNot(contains('File modified during build')),
        );
        return result;
      }

      await run(['pub', 'get']);
      Future<(DateTime, List<int>)> observeBuild() async {
        final result = await run(['run', 'main.dart']);
        expect(result.stdout, contains('native-pid:'));
        final hookRoot = Directory(
          '${consumer.path}/.dart_tool/hooks_runner/universal_driver_macos',
        );
        final output = hookRoot
            .listSync(recursive: true)
            .whereType<File>()
            .singleWhere((file) => file.path.endsWith('/output.json'));
        final json = jsonDecode(output.readAsStringSync()) as Map;
        expect(json['dependencies'], [
          '${driver.path}/bridge/src/driver_bridge.swift',
        ]);
        final encoding =
            ((json['assets'] as List).single as Map)['encoding'] as Map;
        final library = File(encoding['file'] as String);
        expect(library.path, isNot(contains('//libxs_ax_driver')));
        return (library.lastModifiedSync(), library.readAsBytesSync());
      }

      final first = await observeBuild();
      final warm = await observeBuild();
      expect(
        warm.$1,
        first.$1,
        reason: 'unchanged inputs must reuse the dylib',
      );
      expect(warm.$2, first.$2);
      File('${driver.path}/bridge/src/driver_bridge.swift').writeAsStringSync(
        '\n// Owned cache invalidation fixture.\n',
        mode: FileMode.append,
      );
      final changed = await observeBuild();
      expect(
        changed.$1.isAfter(warm.$1),
        isTrue,
        reason: 'a changed Swift source must rebuild the native output',
      );
    },
    skip:
        !Platform.isMacOS || Platform.environment['XS_TEST_NATIVE_HOOK'] != '1'
        ? 'Set XS_TEST_NATIVE_HOOK=1 on macOS for real Swift build/cache proof'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
