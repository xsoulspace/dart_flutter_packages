# universal_storage_interface

Core contracts, models, and exceptions for Universal Storage.

Status: alpha (`0.1.0-dev`). API may still change.

## What This Package Contains

- `StorageProvider`: low-level provider contract (`initWithConfig`, CRUD, list, restore, optional sync, dispose)
- `StorageService`: provider-agnostic service (`saveFile`, `readFile`, `removeFile`, `listDirectory`, `restoreData`, `syncRemote`)
- Typed configs:
  - `FileSystemConfig`
  - `OfflineGitConfig`
  - `GitHubApiConfig`
- Kernel/profile contracts:
  - `StorageProfile`, `StorageNamespaceProfile`, `StoragePolicy`
  - `StorageKernelContract`, `LocalEngine`, `RemoteEngine`, `SyncEngine`
- Version control contracts/models:
  - `VersionControlService`
  - `VcRepository`, `VcBranch`, `VcCreateRepositoryRequest`, etc.

## Installation

```yaml
dependencies:
  universal_storage_interface: ^0.1.0-dev.10
```

## Minimal Usage

```dart
import 'package:universal_storage_interface/universal_storage_interface.dart';

class InMemoryProvider extends StorageProvider {
  final Map<String, String> _files = <String, String>{};

  @override
  Future<void> initWithConfig(final StorageConfig config) async {}

  @override
  Future<bool> isAuthenticated() async => true;

  @override
  Future<FileOperationResult> createFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) async {
    if (_files.containsKey(path)) {
      throw FileAlreadyExistsException('File exists: $path');
    }
    _files[path] = content;
    return FileOperationResult.created(path: path);
  }

  @override
  Future<String?> getFile(final String path) async => _files[path];

  @override
  Future<FileOperationResult> updateFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) async {
    if (!_files.containsKey(path)) {
      throw FileNotFoundException('File not found: $path');
    }
    _files[path] = content;
    return FileOperationResult.updated(path: path);
  }

  @override
  Future<FileOperationResult> deleteFile(
    final String path, {
    final String? commitMessage,
  }) async {
    _files.remove(path);
    return FileOperationResult.deleted(path: path);
  }

  @override
  Future<List<FileEntry>> listDirectory(final String directoryPath) async =>
      _files.keys
          .where((final k) => k.startsWith(directoryPath))
          .map((final k) => FileEntry(name: k, isDirectory: false))
          .toList();

  @override
  Future<void> restore(final String path, {final String? versionId}) async {}

  @override
  Future<void> dispose() async {}
}

Future<void> main() async {
  final service = StorageService(InMemoryProvider());
  await service.initializeWithConfig(
    FileSystemConfig(filePathConfig: FilePathConfig({'path': '/tmp'})),
  );
  await service.saveFile('notes/a.txt', 'hello');
}
```

## Notes

- `StorageService.syncRemote()` throws `CapabilityMismatchException` when the
  provider reports `supportsSync == false`.
- For production rollout status and completion plan, see:
  - `../universal_storage_docs/PRODUCTION_COMPLETENESS_PATH.md`
