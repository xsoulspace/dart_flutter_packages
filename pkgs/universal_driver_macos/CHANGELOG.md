# Changelog

## 0.1.1

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
