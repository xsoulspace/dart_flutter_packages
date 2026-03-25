# universal_storage_cloudkit_web

Web bridge package for `universal_storage_cloudkit`.

## Architecture

- Raw layer: `lib/src/raw/cloudkit_raw.g.dart` (generated)
- Wrapper layer: `CloudKitWebBridge` and `CloudKitWebClient`
  - Preferred runtime mode: native CloudKit JS object model
    (`CloudKit.configure` + container/private DB methods)
  - Compatibility mode: adapter-style `window.CloudKit.*` methods when present

## Testing

- VM tests: `flutter test`
- Browser interop tests (stubbed global `CloudKit`):  
  `dart test -p chrome test/cloudkit_js_interop_browser_test.dart`

## Regeneration

CloudKit web raw bindings are generated from the pinned
`tool/generated/cloudkit.generated.d.ts` snapshot through
`xsoulspace_js_interop_codegen` (TS IR parser + Dart emitter).

```bash
dart run tool/generate.dart
dart run tool/generate.dart --check
```
