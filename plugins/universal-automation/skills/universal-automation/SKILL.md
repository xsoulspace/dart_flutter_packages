---
name: universal-automation
description: >
  Drive browsers (CDP/WebDriver), native macOS/Linux/Windows apps, and
  Flutter surfaces through the universal_automation family: the
  observe/act/verify loop, declarative plans composed as typed Dart
  (YAML snapshots for agents), intent routing, screencast recording, and
  humanized input dynamics (ADR-0044 behavior profiles). Use when a task
  needs UI automation, browser driving, plan-based testing, or
  app-intent invocation — via the `universal-automation` CLI, the
  `automation_*` MCP tools, or a Dart plan file.
---

# Universal Automation Toolkit

One vocabulary for the observe/act/verify loop across browser and OS
tiers (ADR 0046). Attach-only: it never spawns or stops processes —
launch targets yourself (or point at oka-published session handles) and
aim the toolkit at the debug endpoint.

**Dart is the source of truth; YAML/JSON documents are snapshots** (the
agent interchange). Code steps make plans first-class code: terminal
commands, oka calls, arbitrary checks.

## Linked tiers

| Tier | Transport | Notes |
| --- | --- | --- |
| Chromium / Flutter web AOT | `cdp` | snapshots, semantic clicks, profiles, `record` |
| Safari / WebDriver ends | `webdriver` | actions + screenshots; no a11y tree |
| macOS apps | `osAccessibility` | focused app; Accessibility (+Screen Recording) TCC |
| Linux apps | `osAccessibility` | session D-Bus AT-SPI |
| Windows apps | `osAccessibility` | UIA sidecar binary; loud elsewhere |
| Flutter JIT (debug) | `vmService` | inject `DriverFactory` (composition root) |

## MCP tools (plugin server mounted)

| Tool | Purpose |
| --- | --- |
| `automation_observe` | Semantic snapshot of a surface (read-only). Pass `view` (`{subtreeOf, identifierPrefix, fields, maxNodes, panes}`) for a rendered, ref-stable observation instead of the raw tree; `diff: true` adds +/-/~ rows against the previous viewed observation (ADR 0052). |
| `automation_act` | navigate/click/type/key/scroll/evaluate/invoke; optional `profile` (ADR-0044 humanized delivery) + `seed`; `returnState: true` attaches the post-action state render — act + observe in one call. |
| `automation_verify` | Checks: `{exists: {role?, name?}}`, `{absent: …}`, `{value: {locator, equals/contains}}`, `{urlContains: s}`. |
| `automation_screenshot` | PNG to a local path (opt-in pixels; the semantic channel is primary). |
| `automation_validate_plan` | Fail-closed snapshot validation. |
| `automation_run_plan` | Run a scenario; structured JSON report + receipts. |

Ad-hoc tools take a `transport` (`cdp | webdriver | osAccessibility`)
plus an `endpoint` (HTTP base); `osAccessibility` is the desktop tier —
it binds the **focused application** and needs no endpoint. Without
arguments the server uses its `serve` default (`--cdp <base>`, or
`--os` for the desktop tier).

## The loop (semantic-first)

Observe through a `view`, act with `returnState`, verify — the agent
reads refs and deltas, not pixels. Each rendered node carries a stable
`ref`; `diff: true` returns only what changed. Screenshots are opt-in
enrichment, and coordinates are the fallback tier (canvas, games,
surfaces no accessibility tree can see), not the primary path.

## Dart plans (primary)

```dart
final plan = AutomationPlan(
  sessions: [
    cdp('browser', uri: Uri.parse('http://127.0.0.1:9222')),
    SessionBinding(name: 'mac', transport: AutomationTransport.osAccessibility),
  ],
  profiles: {'humanish': BehaviorProfile.humanPrior(7)},
  intents: IntentRegistry.fromFiles(['app.intents.json']),
  scenarios: [
    scenario('checkout', steps: [
      navigate(Uri.parse('https://example.com/cart')),
      waitFor([exists(role: 'button', name: 'Checkout')]),
      intent('app', 'fill-email', args: {'text': 'a@b.c'}),
      click(name: 'Checkout', profile: 'humanish', seed: 42),
      exec('flutter', args: ['test']),                    // terminal step
      code((context) async => {'oka': 'call anything'}),  // first-class code
      verifyThat([absent(name: 'Error')]),
      record(const Duration(seconds: 2), '/tmp/out'),      // screencast
      shot('/tmp/cart.png'),
    ]),
  ],
);
final report = await PlanRunner().run(plan, scenarioName: 'checkout');
```

Snapshot export (for agents; refuses code steps):
`planDocument(plan)` → YAML/JSON.

## CLI (snapshots + ad-hoc)

```bash
universal-automation observe  --cdp http://127.0.0.1:9222
universal-automation act      --cdp http://127.0.0.1:9222 --click-name Submit
universal-automation verify   --cdp http://127.0.0.1:9222 --exists role=button,name=Go
universal-automation actions  --cdp http://127.0.0.1:9222
universal-automation screenshot --cdp http://127.0.0.1:9222 --out /tmp/s.png
universal-automation run      --plan plan.yaml --scenario checkout --out /tmp/out
universal-automation run      --plan plan.yaml --handles-dir ~/.oka/handles
universal-automation serve    --cdp http://127.0.0.1:9222   # MCP stdio
universal-automation serve    --http 8931                    # MCP POST /mcp

# Desktop tier (focused app; macOS AX / Linux AT-SPI / Windows UIA):
universal-automation observe  --os
universal-automation act      --os --click-name New\ Folder
universal-automation serve    --os                           # MCP over the desktop tier
```

Exit codes: 0 pass, 1 automation failure, 2 usage. Results are JSON on
stdout. Without the binary on PATH, the plugin launcher falls back to
`dart run` from the package (`plugins/universal-automation/install.sh`
builds and symlinks the AOT binary — `dart build cli` is mandatory once
a native tier is linked; `dart compile exe` silently drops native code
assets).

## House rules and gotchas

- **Fail closed**: every plan violation is reported before anything
  attaches; capability gaps fail loudly, never silently degrade.
- **Borrowed sessions**: detaching never closes the target's process.
- Locators are semantic (`role`/accessible `name`) first; CSS is the
  fallback tier. `wait` instead of sleeps — deep links may resolve on
  the previous page's load event.
- macOS tier needs the Accessibility TCC grant for the *host process*
  (the MCP client or terminal that spawned the binary).
- Multi-session scenarios: `onSession('name', steps)` or per-step
  `session:`; handle bindings resolve via `--set name=uri` or handle
  artifacts under `--handles-dir`.
- For hermetic tests, compose against the family's fake CDP server
  (`package:universal_browser_cdp/universal_browser_cdp_testing.dart`).
