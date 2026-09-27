# universal_browser_cdp

Pure-Dart Chrome DevTools Protocol (CDP) client: discovery, WebSocket
JSON-RPC, accessibility snapshots, intent-level input synthesis, and
screenshots. **No Flutter, no Node, no Java.**

Part of the `universal_automation_*` family
([ADR 0037](../../docs/decisions/0037_universal_automation_family.md)).

## What it does

- `CdpDiscovery` — `/json/version` readiness probe (oka's borrowed-lease
  identity check) and `/json/list` target enumeration.
- `CdpConnection` — correlated JSON-RPC over WebSocket with a broadcast
  event stream.
- `CdpPage` — navigation, `Runtime.evaluate`, accessibility-tree snapshots
  mapped to the family's `AxNode` model, screenshots, and trusted input
  (`Input.dispatchMouseEvent`/`insertText` at resolved element rects).
- `CdpDriver` / `CdpBrowserSession` — the observe/act/verify
  `AutomationDriver` over a page.
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

## Non-claims

- Chromium-only (CDP). Firefox/WebKit need WebDriver — see
  `universal_browser_webdriver`.
- No lifecycle ownership: this package never launches or kills browsers.
- Web (dart2js/ddc) is not a target; the client requires `dart:io`.
