# universal_storage_sync_utils

Utilities for Universal Storage sync/profile workflows.

Status: alpha (`0.1.0-dev`).

## What This Package Provides

- Folder selection + writable path checks (`pickWritableDirectory`)
- Default app path resolution (`resolveDefaultPath`)
- macOS bookmark helpers for sandboxed paths
- YAML profile loading helper
- Profile schema/capability validation
- Repository workflow helper (`RepositoryManager`)

## Installation

```yaml
dependencies:
  universal_storage_sync_utils: ^0.1.0-dev.12
```

## Directory Picker Example

```dart
import 'package:universal_storage_sync_utils/universal_storage_sync_utils.dart';

Future<void> pick() async {
  final result = await pickWritableDirectory();

  switch (result) {
    case PickSuccess(config: final config):
      print('Selected path: ${config.path.path}');
    case PickFailure(reason: final reason):
      print('Failed: $reason');
    case PickCancelled():
      print('Cancelled');
  }
}
```

## Repository Manager Example

```dart
import 'package:universal_storage_sync_utils/universal_storage_sync_utils.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

class MyRepoUi implements RepositorySelectionUIDelegate {
  const MyRepoUi();

  @override
  Future<VcRepository?> selectRepository(
    final List<VcRepository> repositories, {
    final String? suggestedName,
  }) async => repositories.isEmpty ? null : repositories.first;

  @override
  Future<VcCreateRepositoryRequest?> getRepositoryCreationDetails(
    final RepositorySelectionConfig config,
  ) async => VcCreateRepositoryRequest(
    name: config.suggestedName ?? 'my-repo',
    description: config.defaultDescription ?? '',
    isPrivate: config.defaultPrivate,
    organization: '',
  );

  @override
  Future<void> showProgress(final String message) async {}

  @override
  Future<void> hideProgress() async {}

  @override
  Future<void> showError(final String title, final String message) async {}
}
```

`RepositoryManager.cloneRepositoryToLocal(...)` performs a capability-first
check via `VersionControlService.resolveVersionControlCapabilities()` and
blocks clone calls when `supportsCloneToLocal == false`.

## Known Constraints (2026-03-02)

- `RepositoryManager` depends on a fully implemented
  `VersionControlService`; clone-to-local flows now require explicit provider
  capability support (`supportsCloneToLocal`).
