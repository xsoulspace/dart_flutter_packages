# universal_storage_sync_utils

Pure Dart utilities for Universal Storage sync/profile workflows.

Status: alpha (`0.1.0-dev`).

## What This Package Provides

- YAML profile loading helper
- Profile schema/capability validation
- Repository workflow helper (`RepositoryManager`)
- Migration recipe modeling utilities
- Path writability validation (`PathValidator`)
- Shared picker result models (`PickResult`)

## Flutter-Specific APIs

Folder picker and macOS bookmark implementations were moved to:
`universal_storage_sync_utils_flutter`.

## Installation

```yaml
dependencies:
  universal_storage_sync_utils: ^0.1.0-dev.13
```

## Repository Manager Example

```dart
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_sync_utils/universal_storage_sync_utils.dart';

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
