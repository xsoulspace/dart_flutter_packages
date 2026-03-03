# universal_storage_cloudkit_web

Web bridge package for `universal_storage_cloudkit`.

## Architecture

- Raw layer: `lib/src/raw/cloudkit_raw.g.dart` (generated)
- Wrapper layer: `CloudKitWebBridge` and `CloudKitWebClient`

## Regeneration

```bash
dart run tool/generate.dart
dart run tool/generate.dart --check
```
