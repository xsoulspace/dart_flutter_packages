## Universal Storage Sync — Architecture (Short)

### Core Principles

- **Interfaces first**: All types come from `package:universal_storage_interface`.
- **Separation of concerns**: Foundation orchestrates; providers implement.
- **Pluggable providers**: Providers live in separate packages and register at runtime.
- **Typed configs**: `StorageConfig` subtypes select providers; no map-based models.
- **Predictable errors**: Create → `FileAlreadyExistsException`; Update/Delete → `FileNotFoundException`; missing directories → return `[]`.

### High-level Flow

1. App registers provider factories for config types using `StorageProviderRegistry`.
2. App calls `StorageFactory.create(config)`.
3. Factory resolves provider via registry, initializes it with typed `config` and returns `StorageService`.
4. `StorageService` exposes unified APIs: `saveFile`, `readFile`, `removeFile`, `listDirectory`, `restoreData`, `syncRemote`.

### Key Components

- `StorageService` (foundation): Unified API over a `StorageProvider`.
- `StorageFactory` (foundation): Creates initialized `StorageService` using registry resolution.
- `StorageProviderRegistry` (foundation): Decouples foundation from providers; providers register themselves.
- `StorageProvider` (interface): Contract implemented by providers.
- `VersionControlService` (interface): Optional capabilities for VCS features.
- `StorageConfig` (interface): Typed configs that drive provider selection.

### Provider Registration (Example)

```dart
import 'package:universal_storage_sync/universal_storage_sync.dart';
import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';
import 'package:universal_storage_github_api/universal_storage_github_api.dart';
import 'package:universal_storage_git_offline/universal_storage_git_offline.dart';

void bootstrap() {
  StorageProviderRegistry.register<FileSystemConfig>(
    () => FileSystemStorageProvider(),
  );
  StorageProviderRegistry.register<GitHubApiConfig>(
    () => GitHubApiStorageProvider(),
  );
  StorageProviderRegistry.register<OfflineGitConfig>(
    () => OfflineGitStorageProvider(),
  );
}
```

### Usage (Factory + Service)

```dart
final service = await StorageFactory.create(
  FileSystemConfig(basePath: '/data'),
);
await service.saveFile('file.txt', 'content');
```

### Testing Strategy

- Provider-specific unit tests live in provider packages.
- Foundation tests validate `StorageFactory` wiring, `StorageService` behavior, and error contracts.
