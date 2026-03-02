# universal_storage_github_api

GitHub REST API provider for Universal Storage (no local Git required).

Status: alpha (`0.1.0-dev`). Provider contract methods are implemented.

## Installation

```yaml
dependencies:
  universal_storage_github_api:
    path: ../universal_storage_github_api
  universal_storage_interface:
    path: ../universal_storage_interface
```

## Usage

```dart
import 'package:universal_storage_github_api/universal_storage_github_api.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

Future<void> main() async {
  final provider = GitHubApiStorageProvider();
  await provider.initWithConfig(
    GitHubApiConfig(
      authToken: 'ghp_xxx',
      repositoryOwner: const VcRepositoryOwner('owner'),
      repositoryName: const VcRepositoryName('repo'),
      branchName: VcBranchName.main,
    ),
  );

  final service = StorageService(provider);
  await service.saveFile('docs/readme.md', '# Docs', message: 'docs: add readme');
}
```

## Current Limitations (2026-03-02)

- `cloneRepository` is intentionally unsupported in this API-only provider and
  throws `UnsupportedOperationException`.
- Use `OfflineGitStorageProvider` when you need local clone workflows.

## Notes

- Works on web and non-web platforms.
- Subject to GitHub API rate limits and token permissions.
- Authentication flow is intentionally out of scope for this package; use
  `universal_storage_oauth` or app-level token acquisition.
