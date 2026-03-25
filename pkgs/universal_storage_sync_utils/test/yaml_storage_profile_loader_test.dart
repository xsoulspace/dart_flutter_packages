import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';
import 'package:universal_storage_sync_utils/universal_storage_sync_utils.dart';

class _YamlLoaderFakeStorageProvider extends StorageProvider {
  final Map<String, String> files = <String, String>{};
  var _initialized = false;

  @override
  Future<void> initWithConfig(final StorageConfig config) async {
    _initialized = true;
  }

  @override
  Future<bool> isAuthenticated() async => _initialized;

  @override
  Future<FileOperationResult> createFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) async {
    files[path] = content;
    return FileOperationResult.created(path: path);
  }

  @override
  Future<String?> getFile(final String path) async => files[path];

  @override
  Future<FileOperationResult> updateFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) async {
    files[path] = content;
    return FileOperationResult.updated(path: path);
  }

  @override
  Future<FileOperationResult> deleteFile(
    final String path, {
    final String? commitMessage,
  }) async {
    files.remove(path);
    return FileOperationResult.deleted(path: path);
  }

  @override
  Future<List<FileEntry>> listDirectory(final String directoryPath) async =>
      files.keys
          .map(
            (final path) => FileEntry(
              name: path,
              isDirectory: false,
              size: files[path]!.length,
              modifiedAt: DateTime.now(),
            ),
          )
          .toList(growable: false);

  @override
  Future<void> restore(final String path, {final String? versionId}) async {}

  @override
  Future<void> dispose() async {}
}

Future<StorageService> _createService(
  final _YamlLoaderFakeStorageProvider provider,
) async {
  final tempDirectory = await Directory.systemTemp.createTemp(
    'yaml_loader_test_',
  );
  final config = FileSystemConfig(
    filePathConfig: FilePathConfig.create(
      path: tempDirectory.path,
      macOSBookmarkData: MacOSBookmark.fromDirectory(tempDirectory),
    ),
  );
  final service = StorageService(provider);
  await service.initializeWithConfig(config);
  return service;
}

void main() {
  group('YamlStorageProfileLoader', () {
    test('loads kernel from yaml and propagates validation warnings', () async {
      final provider = _YamlLoaderFakeStorageProvider();
      final service = await _createService(provider);

      const yaml = '''
version: 2
name: yaml_profile
namespaces:
  - namespace: settings
    policy: local_only
    local_engine_id: files
''';

      const yamlLoader = YamlStorageProfileLoader();
      final result = await yamlLoader.load(
        yamlSource: yaml,
        serviceFactory: (final _) async => service,
      );

      await result.kernel.write(
        namespace: StorageNamespace.settings,
        path: 'settings.json',
        content: '{"offline":true}',
      );

      expect(provider.files['settings.json'], isNotNull);
      expect(
        result.warnings.any(
          (final warning) => warning.contains('Schema v2 is parsed by v1'),
        ),
        isTrue,
      );
    });

    test('throws when schema validation has errors', () async {
      const yaml = '''
version: 1
name: invalid
namespaces:
  - namespace: projects
    policy: optimistic_sync
    local_engine_id: files
''';

      const yamlLoader = YamlStorageProfileLoader();

      await expectLater(
        () => yamlLoader.load(
          yamlSource: yaml,
          serviceFactory: (final _) => Future<StorageService>.error(
            const ConfigurationException('Should not be called'),
          ),
        ),
        throwsA(isA<ConfigurationException>()),
      );
    });
  });
}
