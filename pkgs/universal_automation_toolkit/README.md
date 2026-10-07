# universal_automation_toolkit

The agent-facing surface of the `universal_automation_*` family
([ADR 0046](../../docs/decisions/0046_universal_automation_toolkit.md)):
**one binary, two faces** — a declarative harness composed in typed Dart
(or serialized as YAML/JSON for agents), executed by a fail-closed
runner, exposed as a CLI and as an MCP stdio server.

Part of the `universal_automation_*` family
([ADR 0037](../../docs/decisions/0037_universal_automation_family.md)):

- `universal_automation_interface` — the driver contracts this drives.
- `universal_browser_cdp` — the linked v1 transport tier.
- `universal_automation_conformance` — the family suites.

## What this package fixes

- Agents (ZCode, harness actors, IDE clients) could not call any family
  driver: this is the thin transport ADR 0038 reserved.
- Plans compose **as Dart code** (the mcp_flutter harness / oka
  precedent) and serialize to documents — same values, one runner, no
  second engine.
- App intents ([ADR 0038](../../docs/decisions/0038_automation_kernel_unification.md)
  hints) let apps own their locators; plans reference `intent` steps and
  survive UI refactors.
- Behavior profiles ([ADR 0044](../../docs/decisions/0044_behavior_dynamics_contract.md))
  dispatch actions with declared input dynamics and write receipts.

## Usage

```dart
import 'package:universal_automation_toolkit/compose.dart';
import 'package:universal_automation_toolkit/universal_automation_toolkit.dart';

final plan = AutomationPlan(
  sessions: [cdp('browser', uri: Uri.parse('http://127.0.0.1:9222'))],
  scenarios: [
    scenario('checkout', steps: [
      navigate(Uri.parse('https://example.com/cart')),
      waitFor([exists(role: 'button', name: 'Checkout')]),
      typeText('a@b.c', css: '#email'),
      click(name: 'Checkout', profile: 'humanPrior', seed: 42),
      verifyThat([absent(name: 'Error')]),
      shot('/tmp/checkout.png'),
    ]),
  ],
);
final report = await PlanRunner().run(plan, scenarioName: 'checkout');
```

The same plan as a document (agent wire form): see
`example/showcase.dart` and the test fixtures. CLI:

```bash
dart run bin/universal_automation.dart run --plan plan.yaml --scenario checkout
dart run bin/universal_automation.dart serve --cdp http://127.0.0.1:9222  # MCP
```

Build note: once a native tier links in, build the binary with
`dart build cli` — `dart compile exe` silently drops native code assets.

## Non-claims

- v1 links the CDP tier only; `webdriver`, `osAccessibility`, and
  `vmService` bindings resolve to loud `TransportNotLinkedException`s.
- The toolkit never spawns or stops processes (attach-only; lifecycle
  belongs to oka) and performs no I/O beyond the driven surfaces.
- The intent layer is contract-shaped (intentcall hint JSON), not a
  package dependency.
- MCP surface is tools-only; resources/prompts/sampling are future work.
