import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';

class _AdapterFakeStorageProvider extends StorageProvider {
  _AdapterFakeStorageProvider({this.syncEnabled = false});

  final bool syncEnabled;
  final Map<String, String> files = <String, String>{};
  int syncCalls = 0;
  var _initialized = false;

  @override
  Future<void> initWithConfig(final StorageConfig config) async {
    _initialized = true;
  }

  @override
  Future<bool> isAuthenticated() async => _initialized;

  void _ensureInitialized() {
    if (!_initialized) {
      throw const AuthenticationException('Provider not initialized.');
    }
  }

  @override
  Future<FileOperationResult> createFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();
    files[path] = content;
    return FileOperationResult.created(path: path);
  }

  @override
  Future<String?> getFile(final String path) async {
    _ensureInitialized();
    return files[path];
  }

  @override
  Future<FileOperationResult> updateFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();
    files[path] = content;
    return FileOperationResult.updated(path: path);
  }

  @override
  Future<FileOperationResult> deleteFile(
    final String path, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();
    files.remove(path);
    return FileOperationResult.deleted(path: path);
  }

  @override
  Future<List<FileEntry>> listDirectory(final String directoryPath) async {
    _ensureInitialized();
    final normalizedPath = directoryPath == '.'
        ? ''
        : directoryPath.replaceAll(RegExp(r'^/+|/+$'), '');
    final entries = <FileEntry>[];
    for (final entry in files.keys) {
      if (normalizedPath.isEmpty || entry.startsWith('$normalizedPath/')) {
        entries.add(
          FileEntry(
            name: entry,
            isDirectory: false,
            size: files[entry]!.length,
            modifiedAt: DateTime.now(),
          ),
        );
      }
    }
    return entries;
  }

  @override
  Future<void> restore(final String path, {final String? versionId}) async {
    _ensureInitialized();
  }

  @override
  bool get supportsSync => syncEnabled;

  @override
  Future<void> sync({
    final String? pullMergeStrategy,
    final String? pushConflictStrategy,
  }) async {
    _ensureInitialized();
    if (syncEnabled) {
      syncCalls++;
    }
  }

  @override
  Future<void> dispose() async {}
}

Future<FileSystemConfig> _createConfig() async {
  final tempDirectory = await Directory.systemTemp.createTemp(
    'storage_service_kernel_adapter_test_',
  );
  return FileSystemConfig(
    filePathConfig: FilePathConfig.create(
      path: tempDirectory.path,
      macOSBookmarkData: MacOSBookmark.fromDirectory(tempDirectory),
    ),
  );
}

void main() {
  group('StorageServiceKernelAdapter', () {
    test(
      'preserves legacy service-style read/write/delete/list flows',
      () async {
        final provider = _AdapterFakeStorageProvider();
        final service = StorageService(provider);
        await service.initializeWithConfig(await _createConfig());

        const profile = StorageProfile(
          name: 'adapter_profile',
          namespaces: <StorageNamespaceProfile>[
            StorageNamespaceProfile(
              namespace: StorageNamespace.projects,
              policy: StoragePolicy.localOnly,
            ),
          ],
        );
        final resolver = InMemoryStorageProfileResolver(
          namespaceServices: <StorageNamespace, StorageService>{
            StorageNamespace.projects: service,
          },
        );
        final kernel = StorageKernel(profile: profile, resolver: resolver);
        final adapter = StorageServiceKernelAdapter(
          kernel: kernel,
          namespace: StorageNamespace.projects,
        );

        await adapter.saveFile('todos/a.yaml', 'title: A');
        await adapter.saveFile('todos/a.yaml', 'title: Updated');
        final content = await adapter.readFile('todos/a.yaml');
        final listed = await adapter.listDirectory('todos');
        await adapter.removeFile('todos/a.yaml');

        expect(content, 'title: Updated');
        expect(listed.any((final item) => item.name == 'todos/a.yaml'), isTrue);
        expect(provider.files.containsKey('todos/a.yaml'), isFalse);
      },
    );

    test(
      'syncRemote delegates to kernel sync for selected namespace',
      () async {
        final provider = _AdapterFakeStorageProvider(syncEnabled: true);
        final service = StorageService(provider);
        await service.initializeWithConfig(await _createConfig());

        const profile = StorageProfile(
          name: 'adapter_sync_profile',
          namespaces: <StorageNamespaceProfile>[
            StorageNamespaceProfile(
              namespace: StorageNamespace.projects,
              policy: StoragePolicy.optimisticSync,
              remoteEngineId: 'fake-remote',
            ),
          ],
        );
        final resolver = InMemoryStorageProfileResolver(
          namespaceServices: <StorageNamespace, StorageService>{
            StorageNamespace.projects: service,
          },
        );
        final kernel = StorageKernel(profile: profile, resolver: resolver);
        final adapter = StorageServiceKernelAdapter(
          kernel: kernel,
          namespace: StorageNamespace.projects,
        );

        await adapter.syncRemote();
        expect(provider.syncCalls, 1);
      },
    );
  });
}
