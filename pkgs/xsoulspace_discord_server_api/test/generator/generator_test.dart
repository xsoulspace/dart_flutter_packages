import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final packageRoot = Directory.current.path;
  final routeIndexPath =
      '$packageRoot/tool/generated/rest_v10_route_index.json';
  final typeIndexPath = '$packageRoot/tool/generated/rest_v10_type_index.json';

  test('generated indexes contain key metadata fields', () {
    final routes =
        jsonDecode(File(routeIndexPath).readAsStringSync())
            as Map<String, Object?>;
    final types =
        jsonDecode(File(typeIndexPath).readAsStringSync())
            as Map<String, Object?>;

    expect(routes['routesCount'], isA<int>());
    expect(types['exportedSymbolCount'], isA<int>());
    expect(types['restFileCount'], isA<int>());
    expect(types['payloadFileCount'], isA<int>());
  });

  test(
    'generator is deterministic across runs',
    () async {
      final beforeRoutes = File(routeIndexPath).readAsStringSync();
      final beforeTypes = File(typeIndexPath).readAsStringSync();

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

      final afterRoutes = File(routeIndexPath).readAsStringSync();
      final afterTypes = File(typeIndexPath).readAsStringSync();
      expect(afterRoutes, equals(beforeRoutes));
      expect(afterTypes, equals(beforeTypes));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'check mode fails on stale generated file and passes after restore',
    () async {
      final file = File(routeIndexPath);
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

  test(
    'check mode fails on lock mismatch',
    () async {
      final lockFile = File('$packageRoot/tool/upstream_lock.json');
      final original = lockFile.readAsStringSync();
      final lock = jsonDecode(original) as Map<String, Object?>;
      lock['typesHash'] = 'mismatch';
      lockFile.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(lock)}\n',
      );

      final check = await Process.run('dart', <String>[
        'run',
        'tool/generate.dart',
        '--check',
      ], workingDirectory: packageRoot);

      expect(check.exitCode, isNot(0));

      lockFile.writeAsStringSync(original);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
