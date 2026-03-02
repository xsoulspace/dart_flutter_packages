# Universal Storage Sync

Universal Storage orchestration layer.

Status: alpha (`0.1.0-dev`). Not production-complete yet.

## Scope

`universal_storage_sync` provides:

- provider registry + factory (`StorageProviderRegistry`, `StorageFactory`)
- provider-agnostic service (`StorageService`)
- profile/kernel orchestration (`StorageProfileLoader`, `StorageKernel`)
- migration/sync helpers and capability models

Provider implementations live in dedicated packages:

- `universal_storage_filesystem`
- `universal_storage_github_api`
- `universal_storage_git_offline`

## Installation

```yaml
dependencies:
  universal_storage_sync: ^0.1.0-dev.10
  universal_storage_filesystem: ^0.1.0-dev.11
```

## Quick Start (Filesystem)

```dart
import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';

Future<void> main() async {
  StorageProviderRegistry.register<FileSystemConfig>(
    () => FileSystemStorageProvider(),
  );

  final config = FileSystemConfig(
    filePathConfig: FilePathConfig({'path': '/path/to/workspace'}),
  );

  final storage = await StorageFactory.create(config);
  await storage.saveFile('hello.txt', 'Hello');
  final content = await storage.readFile('hello.txt');
  print(content);
}
```

## Quick Start (Profile + Kernel)

```dart
import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';

Future<StorageKernel> buildKernel() async {
  final fsService = StorageService(FileSystemStorageProvider());
  await fsService.initializeWithConfig(
    FileSystemConfig(
      filePathConfig: FilePathConfig({'path': '/path/to/workspace'}),
    ),
  );

  final profile = StorageProfile(
    name: 'my_profile_v1',
    namespaces: const <StorageNamespaceProfile>[
      StorageNamespaceProfile(
        namespace: StorageNamespace.projects,
        policy: StoragePolicy.localOnly,
        localEngineId: 'filesystem',
        defaultFileExtension: '.yaml',
      ),
    ],
  );

  final loaded = await const StorageProfileLoader().load(
    profile: profile,
    serviceFactory: (final _) async => fsService,
  );

  return loaded.kernel;
}
```

## Known Gaps (2026-03-02)

- Clone-to-local workflows are capability-gated (`supportsCloneToLocal`) and
  are unavailable on API-only providers such as `GitHubApiStorageProvider`.
- App integrations are partial; several apps initialize kernel but still keep
  legacy data paths as primary storage.

## Production Path

For the concrete production-completeness plan and exit criteria:

- `../universal_storage_docs/PRODUCTION_COMPLETENESS_PATH.md`
