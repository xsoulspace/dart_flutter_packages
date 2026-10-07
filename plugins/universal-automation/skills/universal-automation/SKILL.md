---
name: universal-automation
description: >
  Drive browsers (CDP/WebDriver), native macOS/Windows/Linux apps, and
  Flutter surfaces through the universal_automation family: the
  observe/act/verify loop, declarative composable plans, intent routing,
  and humanized input dynamics (ADR-0044 behavior profiles). Use when a
  task needs UI automation, browser driving, plan-based testing, or
  app-intent invocation — via the `universal-automation` CLI or the
  `automation_*` MCP tools.
---

# Universal Automation Toolkit

One vocabulary for the observe/act/verify loop across browser and OS
tiers (ADR 0046). Attach-only: it never spawns or stops processes —
launch targets yourself (or use oka-published session handles) and point
the toolkit at the debug endpoint.

## MCP tools (when the plugin's server is mounted)

| Tool | Purpose |
| --- | --- |
| `automation_observe` | Semantic snapshot of a surface (read-only). |
| `automation_act` | One action: navigate/click/type/key/scroll/evaluate/invoke; optional `profile` for ADR-0044 humanized delivery. |
| `automation_verify` | Assert checks: `{exists: {role?, name?}}`, `{absent: …}`, `{value: {locator, equals/contains}}`, `{urlContains: s}`. |
| `automation_screenshot` | PNG to a local path. |
| `automation_validate_plan` | Fail-closed validation of a plan document. |
| `automation_run_plan` | Run a scenario; structured JSON report + behavior receipts. |

Every ad-hoc tool takes an `endpoint` (CDP HTTP base, e.g.
`http://127.0.0.1:9222`); without it the server uses its `--cdp` default.

## CLI

```bash
universal-automation observe  --cdp http://127.0.0.1:9222
universal-automation act      --cdp http://127.0.0.1:9222 --click-name Submit
universal-automation verify   --cdp http://127.0.0.1:9222 --exists role=button,name=Go
universal-automation screenshot --cdp http://127.0.0.1:9222 --out /tmp/s.png
universal-automation validate --plan plan.yaml
universal-automation run      --plan plan.yaml --scenario checkout --out /tmp/out
universal-automation serve    --cdp http://127.0.0.1:9222   # MCP stdio
```

Exit codes: 0 pass, 1 automation failure, 2 usage. Results are JSON on
stdout; errors go to stderr. Without the AOT binary, prefix with
`dart run` from `pkgs/universal_automation_toolkit/`.

## Declarative plans (the harness face)

Plans compose in **typed Dart** (primary — see
`pkgs/universal_automation_toolkit/lib/compose.dart` and
`example/showcase.dart`) and serialize to **YAML/JSON** for agents. Both
faces are the same values; one runner executes both.

```yaml
sessions:                      # attach-only bindings; oka owns lifecycle
  chrome: {transport: cdp, uri: 'http://127.0.0.1:9333'}
  staged: {transport: cdp, handle: session-staged-handle}  # resolved via --set staged=<uri>
profiles:                      # ADR-0044 behavior dynamics (canonical JSON)
  humanish:
    rhythm: {beforeAction: {kind: fixed, micros: 0}}
    reaction: {floorUs: 150000}
    pacing: {noiseEventGrid: 0, driftHourUs: 0}
    pointer:
      path: {kind: bezier, curvature: 12, overshootGrid: 300}
      moveDuration: {kind: fixed, micros: 120000}
      buttonHold: {kind: fixed, micros: 80000}
      maxStepPx: 24
    cadence:
      digraph: {kind: fixed, micros: 0}
      hold: {kind: fixed, micros: 0}
intents:                       # app-owned locators (intentcall hint shape)
  - app: page
    intents:
      - name: fill-email
        hint: {driver: cdp, action: type, locator: {css: 'input'}}
scenarios:
  buy:
    steps:
      - navigate: {url: 'https://example.com/'}      # lone verbs are act steps
      - wait: {checks: [{exists: {role: button, name: Buy}}], timeout: 5}
      - intent: {app: page, name: fill-email, args: {text: 'a@b.c'}}
      - act: {click: {name: Buy}, profile: humanish, seed: 42}
      - verify: [{exists: {role: heading, name: Thanks}}]
      - screenshot: shots/buy.png
```

Composition: `extends` (parent steps run first), `include` (file merge,
conflicts are violations). `run --set <handle>=<uri>` resolves handle
bindings. The report is structured JSON; profiled dispatches also write
ADR-0044 receipts (`*.behavior.stream.jsonl`, `*.behavior.receipts.jsonl`
— dispatch claims, not effect evidence).

## House rules and gotchas

- **Fail closed**: every plan violation is reported before anything
  attaches; capability gaps fail loudly, never silently degrade.
- **Borrowed sessions**: detaching never closes the target's process.
- Locators are semantic (`role`/accessible `name`) first — snapshots, not
  pixels; CSS is the fallback tier.
- For hermetic tests, compose against the family's fake CDP server
  (`package:universal_browser_cdp/universal_browser_cdp_testing.dart`).
- Deep links: `Page.loadEventFired` can be the previous page's — wait for
  content (`exists`/`urlContains`), not navigation completion.
