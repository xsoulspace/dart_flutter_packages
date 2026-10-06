# universal_browser_cdp

Pure-Dart Chrome DevTools Protocol (CDP) client: discovery, WebSocket
JSON-RPC, accessibility snapshots, intent-level input synthesis, and
screenshots. **No Flutter, no Node, no Java.**

Part of the `universal_automation_*` family
([ADR 0037](../../docs/decisions/0037_universal_automation_family.md)).

## Driving Flutter web (measured primitives)

Semantic clicks and typing on real Chromium + Flutter web need the
primitives added in
[ADR 0045](../../docs/decisions/0045_flutter_web_driving_primitives.md):

- `resolveNamedRect(name, {role, match})` / `hasNamedElement` — locate
  by accessible name in the LIVE DOM (`flt-semantics` included; last
  match wins, so dialogs beat page chrome). The semantic-click ladder
  falls back to this when Chromium's AX `backendDOMNodeId`s go stale —
  Flutter web replaces semantics nodes continuously.
- `bringToFront()` + `insertText()` — typing into a background window:
  per-key events land nowhere without OS focus (`document.hasFocus()`
  is false); click the field, bring to front, insert.
- `fieldValue(css)` / `editableValues()` — reliable field reads (the AX
  `value` is unreliable across several fields).
- Attach enables `DOM` (the `resolveNode` prerequisite the fake
  answers without — which hid the gap), and the node probe walks up
  from text nodes and captures `this` before any inner call.

Headless Chrome never runs requestAnimationFrame — Flutter web freezes
mid-boot; drive it headed (the harness's `ChromeAppTarget` disables
background throttling and defaults headed). After `navigate(load)`, wait
for CONTENT (`hasNamedElement`) — `Page.loadEventFired` carries no
loaderId and can belong to the previous page.

Conformance against real Chromium: `XS_TEST_CDP_LIVE=1 fvm dart test
test/cdp_live_chrome_test.dart` — a node-replacing fixture emulating
Flutter-web semantics churn. The fake-only suite is structurally blind
to this failure class.

## What it does

- `CdpDiscovery` — `/json/version` readiness probe (oka's borrowed-lease
  identity check) and `/json/list` target enumeration.
- `CdpConnection` — correlated JSON-RPC over WebSocket with a broadcast
  event stream.
- `CdpPage` — navigation (typed `errorText` failures, `loaderId`-matched
  main-frame wait), `Runtime.evaluate`, accessibility-tree snapshots
  mapped to the family's `AxNode` model, screenshots, and trusted input
  (hit-checked `Input.dispatchMouseEvent`/key events at resolved element
  rects). `detach()` leaves borrowed targets alive.
- `CdpDriver` / `CdpBrowserSession` — the observe/act/verify
  `AutomationDriver` over a page.
- `BehavioralCdpDriver` — the ADR
  [0044](../../docs/decisions/0044_behavior_dynamics_contract.md) lowering:
  profiled dispatch with planned-timestamp stamping, awaited serialized
  sends, reaction floors, navigation-gated interruption verdicts, and the
  receipt pair via `CdpBehaviorReceiptWriter`.
- Auto-wait: `navigate` takes `waitUntil`
  (`commit`/`load`/`domContentLoaded`/`networkIdle`); click/type poll the
  target to actionable (attached → visible → stable → hittable) with
  `timeout` + `force` escape hatches. Plain `type` emits real per-key
  events (non-ASCII lowers to IME-style insertion).
- Network observation: `page.network` — request lifecycle entries,
  statuses, in-flight counting, `responseBody(id)`; the counter behind
  `networkIdle`.
- Multi-tab: `CdpBrowser` — browser-level socket, flat sessions
  (`openPage`/`pages`/`attachFirstPage`/`closePage`); there is no
  active-page state — each page is an independent handle, and
  `switchTo(page)` returns that page's driver. Verbs only — whether to
  open or close targets stays oka's policy, and `close` never kills the
  browser.
- Semantic locators: snapshots carry `attributes['cdp.backendDOMNodeId']`;
  `ClickAction(role:, name:)` resolves a11y → DOM → hit-checked
  coordinates.
- `package:universal_browser_cdp/testing.dart` — a scriptable
  `FakeCdpServer` so consumers can test their pipelines without Chrome.

## Usage

```dart
// Production: take the endpoint oka published
// (session-<name>-handle / browser-debug-uri) — never spawn here.
final session = await CdpBrowserSession.attach(
  Uri.parse('http://127.0.0.1:9222'),
);
final driver = session.driver;
final snapshot = await driver.snapshot();
await driver.perform(ClickAction(css: '#submit'));
await driver.screenshot();
await session.close();
```

Auto-wait, network observation, multi-tab, semantic locators:

```dart
await page.navigate(uri, waitUntil: NavigateWait.networkIdle);
await page.click(css: '#submit', timeout: const Duration(seconds: 5));
await page.type('hello', css: '#q'); // real per-key events
final ok = page.network.requests
    .any((request) => request.url.endsWith('/api/save') && request.status == 200);

final browser = await CdpBrowser.connect(Uri.parse('http://127.0.0.1:9222'));
final tab = await browser.openPage(url: uri);
final driver = CdpDriver(tab);
await driver.perform(ClickAction(role: 'button', name: 'Submit'));
```

Profiled delivery (opt-in; plain `perform` is unchanged):

```dart
final driver = BehavioralCdpDriver(session.page);
final profile = BehaviorProfile.humanPrior(sessionSeed);
final outcome = await driver.performWith(
  ClickAction(css: '#submit'),
  profile,
  seed: sessionSeed, // omit in production: fresh entropy per dispatch
);
// outcome.verdict / .dispatched[i].driftUs — and receipts:
await CdpBehaviorReceiptWriter(directory: '/tmp/runs').write(
  profile: profile,
  seed: sessionSeed,
  driverId: 'cdp',
  transport: 'cdp',
  outcome: outcome,
);

## Non-claims

- Chromium-only (CDP). Firefox/WebKit need WebDriver — see
  `universal_browser_webdriver`.
- No lifecycle ownership: this package never launches or kills browsers.
- Web (dart2js/ddc) is not a target; the client requires `dart:io`.
