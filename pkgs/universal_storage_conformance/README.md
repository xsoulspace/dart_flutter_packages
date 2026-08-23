# universal_storage_conformance

Shared behavioral test suite for Universal Storage backends. Every
`StorageProvider` implementation must pass this suite to guarantee
swappability under the `StorageKernelContract`.

## Adopting the suite

Call `storageProviderConformanceTests` from your backend package's test
suite with a factory that produces a fresh, initialized provider per
scenario (the suite creates and disposes one provider per test):

```dart
import 'dart:io';
import 'package:test/test.dart';
import 'package:universal_storage_conformance/universal_storage_conformance.dart';
import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

void main() {
  storageProviderConformanceTests(
    'FileSystemStorageProvider',
    create: () async {
      final dir = await Directory.systemTemp.createTemp('conf_');
      final provider = FileSystemStorageProvider();
      await provider.initWithConfig(
        FileSystemConfig(
          filePathConfig: FilePathConfig.create(path: dir.path),
        ),
      );
      return provider;
    },
    supportsSync: false,
  );
}
```

See existing adoption in `universal_storage_filesystem`,
`universal_storage_local_db`, `universal_storage_git_offline`,
`universal_storage_github_api` (in-process fake API), and
`universal_storage_cloudkit` (fake bridge) test directories.

## Flags

- `supportsSync` (default `false`) — when false, the suite asserts that
  `sync()` throws `UnsupportedOperationException`. When true, a
  sync-capable contract group runs instead.
- `supportsRestore` (default `true`) — only meaningful with
  `supportsSync: true`; when true the suite additionally verifies that
  `restore()` without a version restores the latest state. Set to `false`
  for sync-capable backends without revision history.

## What is covered

CRUD round-trips, path normalization (leading/trailing slashes), empty and
unicode/large payloads, relative-name listing contract,
`isAuthenticated` determinism, and sync/restore contracts per flag.

## Capability model

Backends × `SyncAvailability` × restore support:

| Backend                  | SyncAvailability     | Restore |
|--------------------------|----------------------|---------|
| filesystem               | `none`               | no      |
| local_db                 | `none`               | no      |
| git_offline              | `withRemoteConfig`   | yes     |
| github_api               | `always`             | yes     |
| cloudkit                 | `always`             | yes     |

`SyncAvailability.none`: local-only; `sync()` must throw
`UnsupportedOperationException`.
`withRemoteConfig`: sync works once a remote is configured; unconfigured,
kernel-level sync degrades to a graceful no-op that retains the outbox.
`always`: remote is intrinsic to the backend.
