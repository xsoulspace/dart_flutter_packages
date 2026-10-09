# universal_automation_toolkit

The agent-facing surface of the `universal_automation_*` family
([ADR 0046](../../docs/decisions/0046_universal_automation_toolkit.md)):
declarative automation **composed as typed Dart** — the primary,
executable surface — with a fail-closed runner, an MCP server (stdio +
loopback HTTP), and a CLI that runs plan **snapshots** (YAML/JSON, the
interchange form for agents and existing scattered configs).

Part of the `universal_automation_*` family
([ADR 0037](../../docs/decisions/0037_universal_automation_family.md)).

## Tier matrix (what is linked)

| Tier | Transport | Status |
| --- | --- | --- |
| Chromium / Flutter web (AOT) | CDP (`universal_browser_cdp`) | **linked** — snapshots, semantic clicks, behavior profiles, screencast |
| Safari / any WebDriver end | W3C WebDriver (`universal_browser_webdriver`) | **linked** — actions + screenshots; no a11y tree (protocol has none) |
| macOS apps | AX/CGEvent (`universal_driver_macos`) | **linked** — focused app; needs Accessibility (+Screen Recording) TCC |
| Linux apps | AT-SPI2 (`universal_driver_linux`) | **linked** — D-Bus session bus |
| Windows apps | UIA sidecar (`universal_driver_windows`) | **linked** — needs the sidecar binary; refuses loudly elsewhere |
| Flutter JIT (debug) | VM service (`ToolkitDriver`, mcp_flutter) | via **injected `DriverFactory`** (ADR 0036 direction) — `SessionRegistry.registerFactory` |
| Screencast plane | `universal_screencast` | **linked** for CDP (`record` step → `.mjpeg` + receipts) |

Untested builds are not proof: Linux/Windows paths run their family
packages' own fakes in CI here, live proof is platform-bound.

## Dart is the source of truth

Compose plans as typed values — including **code steps**: terminal
commands, oka calls, arbitrary checks. Anything a document cannot
express is ordinary Dart inside the scenario.

```dart
import 'dart:convert';
import 'package:universal_automation_toolkit/compose.dart';
import 'package:universal_automation_toolkit/universal_automation_toolkit.dart';

final plan = AutomationPlan(
  sessions: [
    cdp('browser', uri: Uri.parse('http://127.0.0.1:9222')),
    cdp('staged', handle: 'session-staged-handle'), // oka artifact / --set
    SessionBinding(name: 'mac', transport: AutomationTransport.osAccessibility),
  ],
  profiles: {'humanish': BehaviorProfile.humanPrior(7)},
  intents: IntentRegistry.fromFiles(['webshop.intents.json']),
  scenarios: [
    scenario('checkout', steps: [
      navigate(Uri.parse('https://example.com/cart')),
      waitFor([exists(role: 'button', name: 'Checkout')]),
      intent('webshop', 'fill-email', args: {'text': 'a@b.c'}),
      click(name: 'Checkout', profile: 'humanish', seed: 42),
      exec('flutter', args: ['test', '--tags', 'checkout']),
      code((context) async {
        // anything: oka, processes, custom assertions
        return {'oka': 'hands off'};
      }),
      verifyThat([absent(name: 'Error')]),
      record(const Duration(seconds: 2), '/tmp/out'),
      shot('/tmp/cart.png'),
    ]),
  ],
);
final report = await PlanRunner(
  handleBaseDirectory: '~/.oka/handles',
).run(plan, scenarioName: 'checkout');

// Snapshot for agents (refuses to export code steps — they are
// Dart-only by design):
print(const JsonEncoder.withIndent('  ').convert(planDocument(plan)));
```

Run it as an ordinary Dart program (`dart run tool/checkout_plan.dart`) —
the showcase (`example/showcase.dart`) is the reference. Tests drive
composed plans directly under `dart test` against the family's fake CDP
server.

## Snapshots (YAML/JSON) and the CLI

Snapshots are the interchange for agents and MCP — never the source of
truth. Agents author or consume them; humans export them from Dart.

```bash
dart run bin/universal_automation.dart validate --plan plan.yaml
dart run bin/universal_automation.dart run --plan plan.yaml --out /tmp/out
dart run bin/universal_automation.dart actions --cdp http://127.0.0.1:9222
dart run bin/universal_automation.dart serve --cdp http://127.0.0.1:9222   # MCP stdio
dart run bin/universal_automation.dart serve --http 8931                   # MCP POST /mcp
```

Every ad-hoc verb (`observe`, `act`, `verify`, `screenshot`, `actions`)
and `serve` picks a transport: `--cdp <http-base>` (default face),
`--webdriver <http-base>`, or `--os` — the desktop accessibility tier of
the host (macOS AX focused app / Linux AT-SPI / Windows UIA;
endpoint-free). Over MCP, `serve --os` makes `automation_observe` and
friends drive the focused application, and every tool accepts a
per-call `transport` override (`cdp | webdriver | osAccessibility`):

```bash
dart run bin/universal_automation.dart observe --os            # focused app tree
dart run bin/universal_automation.dart serve --os              # MCP over the desktop tier
dart run bin/universal_automation.dart observe --os \
  --view-max 40 --view-fields role,name,value                  # rendered view + refs
dart run bin/universal_automation.dart act --os \
  --click-name "New Folder" --return-state                     # act + closing read
```

Native-tier runs need the native asset built: use `dart run` or the
AOT bundle, not a bare `dart bin/...` invocation.

MCP tools: `automation_observe/act/verify/screenshot/validate_plan/
run_plan`. Behavior receipts (ADR 0044) and screencast artifacts
(`.mjpeg` + `.meta.jsonl`) land under `--out`.

## Semantic views (ADR 0052)

The observe/act loop's economics live in
[`universal_automation_semantics`](../universal_automation_semantics/):
views declare what an observation keeps, observations issue full-walk
refs, diffs close the loop. Three calling shapes compose the same
values:

```dart
final plan = AutomationPlan(
  sessions: [cdp('browser', uri: Uri.parse('http://127.0.0.1:9222'))],
  scenarios: [
    scenario('loop', steps: [
      observe(view: const SemanticView(maxNodes: 120)),  // rendered + refs
      click(name: 'Buy', returnState: true),             // act + closing read
      scope(                                             // view-scoped tree
        const SemanticView(subtreeOf: 's_1'),
        [click(name: 'Checkout'), verifyThat([absent(name: 'Error')])],
      ),
    ]),
  ],
);
```

Over MCP the same values ride `automation_observe` arguments
(`view`, `diff: true`) and `automation_act` (`returnState: true`) —
one schema across Dart, plan documents, and MCP.

**Grounding** (ADR 0053): `observe(at: (x, y))` names the innermost
walked node whose bounds contain the point — bounds grounding from the
tree's own geometry, fail-closed on a miss (reobserve, never guess).
MCP `automation_observe` takes the same `at` object; the CLI takes
`--at x,y`. Pixel grounding (screenshot → coordinates) stays
client-side.

**Coordinate verbs + chords** (ADR 0053): `clickAt(x, y)`/`moveTo`/
`dragTo` cover surfaces no tree can see; `modifiers: ['shift']`… hold
a chord through clicks, drags, and keys. CDP, macOS (CGEvent), and
WebDriver (W3C pointer actions) implement them — plain and under
behavior profiles (a drag is a bezier gesture, not a teleport);
Linux/Windows refuse loudly until their synthetic-input sidecars land.
CLI: `--click-at`/`--move-to`/`--drag` with `--button`/`--click-count`/
`--modifier`.

**Intent view hints**: an intent hint may carry a `view` (the family
view grammar verbatim). The runner observes through it after the
action dispatch — the app declares how its effect should be read, and
the step result carries the render (`state`).

**Screenshots** are opt-in enrichment: `automation_screenshot` writes
the PNG and, with `image: true`, attaches it as an image content block
(`maxPx` caps the long side; window-scoped capture via `windowId` /
`listWindows` on the OS tier, needing Screen Recording consent — a
different TCC grant than Accessibility, surfaced as its own typed
exception). CLI: `screenshot --list-windows` / `--window-id` /
`--max-px`.

Build note: the AOT binary **must** use `dart build cli` —
`dart compile exe` silently drops the native code assets (the macOS
driver dylib). `plugins/universal-automation/install.sh` builds and
symlinks it.

## Non-claims

- The Flutter JIT tier binds through injected factories from
  composition roots (mcp_flutter); no shipped binary drives it OOTB.
- Live proof exists for macOS/CDP tiers; Linux/Windows bindings are
  wired against their family packages (pure Dart) with live proof
  platform-bound.
- The intent layer is contract-shaped (intentcall hint JSON), not a
  package dependency; intentcall's export path is unverified end-to-end.
- MCP surface is tools-only; the HTTP transport binds loopback only.
