# ADR 0065: OS-AX web fidelity, window-local semantic pointer, and preview stream

Date: 2026-10-26
Status: Accepted and implemented (2026-10-26)
Related: 0064 (background actuation), 0053 (coordinates last), 0052 (semantic
snapshots), UA ADR 0003 (tier routing), UA ADR 0005 (capture)

## Context

Agents driving real browsers through the macOS accessibility tier were
seeing only chrome chrome and footer links while the page form lived in an
`AXWebArea` subtree that our depth/node budget exhausted before reaching.
Coordinate `clickAt` correctly refused in background (global event stream);
the missing piece was **semantic** hit-test actuation in **window**
coordinates without CDP.

Cursor Computer Use and Universal Automation already share the ADR 0064
contract: semantic verbs act below the focus layer. The gap was observation
fidelity and a window-scoped pointer path that maps to AXPress/setValue,
not `CGEvent` posts.

## Decision

1. **Web-first walks (macOS).** When `preferWebContent` is enabled (default
   on known browser bundle ids), snapshot walks locate an `AXWebArea` (or
   nested web document) and spend the node budget there first. Walk meta
   (`webRoot`, `webTrimmed`) rides on the snapshot root attributes.
2. **Window-local semantic pointer.** `ClickAtAction` with `windowId` maps
   window-local `(x, y)` to screen coordinates via window bounds, hit-tests
   with `AXUIElementCopyElementAtPosition`, verifies the element's pid
   matches the anchored session, then `AXPress` — no foreground, no global
   cursor move.
3. **Preview stream.** `automation_preview` polls `windowScreenshot` for a
   `windowId` and returns scaled PNG frames (`maxPx`, `intervalMs`) so
   agents observe background surfaces without stealing focus.
4. **Non-claims.** CDP still owns `evaluate`/DOM; apps without AX stay
   invisible; global-screen `clickAt` keeps the foreground contract; no
   floating PiP UI in v1.

## Consequences

- `xs_axdrv_snapshot_app_json` gains a `preferWebContent` flag (Dart FFI).
- `ClickAtAction` gains optional `windowId`.
- MCP: `preferWebContent` on observe; `windowId` on clickAt; new
  `automation_preview` tool.
- Evidence: `docs/evidence/os-ax-web-fidelity-2026-10-26/` and validation
  script under `pkgs/universal_driver_macos/validation/`.
