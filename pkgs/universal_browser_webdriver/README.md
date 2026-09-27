# universal_browser_webdriver

Pure-Dart W3C WebDriver client with a `safaridriver` endpoint adapter —
Safari automation with **no Java and no Node**.

Part of the `universal_automation_*` family
([ADR 0037](../../docs/decisions/0037_universal_automation_family.md)).

## What it does

- `WebDriverClient` — classic WebDriver over HTTP: sessions, navigation,
  element lookup (`css selector`, `xpath`, `link text`, …), clicks,
  typing, key actions, screenshots. Error envelopes map onto the family's
  typed exceptions.
- `WebDriverDriver` — the family's observe/act/verify contract over a
  session. Honest capability: classic WebDriver has no a11y-tree
  endpoint, so `a11yTree` is `false` and `snapshot()` refuses loudly.
- `SafariDriverEndpoint` — spawns/supervises `safaridriver -p <port>`
  and waits for `/status`. One-time setup: `safaridriver --enable`.
- `package:universal_browser_webdriver/testing.dart` — a scriptable
  fake remote end for consumers' tests.

## Usage

```dart
final endpoint = await SafariDriverEndpoint.spawn(port: 7051);
final driver = WebDriverDriver(endpoint.client);
await driver.perform(NavigateAction(Uri.parse('https://example.test')));
final png = await driver.screenshot();

// Attaching to an externally owned driver (oka publishes the URI):
final client = WebDriverClient(Uri.parse('http://127.0.0.1:7051'));
await client.newSession(capabilities: {'browserName': 'safari'});
```

## Non-claims

- No WebDriver BiDi yet (declared follow-up; CDP covers Chromium).
- No accessibility-tree snapshots: that is the OS-native tier
  (`universal_capture_macos`), not classic WebDriver.
- `snapshot()` intentionally throws — a silent empty tree would be worse.
