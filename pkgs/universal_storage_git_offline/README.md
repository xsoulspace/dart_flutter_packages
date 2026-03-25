# universal_storage_git_offline

Offline Git provider for Universal Storage.

Status: alpha (`0.1.0-dev`). Provider contract methods are implemented.

## Installation

```yaml
dependencies:
  universal_storage_git_offline:
    path: ../universal_storage_git_offline
  universal_storage_interface:
    path: ../universal_storage_interface
```

## Usage

```dart
import 'package:universal_storage_git_offline/universal_storage_git_offline.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

Future<void> main() async {
  final service = StorageService(OfflineGitStorageProvider());
  await service.initializeWithConfig(
    OfflineGitConfig(
      localPath: '/path/to/repo',
      branchName: VcBranchName.main,
      authorName: 'Your Name',
      authorEmail: 'you@example.com',
    ),
  );

  await service.saveFile('README.md', '# Project', message: 'docs: add readme');
  await service.restoreData('README.md');
}
```

## Current Limitations (2026-03-02)

- `cloneRepository` is intentionally unsupported for this provider and throws
  `UnsupportedOperationException`.
- `setRepository` switches local context by sibling directory name and does not
  perform remote discovery.

## Notes

- Requires Git CLI for sync and advanced operations.
- Configure remote via `OfflineGitConfig` to enable sync (`supportsSync` is
  false when no remote is configured).
