# Changelog

## 0.2.0

- **APP MANAGEMENT — the macOS rung** (manage applications, not only the
  focused one): `runningApps()` (discovery of running Dock-able apps),
  `frontmost()`, `launch(bundleId)` (launch-or-activate; a running app is
  adopted, never relaunched), `activate(pid)`, `terminate(pid)`, and
  `snapshotOfApp(pid)` — a semantic snapshot of ANY application's AX tree,
  background included (the old snapshot stays the focused-app shorthand).
  New bridge symbols: `xs_axdrv_apps_json`, `xs_axdrv_frontmost_json`,
  `xs_axdrv_activate_app`, `xs_axdrv_launch_app`, `xs_axdrv_terminate_app`,
  `xs_axdrv_snapshot_app_json`; error codes 7 (app not found) and 8
  (activation/launch/terminate failed) join the table.
- New `MacosApp` record (pid, bundleId, name, active, hidden) — the
  discovery record every app-targeted call consumes.
- Live-proven composition: `mcp_flutter` `showcase/drivers/bin/drive_macos.dart`
  discovers the running apps, targets one by pid or bundle id, activates
  it, observes its tree, reads a BACKGROUND app by pid, verifies, and
  captures a screenshot.

## 0.1.1

- Handle the sealed `InvokeAction` case (universal_automation_interface 0.2.0): the tier has no surface action registry, so the driver refuses loudly instead of failing to compile.

- interface constraint bump only; no code changes.

## 0.1.0 (2026-09-29)

- Initial release: `MacosDriver` implementing the family's
  `AutomationDriver` contract.
- Observe: depth-bounded semantic snapshot of the focused application
  (AXUIElement → `Snapshot`/`AxNode`), plus `elementAtPosition` hit-testing
  in top-left-origin screen coordinates (the hover query for pointer-driven
  UIs).
- Act: semantic clicks via AXPress with one transparent stale-handle
  re-observe, unicode typing, named key presses, wheel-line scrolling with
  sub-line accumulation, screenshots via CGDisplayCreateImage (Screen
  Recording permission).
- Typed exceptions: `AccessibilityPermissionRequiredException`,
  `ElementNotFoundException`, `ProtocolException`,
  `DriverUnsupportedException` (navigate/evaluate have no AX equivalent).
- Native-assets build hook (swiftc → dylib → code asset, the ADR 0001
  pattern); unit tests run without the dylib via the injectable
  `AxDriverBridge` seam.
