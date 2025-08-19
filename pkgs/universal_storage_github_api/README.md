# universal_storage_github_api

GitHub API provider for Universal Storage using GitHub REST API (no local Git).

## Install

```yaml
dependencies:
  universal_storage_interface: ^0.1.0-dev.2
  universal_storage_github_api: ^0.1.0-dev.2
```

## Usage

```dart
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_github_api/universal_storage_github_api.dart';

final provider = GitHubApiStorageProvider();
await provider.initWithConfig(GitHubApiConfig(
  authToken: 'ghp_xxx',
  repositoryOwner: const VcRepositoryOwner('owner'),
  repositoryName: const VcRepositoryName('repo'),
  branchName: VcBranchName.main,
));

final service = StorageService(provider);
await service.saveFile('docs/readme.md', '# Docs', message: 'docs: add readme');
```

## Notes

- Works on web
- Subject to GitHub API rate limits

## License

MIT
