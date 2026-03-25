# xsoulspace_steamworks example

Small desktop Flutter app demonstrating:

- Steam init/shutdown
- callback pumping
- stats request
- achievement set/clear + store

## Run with real Steam runtime

```bash
flutter run -d macos
```

(or `-d windows` / `-d linux`)

## Run with fake backend (no Steam required)

```bash
flutter run -d macos --dart-define=STEAMWORKS_EXAMPLE_FAKE=true
```

## Integration test

```bash
flutter test integration_test -d macos
```

Use `-d windows` or `-d linux` on those platforms.

The integration test always uses the fake backend for deterministic CI behavior
and does not require running Steam.
