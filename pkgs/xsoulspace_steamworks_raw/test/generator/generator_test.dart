import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final packageRoot = Directory.current.path;
  final fixtureSdkPath = p.join(packageRoot, 'test', 'fixtures', 'fake_sdk');
  final mockFfigenOutputPath = p.join(
    packageRoot,
    'test',
    'fixtures',
    'mock_ffigen_output.dart',
  );

  Future<ProcessResult> runGenerator(
    final String workingPackageRoot, {
    final bool check = false,
  }) {
    final args = <String>[
      'run',
      'tool/generate.dart',
      '--package-root',
      workingPackageRoot,
      '--sdk-path',
      fixtureSdkPath,
      '--mock-ffigen-output',
      mockFfigenOutputPath,
    ];
    if (check) {
      args.add('--check');
    }

    return Process.run('dart', args, workingDirectory: packageRoot);
  }

  Future<String> createTempPackageCopy() async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'steamworks_raw_pkg_',
    );
    final copyRoot = p.join(tempRoot.path, 'xsoulspace_steamworks_raw');
    await _copyDirectory(Directory(packageRoot), Directory(copyRoot));
    return copyRoot;
  }

  test('generator is deterministic for the same SDK input', () async {
    final tempPackageRoot = await createTempPackageCopy();
    addTearDown(
      () => Directory(p.dirname(tempPackageRoot)).deleteSync(recursive: true),
    );

    final first = await runGenerator(tempPackageRoot);
    expect(first.exitCode, 0, reason: '${first.stdout}\n${first.stderr}');

    final firstContent = File(
      p.join(
        tempPackageRoot,
        'lib',
        'src',
        'generated',
        'steam_api_flat_bindings.g.dart',
      ),
    ).readAsStringSync();

    final second = await runGenerator(tempPackageRoot);
    expect(second.exitCode, 0, reason: '${second.stdout}\n${second.stderr}');

    final secondContent = File(
      p.join(
        tempPackageRoot,
        'lib',
        'src',
        'generated',
        'steam_api_flat_bindings.g.dart',
      ),
    ).readAsStringSync();

    expect(secondContent, equals(firstContent));
  });

  test('generator fails on upstream lock mismatch', () async {
    final tempPackageRoot = await createTempPackageCopy();
    addTearDown(
      () => Directory(p.dirname(tempPackageRoot)).deleteSync(recursive: true),
    );

    final lockFile = File(
      p.join(tempPackageRoot, 'tool', 'upstream_lock.json'),
    );
    final lock =
        jsonDecode(lockFile.readAsStringSync()) as Map<String, Object?>;
    lock['sdkVersion'] = 'mismatch';
    lockFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(lock)}\n',
    );

    final result = await runGenerator(tempPackageRoot);
    expect(result.exitCode, isNot(0));
    expect(result.stderr.toString(), contains('lock mismatch'));
  });

  test(
    'check mode fails on stale generated files and passes after regenerate',
    () async {
      final tempPackageRoot = await createTempPackageCopy();
      addTearDown(
        () => Directory(p.dirname(tempPackageRoot)).deleteSync(recursive: true),
      );

      final generate = await runGenerator(tempPackageRoot);
      expect(
        generate.exitCode,
        0,
        reason: '${generate.stdout}\n${generate.stderr}',
      );

      final generatedFile = File(
        p.join(
          tempPackageRoot,
          'lib',
          'src',
          'generated',
          'steam_api_flat_bindings.g.dart',
        ),
      );
      generatedFile.writeAsStringSync(
        '${generatedFile.readAsStringSync()}\n// stale marker\n',
      );

      final staleCheck = await runGenerator(tempPackageRoot, check: true);
      expect(staleCheck.exitCode, isNot(0));

      final regenerate = await runGenerator(tempPackageRoot);
      expect(
        regenerate.exitCode,
        0,
        reason: '${regenerate.stdout}\n${regenerate.stderr}',
      );

      final cleanCheck = await runGenerator(tempPackageRoot, check: true);
      expect(
        cleanCheck.exitCode,
        0,
        reason: '${cleanCheck.stdout}\n${cleanCheck.stderr}',
      );
    },
  );
}

Future<void> _copyDirectory(
  final Directory source,
  final Directory destination,
) async {
  destination.createSync(recursive: true);

  await for (final entity in source.list(followLinks: false)) {
    final basename = p.basename(entity.path);
    if (basename == '.dart_tool' || basename == 'build') {
      continue;
    }

    if (entity is Directory) {
      await _copyDirectory(
        entity,
        Directory(p.join(destination.path, basename)),
      );
      continue;
    }

    if (entity is File) {
      final target = File(p.join(destination.path, basename));
      target.writeAsBytesSync(entity.readAsBytesSync());
    }
  }
}
