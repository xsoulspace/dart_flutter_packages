# universal_driver_macos

macOS driver for the [universal automation
family](../universal_automation_interface): the observe/act/verify loop
over the real accessibility tree (AXUIElement) and CGEvent input
synthesis. Pure Dart — no Flutter plugin surface, no FFI path hunting —
through native-assets build hooks (the ADR 0001 pattern).

## Native build/cache regression

Run `XS_TEST_NATIVE_HOOK=1 dart test test/native_hook_test.dart` on macOS.
It copies the package into an owned temporary fixture, builds a real Swift
code asset, loads it through MacosDriver.frontmost, checks warm reuse, then
changes only the copied Swift source and checks rebuilding. It refuses the
"File modified during build" warning and checks absolute dependency paths.
The fixture never activates an app or edits the repository bridge. The default
suite skips this compiler-dependent test; unit driver tests are separate proof.

## What it can do

| Capability | Status | Notes |
|---|---|---|
| `a11yTree` | yes | Focused application snapshot, depth- and node-bounded |
| `inputSynthesis` | yes | AXPress clicks, unicode typing, keys, wheel scrolling |
| `pointerCoordinates` | yes | `ClickAtAction`/`MoveAction`/`DragAction` as CGEvents (ADR 0053) |
| `behaviorDynamics` | yes | `BehavioralMacosDriver` lowers humanized plans, gestures included |
| `screenshot` | yes | Main display PNG; needs Screen Recording permission |
| `screencast` | no | Use `universal_capture_macos` + `universal_screencast` |
| `evaluate` | no | No AX equivalent; refused loudly |

## Permissions

Semantic click/setValue/elementAction locators must match exactly one observed
node. Duplicate role/name matches throw ProtocolException with locator and match
count before native mutation; a stale-handle refresh applies the same rule.
Add a unique accessible name or scope the app's controls instead of relying on
tree order. Completion of AXPress is delivery evidence; verify the app effect
independently. A rendered background window does not guarantee an exposed AX
window/control subtree.

- **Accessibility** (System Settings → Privacy & Security → Accessibility):
  required for `snapshot`/`elementAtPosition`/`perform`. Check with
  `driver.axTrusted`, prompt once with `driver.requestTrust()`. Missing
  permission throws the typed
  `AccessibilityPermissionRequiredException`.
- **Screen Recording**: a separate TCC grant, needed only for pixel
  capture — `screenshot()`, `windowScreenshot(windowId)`. Missing
  consent throws the typed
  `ScreenRecordingPermissionRequiredException`; the
  `screenRecording` consent kind in `xsoulspace_permission_core` is the
  policy vocabulary for it.

## Windows and window-scoped capture

`windows({pid})` lists the on-screen, normal-layer windows (ids,
bounds, titles — titles may be empty without Screen Recording;
ids/bounds need no consent). `windowScreenshot(windowId, {maxPx})`
captures one window — occlusion included, exact window bounds;
`maxPx` caps the long side for agent-facing budgets (the ~1024px
convention). A window that yields no image (some auxiliary surfaces)
fails loudly, never silently empty.

## Coordinate convention

`elementAtPosition(x, y)` takes **top-left relative screen coordinates** —
the system `AXUIElementCopyElementAtPosition` documents, and the same one
CGEvent mouse events use, so pointer positions feed in without conversion.

## Hover throttling (load-bearing)

AX queries are synchronous Mach IPC to the target application (~ms each).
`elementAtPosition` is the hover query for pointer-driven UIs: throttle it
to pointer cadence (e.g. coalesce to the latest position per frame), never
call it per camera frame. Measure before assuming — see
`docs/validation.md` in the consuming project.

## Element handles

Each observation (snapshot or hit-test) registers fresh element handles on
the native side and clears the previous batch; nodes carry their handle as
the `axid` attribute. A click on a stale handle transparently re-observes
once and retries before giving up with `ElementNotFoundException`.

## Testing

Unit tests run everywhere (the driver takes an injectable `AxDriverBridge`).
Live smoke tests need the grant and opt-in:

```sh
XS_AX_DRIVER_LIVE=1 dart test test/driver_bridge_live_test.dart
```

## Non-claims

- Letters/digits in `KeyPressAction` map to US-layout keycodes (the same
  convention the Vosges desktop host uses); non-US layouts remap them.
- Windows and menus of apps that expose no AX tree (games, some Electron
  configs) are invisible to `snapshot`; `elementAtPosition` then returns
  `ElementNotFoundException` at any position over them.
- Scroll synthesis posts wheel-line events at the current mouse position;
  it does not target a specific scroll view by element.
