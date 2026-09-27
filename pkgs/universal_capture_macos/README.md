# universal_capture_macos

macOS-native screen capture and accessibility checks for **pure Dart**,
wired through Dart native-assets build hooks — the ADR 0001 pattern
(`hook/build.dart` compiles the Swift bridge with `swiftc`, registers a
code asset, and Dart binds via `@Native`). **No Flutter plugin surface.**

Part of the `universal_automation_*` family
([ADR 0037](../../docs/decisions/0037_universal_automation_family.md)).
This is the OS-native tier of the family: it can observe and capture
apps that never opted into any protocol.

## What it does

- `CaptureBridge.version()` — bridge identity.
- `CaptureBridge.axTrusted` — may this process drive the AX tree?
  Never prompts.
- `CaptureBridge.screenPermissionPreflight` — is screen capture already
  permitted? Never prompts.
- `CaptureBridge.requestScreenPermission()` — the explicit, user-facing
  consent prompt; call only from user-initiated flows.
- `CaptureBridge.screenshotPng({displayId})` — one PNG frame of a
  display; throws `CapturePermissionDeniedException` (with a remediation
  path in the message) when consent is missing.
- `CaptureBridge.listDisplays()` — online display ids.

## Requirements

- macOS 13+ (built for arm64 and x64).
- `swiftc` + Xcode command line tools at build time (the hook runs on
  `dart pub get`).
- Screen Recording permission for capture; Accessibility permission for
  AX (checked, not managed, by this package).

## Non-claims

- Single-frame capture only; continuous ScreenCaptureKit streaming and
  AX-tree reads are future work (ADR 0037).
- Windows/Linux are out of scope for this package; the family's
  Linux path is AT-SPI (future).
