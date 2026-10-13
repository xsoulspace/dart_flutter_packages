import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const _package = 'xsoulspace_inference_apple_foundation';
const _sources = [
  'bridge/src/bridge.swift',
  'bridge/src/DartSchemaMaterializer.swift',
];

Directory _packageRoot() {
  for (final root in [Directory.current, Directory('pkgs/$_package')]) {
    if (File('${root.path}/hook/build.dart').existsSync()) {
      return Directory(root.resolveSymbolicLinksSync());
    }
  }
  throw StateError('Run from the package or repository root.');
}

Directory _workspaceRoot(Directory package) {
  var root = package;
  while (!File('${root.path}/.dart_tool/package_config.json').existsSync()) {
    final parent = root.parent;
    if (parent.path == root.path) {
      throw StateError('Resolved workspace package_config.json is required.');
    }
    root = parent;
  }
  return root;
}

Future<String> _sha(File file) async {
  final result = await Process.run('shasum', ['-a', '256', file.path]);
  expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  return (result.stdout as String).trim().split(' ').first;
}

void main() {
  test(
    'actual hook records package-root dependencies for a different consumer',
    () async {
      final package = _packageRoot();
      final workspace = _workspaceRoot(package);
      final cache = Directory(
        '${workspace.path}/.dart_tool/hooks_runner/$_package',
      );
      final cached = cache
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.uri.pathSegments.last == 'input.json')
          .map((file) => jsonDecode(file.readAsStringSync()) as Map)
          .where((input) {
            final config = input['config'] as Map;
            final extensions = config['extensions'] as Map;
            final code = extensions['code_assets'] as Map;
            return code['target_os'] == 'macos' &&
                code['link_mode_preference'] == 'dynamic';
          });
      expect(cached, isNotEmpty, reason: 'actual macOS hook input is required');
      final original = cached.first;
      final temp = await Directory.systemTemp.createTemp(
        'afm_hook_regression_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final copied = await Directory('${temp.path}/package').create();
      final consumer = await Directory('${temp.path}/consumer').create();
      final sourceHashes = <String, String>{};
      for (final path in _sources) {
        final source = File('${package.path}/$path');
        final target = File('${copied.path}/$path');
        target.parent.createSync(recursive: true);
        target.writeAsBytesSync(source.readAsBytesSync(), flush: true);
        sourceHashes[path] = await _sha(source);
        expect(await _sha(target), sourceHashes[path]);
      }
      expect(Directory('${copied.path}/.dart_tool/lib').existsSync(), isFalse);
      final output = File('${temp.path}/output.json');
      final input = Map<String, Object?>.from(original)
        ..['package_root'] = '${copied.path}/'
        ..['out_file'] = output.path
        ..['out_dir_shared'] = '${temp.path}/shared/';
      // Native compiler configuration is copied unchanged; only addresses of
      // the disposable package/output directories differ from the real input.
      expect(input['config'], original['config']);
      final inputFile = File('${temp.path}/input.json')
        ..writeAsStringSync(jsonEncode(input), flush: true);
      final dart = Platform.environment['AFM_BUILD_HOOK_DART'] ?? 'dart';
      final result = await Process.run(dart, [
        '--packages=${workspace.path}/.dart_tool/package_config.json',
        '${package.path}/hook/build.dart',
        '--config=${inputFile.path}',
      ], workingDirectory: copied.path);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      final emitted = jsonDecode(output.readAsStringSync()) as Map;
      expect(emitted['status'], 'success');
      final assets = emitted['assets'] as List;
      expect(assets, hasLength(1));
      final asset = (assets.single as Map)['encoding'] as Map;
      expect(asset['id'], 'package:$_package/swift_bridge');
      expect(asset['link_mode'], {'type': 'dynamic_loading_bundle'});
      expect(File(asset['file'] as String).existsSync(), isTrue);
      for (final path in _sources) {
        expect(await _sha(File('${copied.path}/$path')), sourceHashes[path]);
        expect(await _sha(File('${package.path}/$path')), sourceHashes[path]);
      }
      final dependencies = (emitted['dependencies'] as List).cast<String>();
      stdout.writeln(
        jsonEncode({
          'compiler_exit': result.exitCode,
          'consumer': consumer.path,
          'copied_package': copied.path,
          'dependencies': dependencies,
          'asset': asset,
          'source_sha256': sourceHashes,
        }),
      );
      expect(dependencies, hasLength(_sources.length));
      for (var i = 0; i < dependencies.length; i++) {
        final dependency = Uri.file(dependencies[i]);
        expect(
          dependency.isAbsolute,
          isTrue,
          reason: 'consumer must not reinterpret provider-relative inputs',
        );
        expect(dependency, copied.uri.resolve(_sources[i]));
        expect(
          File.fromUri(consumer.uri.resolveUri(dependency)).existsSync(),
          isTrue,
        );
      }
    },
    skip: Platform.isMacOS
        ? false
        : 'Actual Apple Swift bridge requires macOS.',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
