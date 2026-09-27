# universal_driver_linux

Linux accessibility driver for the `universal_automation_*` family:
**AT-SPI2 over D-Bus in pure Dart** — observe any Linux desktop app's
semantic tree and act through the AT-SPI `Action` interface (the same
trusted path screen readers use). No X11 tools, no native binary.

Part of [ADR 0037](../../docs/decisions/0037_universal_automation_family.md);
OS-native tier alongside `universal_capture_macos`.

## What it does

- `AtspiDriver` — the family observe/act/verify contract: the AT-SPI
  tree mapped to `Snapshot`/`AxNode` (roles normalized: `push button` →
  `button`, `text` → `textbox`, …); `ClickAction(name:)` dispatches
  `Action.DoAction`.
- `DBusAtspiBus` — resolves the accessibility bus through
  `org.a11y.Bus`, walks `org.a11y.atspi.Accessible` (GetChildren with
  ChildCount/GetChildAtIndex fallback), `GetRoleName`, and `Action`.
- `package:universal_driver_linux/testing.dart` — a canned in-memory
  bus so consumers can test on any platform.

## Capabilities (honest)

a11y tree ✓ · semantic click ✓ · navigation/typing/keys/script ✗
(refused loudly — those need browser protocols or keyboard synthesis).

## Non-claims

- Verified against the fake bus and the documented at-spi2 D-Bus
  interface; a live GNOME/KDE session pass is the next evidence gate.
- Keyboard/text synthesis is an input-tier feature (future).
