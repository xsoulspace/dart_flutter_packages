# universal_storage_cloudkit

CloudKit provider package for Universal Storage.

## What It Adds

- `CloudKitStorageProvider`
- `registerUniversalStorageCloudKit()`
- `CloudKitPayloadTooLargeException`

## Modes

- `CloudKitDataMode.remoteOnly`: CRUD hits CloudKit bridge directly.
- `CloudKitDataMode.localMirror`: CRUD writes local filesystem mirror and sync does pull-then-push.

## Registration

```dart
import 'package:universal_storage_cloudkit/universal_storage_cloudkit.dart';

void bootstrap() {
  registerUniversalStorageCloudKit();
}
```
