# universal_storage_git_offline

Offline Git provider for Universal Storage. Local Git repository with optional remote sync.

## Install

```yaml
dependencies:
  universal_storage_interface: ^0.1.0-dev.2
  universal_storage_git_offline: ^0.1.0-dev.2
```

## Usage

```dart
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_git_offline/universal_storage_git_offline.dart';

final service = StorageService(OfflineGitStorageProvider());
await service.initializeWithConfig(OfflineGitConfig(
  localPath: '/path/to/repo',
  branchName: VcBranchName.main,
  authorName: 'Your Name',
  authorEmail: 'you@example.com',
));

await service.saveFile('README.md', '# Project', message: 'docs: add readme');
await service.restoreData('README.md');
```

## Notes

- Requires Git CLI for sync and advanced operations
- Configure remote via `OfflineGitConfig` to enable sync

## License

MIT
