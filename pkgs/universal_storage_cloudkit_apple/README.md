# universal_storage_cloudkit_apple

Apple (iOS/macOS) bridge package for `universal_storage_cloudkit`.

This package registers a Pigeon/typed-channel backed `CloudKitBridge`
implementation for native CloudKit operations.

Implemented host-side operations:
- private database + custom zone bootstrap
- record CRUD (`USFile`-style fields)
- path-prefix queries
- zone change fetching with encoded server change token
- Apple error mapping to bridge error codes

## Testing

```bash
flutter test
swift test
```

## Regenerate Pigeon API

```bash
flutter pub run pigeon --input pigeons/cloudkit_apple_api.dart
```
