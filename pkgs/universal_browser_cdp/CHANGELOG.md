# Changelog

## Unreleased

- ADR 0045: Flutter-web driving primitives — `DOM.enable` at attach,
  semantic-click ladder with live-DOM name fallback
  (`resolveNamedRect`/`hasNamedElement`), node-probe hardening
  (text-node walk-up, `this` capture), `bringToFront`/`insertText`,
  `fieldValue`/`editableValues`, `TypeAction` without a locator lowers
  to caret insertion, and an opt-in real-Chromium conformance fixture
  (`XS_TEST_CDP_LIVE=1`).
## 0.2.0

- **Surface action registry (ADR-0017 invoke tier)**: `CdpDriver`
  implements `AutomationActionCatalog` over the page's
  `window.__mcpActions` convention — any web surface (Jaspr, plain JS,
  Flutter web) publishes named `{description, schema, invoke(args)}`
  handlers and the driver lists and invokes them; async handlers are
  awaited, JS rejections surface as `ProtocolException`. New
  `CdpPage.evaluateAsync` awaits Promise results with
  `exceptionDetails` surfaced.
- **Behavior dynamics lowering (ADR 0044)**: `BehavioralCdpDriver`
  (`capabilities.behaviorDynamics`) with the client-side scheduler —
  planned-timestamp stamping on every dispatch, serialized awaited sends,
  navigation-gated truncation with typed `BehaviorOutcome` verdicts;
  reaction-floor enforcement against the last observation; loud
  `DriverUnsupportedException` for session pacing the lowering cannot
  honor yet. Receipt pair writer (`CdpBehaviorReceiptWriter`) mirroring
  the screencast recording contract.
- **Navigate correctness**: `Page.navigate` failures surface as
  `ProtocolException` via the response's `errorText` instead of hanging
  the wait; the wait matches the navigation's `loaderId` and ignores
  subframe events; the timeout is a parameter (default 30s).
- **Hit-checked input resolution**: `CdpPage.resolveRect` scrolls the
  element into view and verifies the center point hits the element (or a
  descendant) before any dispatch — occluded elements refuse loudly
  instead of missing silently.
- **Borrowed-lease teardown**: `CdpPage.detach` / `CdpBrowserSession.detach`
  close only the client socket, leaving adopted targets alive.
- `CdpDriver` declares an explicit capability set (no longer reuses
  `DriverCapabilities.full`); plain drivers keep `behaviorDynamics: false`.
- **Auto-wait**: `NavigateWait` enum on `navigate`
  (`commit`/`load`/`domContentLoaded`/`networkIdle` — networkIdle rides
  the new network log); actionability polling (attached → visible →
  stable → hittable) inside `click`/`type`/`resolveRect` with `timeout`
  and `force` parameters; `clickAt(x, y)` explicit-point dispatch.
- **Network observation**: `CdpPage.network` (`CdpNetworkLog`) — request
  lifecycle entries with redirect folding, statuses, in-flight counting,
  `responseBody(id)`, `waitIdle()`.
- **Multi-tab**: `CdpBrowser` over the browser-level socket —
  `openPage`/`attachTarget`/`attachFirstPage`/`pages`/`closePage` via CDP
  flat sessions (`CdpFlatSession`); `Target.targetDestroyed` marks pages
  closed; `close()` only drops the client socket (borrowed-lease
  discipline). `CdpPage` now speaks the `CdpTransport` surface (dedicated
  socket or flat session).
- **Semantic locators**: snapshots keep `backendDOMNodeId` in
  `attributes['cdp.backendDOMNodeId']`; `ClickAction(role:, name:)`
  resolves through the semantic index (`DOM.resolveNode` +
  hit-checked coordinates) — no more "css selector required" refusal.
- Depends on `universal_automation_interface` ^0.2.0.
