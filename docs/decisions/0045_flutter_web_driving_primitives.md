# ADR 0045: Flutter-web driving primitives — live-DOM name location, focus restoration, and the JIT/AOT tier matrix

- Status: Accepted
- Date: 2026-10-02
- Builds on: [ADR 0037](0037_universal_automation_family.md) (driver
  contract), [ADR 0040](0040_universal_driver_macos.md) (the macOS
  synthesis tier — the third leg of the tier matrix below), [ADR
  0044](0044_behavior_dynamics_contract.md) (behavior surface)

## Context

Driving a Flutter web app through real Chromium failed at every layer the
fakes covered (2026-10-02, multiplayer gate, 13 runs):

1. **Semantic clicks died with "detached".** Three stacked causes, only
   visible on real Chromium: `DOM.resolveNode` answers nothing usable
   without `DOM.enable` (the fake answered anyway); the AX node's
   `backendDOMNodeId` resolves to the layout TEXT node, not the element
   (`scrollIntoView is not a function`); and
   `Runtime.callFunctionOn` invokes with `this` bound correctly only for
   the OUTER function — a plain-called inner IIFE rebinds `this` to
   global.
2. **Flutter web replaces semantics DOM nodes continuously**, so a
   `backendDOMNodeId` from a fresh snapshot can be dead milliseconds
   later; polling a stale id forever reports `detached`.
3. **Background windows have no OS focus** — `Input.dispatchKeyEvent`
   events land nowhere (`document.hasFocus()` false); typing silently
   no-ops.
4. **Headless never runs requestAnimationFrame** — the Flutter app
   freezes mid-boot and its semantics DOM stalls entirely.
5. The presence probe `evaluate` swallowed a SyntaxError (a malformed
   `querySelectorAll` argument built by JS string concatenation) as a
   null — silent wrong answers from locator helpers must surface.

## Decision

`universal_browser_cdp` gains the measured-working primitives as
first-class API:

- **`DOM.enable` at attach** (domain prerequisite, documented).
- **`resolveNodeRect` probe hardening**: walk up from a text node to
  its element; capture `this` in the outer function.
- **`resolveNamedRect(name, {role, match})` / `hasNamedElement`**:
  locate by accessible name in the LIVE DOM (`flt-semantics` +
  `[aria-label]`/`[role]`, last match wins, role scopes first but never
  excludes — plain HTML carries roles implicitly). Selector built in
  Dart, passed as one escaped literal.
- **`bringToFront()` / `insertText()`** as first-class; `TypeAction`
  without a locator lowers to bringToFront + insertText (the caret
  path — per-key events require OS focus).
- **Semantic-click ladder** (`_clickSemantic`): per attempt — fresh
  snapshot → backend-node resolution → on failure the live-DOM named
  path (exact, then contains) → refusal with the locator named when
  absent everywhere.
- **`fieldValue` / `editableValues`**: the reliable field reads (AX
  `value` is unreliable across fields).
- **`cdp_live_chrome_test.dart`** (opt-in `XS_TEST_CDP_LIVE=1`): real
  Chromium conformance with a node-replacing fixture — the guard so
  this failure class cannot silently return. Fake-only suites are
  structurally blind to it.

### The tier matrix (JIT vs AOT)

| Target | Tier | Driver |
|---|---|---|
| Flutter web, JIT (DDC, `flutter run`) | VM service | flutter_mcp_toolkit (native refs, widget snapshots) |
| Flutter web, AOT (`flutter build web`) | Browser-level CDP | `CdpDriver` + the primitives here + `window.__mcpActions` |
| Desktop/mobile, JIT (debug) | VM service | flutter_mcp_toolkit |
| Desktop, AOT (release) | OS synthesis | ADR-0040 (CGEvent tier) |

Rule: **the toolkit speaks Dart; CDP speaks the browser; ADR-0040 speaks
the OS.** AOT web builds have no VM service — CDP is not a fallback
there, it is the ONLY tier. Apps that want typed intents on AOT web
publish `window.__mcpActions` handlers (the surface-actions registry —
plain JS interop, works in AOT); the mcp_toolkit catalog can project
onto it (tracked in mcp_flutter).

### Known sharp edge (documented, unfixed)

`Page.loadEventFired` carries no loaderId, so `navigate(load)` can
return on the PREVIOUS page's load event. Callers deep-linking must
wait for content (`hasNamedElement`) rather than navigation completion.

## Consequences

- Real-Chromium conformance is now a runnable gate (opt-in); the
  fake suite stays fast and hermetic.
- Semantic clicks survive Flutter-web semantics churn without app-side
  changes.
- The harness web tier (`WebBuildTarget` + `FlutterWebCdp`,
  mcp_flutter) composes on these primitives instead of re-rolling
  them.
