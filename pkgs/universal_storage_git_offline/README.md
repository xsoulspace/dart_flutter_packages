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

## Batched commits (`GitCommitBatching`)

Git commits cost ~100ms+ each; committing per write makes write-heavy
workloads unusable. Pass a `GitCommitBatching` policy when constructing
`OfflineGitStorageProvider` to defer and coalesce commits:

```dart
final provider = OfflineGitStorageProvider(
  commitBatching: const GitCommitBatching(
    maxDelay: Duration(milliseconds: 500), // flush at least this often
    maxPendingOperations: 50,              // or once this many mutations queue up
  ),
);
```

Tradeoffs:

- **Write-through reads**: file content is written to disk immediately, so
  reads are always consistent with the last write even before a commit.
- **Deferred durability**: revisions/commits for pending mutations only exist
  after a flush; a crash before flush loses history granularity, not data.
- **Flush points**: pending mutations are flushed automatically before
  `sync()`, `restore()`, and `dispose()`. Call `flushPendingCommits()` to
  force a commit at any other point you need durable revisions.

Measured impact: kernel write p50 drops from ~150ms to ~46ms (~3x); outbox
replay throughput rises from ~55 to ~220 entries/sec.

## Current Limitations (2026-03-02)

- `cloneRepository` is intentionally unsupported for this provider and throws
  `UnsupportedOperationException`.
- `setRepository` switches local context by sibling directory name and does not
  perform remote discovery.

## Notes

- Requires Git CLI for sync and advanced operations.
- Configure remote via `OfflineGitConfig` to enable sync (`supportsSync` is
  false when no remote is configured).
