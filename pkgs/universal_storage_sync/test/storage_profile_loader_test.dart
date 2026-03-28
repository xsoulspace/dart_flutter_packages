import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';

class _LoaderFakeStorageProvider extends StorageProvider {
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

Future<FileSystemConfig> _createConfig() async {
  final tempDirectory = await Directory.systemTemp.createTemp(
    'profile_loader_test_',
  );
  return FileSystemConfig(
    filePathConfig: FilePathConfig.create(
      path: tempDirectory.path,
      macOSBookmarkData: MacOSBookmark.fromDirectory(tempDirectory),
    ),
  );
}

Future<StorageService> _createService(
  final _LoaderFakeStorageProvider provider,
) async {
  final service = StorageService(provider);
  await service.initializeWithConfig(await _createConfig());
  return service;
}

void main() {
  group('StorageProfileLoader', () {
    test('loadFromMap wires namespace services into kernel', () async {
      final settingsProvider = _LoaderFakeStorageProvider();
      final projectsProvider = _LoaderFakeStorageProvider();

      final settingsService = await _createService(settingsProvider);
      final projectsService = await _createService(projectsProvider);

      const loader = StorageProfileLoader();
      final result = await loader.loadFromMap(
        profileMap: <String, dynamic>{
          'name': 'loader_profile',
          'version': 1,
          'namespaces': <Map<String, dynamic>>[
            <String, dynamic>{
              'namespace': 'settings',
              'policy': 'localOnly',
              'local_engine_id': 'files',
            },
            <String, dynamic>{
              'namespace': 'projects',
              'policy': 'optimisticSync',
              'local_engine_id': 'files',
              'remote_engine_id': 'github',
            },
          ],
        },
        serviceFactory: (final namespaceProfile) async {
          if (namespaceProfile.namespace == StorageNamespace.settings) {
            return settingsService;
          }
          if (namespaceProfile.namespace == StorageNamespace.projects) {
            return projectsService;
          }
          throw ConfigurationException(
            'Unexpected namespace: ${namespaceProfile.namespace.value}',
          );
        },
      );

      await result.kernel.write(
        namespace: StorageNamespace.settings,
        path: 'settings.json',
        content: '{"mode":"offline"}',
      );

      expect(settingsProvider.files['settings.json'], isNotNull);
      expect(projectsProvider.files['settings.json'], isNull);
      expect(result.profile.name, 'loader_profile');
    });

    test('load throws in strict mode for duplicate namespaces', () async {
      final provider = _LoaderFakeStorageProvider();
      final service = await _createService(provider);

      const loader = StorageProfileLoader();
      const profile = StorageProfile(
        name: 'invalid',
        namespaces: <StorageNamespaceProfile>[
          StorageNamespaceProfile(
            namespace: StorageNamespace.settings,
            policy: StoragePolicy.localOnly,
          ),
          StorageNamespaceProfile(
            namespace: StorageNamespace.settings,
            policy: StoragePolicy.localOnly,
          ),
        ],
      );

      await expectLater(
        () => loader.load(
          profile: profile,
          serviceFactory: (final _) async => service,
        ),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('load collects non-fatal warnings', () async {
      final provider = _LoaderFakeStorageProvider();
      final service = await _createService(provider);

      const loader = StorageProfileLoader();
      const profile = StorageProfile(
        name: 'warning_profile',
        namespaces: <StorageNamespaceProfile>[
          StorageNamespaceProfile(
            namespace: StorageNamespace.projects,
            policy: StoragePolicy.optimisticSync,
            localEngineId: 'files',
            remoteEngineId: 'github',
            syncInteractionLevel: SyncInteractionLevel.complex,
          ),
        ],
      );

      final result = await loader.load(
        profile: profile,
        serviceFactory: (final _) async => service,
      );

      expect(result.warnings, isNotEmpty);
      expect(result.warnings.first, contains('complex interaction'));
    });

    test('loadFromJson rejects non-map payload', () async {
      const loader = StorageProfileLoader();

      await expectLater(
        () => loader.loadFromJson(
          jsonSource: '[]',
          serviceFactory: (final _) async {
            throw const ConfigurationException('Should not be called');
          },
        ),
        throwsA(isA<ConfigurationException>()),
      );
    });
  });
}
