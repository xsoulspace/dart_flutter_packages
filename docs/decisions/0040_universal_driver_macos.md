# ADR 0040: `universal_driver_macos` — AXUIElement observation + CGEvent synthesis

- Status: Accepted
- Date: 2026-09-29
- North Star impact: `applies`
- Builds on: [ADR 0037](0037_universal_automation_family.md) (driver
  contract), [ADR 0001](0001_native_ffi_bridge_acp.md) (native-assets hook
  pattern)

## Context

The automation family had four drivers (AT-SPI2, UIA, CDP, WebDriver) but
none for macOS: no AXUIElement tree reads, no CGEvent synthesis anywhere in
the workspace (verified 2026-09-29 by search across `~/xs`; the only AX
usage was `AXIsProcessTrusted()` boolean probes). The Vosges gesture
controller is the pulling consumer: pointer-driven interaction needs the
*semantic* element under the pointer (hover affordances, element-scoped
clicks), which blind CGWarp + click injection cannot answer.

## Decision

New package `pkgs/universal_driver_macos`, implementing the family's
`AutomationDriver` contract:

- **Observe** — depth- and node-bounded snapshot of the focused
  application (AXUIElement → family `Snapshot`/`AxNode`; the bridge
  serializes to the model's exact JSON shape), plus `elementAtPosition`
  hit-testing for hover affordances.
- **Act** — AXPress for semantic clicks (locator resolution against the
  latest snapshot, one transparent stale-handle re-observe), CGEvent
  unicode typing, named keys, wheel-line scrolling with sub-line
  accumulation, PNG screenshots.
- **Bridge** — flat C ABI (`@_cdecl`, `xs_axdrv_*` prefix), swiftc-compiled
  dylib registered as a code asset by the build hook; Dart binds via
  `@Native` and tests run without the dylib through an injectable
  `AxDriverBridge`.

## Load-bearing findings (do not re-learn)

- **CLI processes get `kAXErrorFailure` (-25204) on AX element queries
  even when TCC-trusted.** Touching `NSApplication.shared` with
  `.prohibited` activation policy registers the process with the window
  server and fixes it; the bridge does this lazily in `systemWide()`.
- `AXUIElementCopyElementAtPosition` takes **top-left-origin screen
  coordinates** (per header docs) — the same system CGEvent mouse events
  use; no conversion either side. Its Swift import takes `Float` coords
  and a plain `AXUIElement?` out-param (audited header, no `Unmanaged`).
- The Swift overlay of `AXUIElementCopyAttributeValue` drops the trailing
  error out-param and keeps `CFString` attribute params — 3-arg calls.
- AX queries are synchronous Mach IPC (~ms each): `elementAtPosition` is a
  hover query for pointer cadence, never per camera frame.
- Element handles are registry ids invalidated by every new observation;
  stale ids fail closed (code 5) and clicks re-observe once before giving
  up.

## Consequences

- Vosges can build semantic hover/commit affordances on real macOS app
  surfaces (see `vosges/docs/semantic-control.md`).
- Windows/Linux/macOS now all have a native driver; the family contract is
  exercised identically via `universal_automation_conformance`.
- Non-claims: no window management (move/focus/raise), no app launching,
  no clipboard, no AXObserver notifications, no per-scroll-view targeting
  (scroll posts at the current pointer position).
