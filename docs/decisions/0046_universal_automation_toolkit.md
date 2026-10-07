# ADR 0046: `universal_automation_toolkit` — the family's agent surface (declarative plans, CLI, MCP)

- Status: Accepted
- Date: 2026-10-08
- North Star impact: `applies`
- Builds on: [ADR 0037](0037_universal_automation_family.md) (family,
  house rules), [ADR 0038](0038_automation_kernel_unification.md)
  (transport-from-engine rule), [ADR 0040](0040_universal_driver_macos.md)
  (OS tier), [ADR 0044](0044_behavior_dynamics_contract.md) (behavior
  profiles and receipts), [ADR 0045](0045_flutter_web_driving_primitives.md)
  (real-Chromium driving primitives)

## Context

The family's contracts and drivers are landed and conformant
(`AutomationDriver` observe/act/verify; CDP incl. the behavior lowering;
WebDriver; macOS AX; AT-SPI/UIA packages), but **no agent can call any of
it**:

- mcp_flutter's toolkit MCP exposes the instrumented Flutter tier only,
  and lives in another repo (ADR 0038 dependency direction).
- ZCode's built-in browser/computer-use plugins spawn their own sessions:
  no oka session handles, no behavior profiles, no fail-closed specs, and
  invisible to harness actors.
- Harness actors have no UI-control surface at all.

ADR 0038 already reserved the shape: engines own semantics, MCP and CLI
are *thin transports*. The missing piece is one transport over the
browser/OS tiers, owned by this repo. Second consumer rule is met (ZCode
clients and harness actors; plus oka-published session handles as the
lifecycle counterpart).

## Decision

New package `pkgs/universal_automation_toolkit` — pure Dart, no Flutter
surface, no process lifecycle. **One binary, two faces** (`bin/
universal-automation`):

0. **Composition is typed Dart code, primary** — the family's harness
   grammar, following the mcp_flutter harness (steps composed in Dart
   over a context) and oka (declarative typed specs) precedent and
   flutter's own builder shape: scenarios are lists of typed step values
   built with a lowercase grammar (`navigate`, `click`, `typeText`,
   `verifyThat`, `waitFor`, `intent`), scenario composition is Dart
   (`scenario('b').extend('a')`, loops, helpers). YAML/JSON documents are
   the **wire form of the same values** for agents and MCP — parsed into
   identical `PlanStep`/`VerifyCheck` values, executed by one runner. No
   second engine, no closure/AST split.
1. **Declarative plans** (`AutomationPlan`, a fail-closed value):
   - `sessions` — named **attach-only** endpoint bindings (transport +
     direct URI or oka-style handle name); the toolkit never spawns or
     stops anything (ADR 0037 house rule 2);
   - `profiles` — named [ADR 0044](0044_behavior_dynamics_contract.md)
     `BehaviorProfile`s (typed in Dart, canonical JSON on the wire);
   - `intents` — named app intents carrying an `IntentHint` (the
     intentcall `IntentAutomationHint` contract shape: driver transport,
     verb, locator), loadable in Dart or from an intentcall-exported
     manifest — the WHAT/HOW split of ADR 0038 landed: apps own their
     locators, plans reference intents by name and survive UI refactors;
   - `scenarios` — ordered steps (`observe`, `act`, `verify`, `wait`,
     `screenshot`, `intent`), each naming its session and optionally a
     profile + seed; a scenario may `extend` one parent (steps concat);
     a document may `include` other documents (maps merge).
   Validation is pure and fail-closed: every violation is collected and
   thrown before anything attaches (`SpecViolationException`) — intent
   steps are validated eagerly by lowering their hints.
2. **Runner** producing a structured `RunReport` (JSON, per-step status,
   timings, snapshot digests) and, for profiled dispatches, the ADR 0044
   receipt pair (`*.behavior.stream.jsonl` / `*.behavior.receipts.jsonl`
   via `CdpBehaviorReceiptWriter`). Receipts claim dispatch, never effect.
3. **CLI verbs** mirroring the driver contract for ad-hoc use:
   `observe`, `act`, `verify`, `screenshot`, `run`, `validate`, `serve`.
   Documents only; Dart-composed plans run through a three-line runner
   call (see the showcase).
4. **MCP stdio server** (`serve`): newline-delimited JSON-RPC 2.0, tools
   `automation_observe`, `automation_act`, `automation_verify`,
   `automation_screenshot`, `automation_validate_plan`,
   `automation_run_plan`; tools-only server (no resources/prompts in v1).
   The default endpoint comes from `--cdp`; tools accept a per-call
   endpoint override so one server serves any reachable browser.
5. **Transport registry**: v1 links the CDP tier
   (`universal_browser_cdp`, including `BehavioralCdpDriver` when a step
   declares a profile). Other transports are named in plans and fail at
   resolution with a loud `TransportNotLinkedException` — plan format
   stays stable while WebDriver/OS/VM-service tiers link in.
6. **Installable plugin with skills**: a ZCode plugin that carries the
   SKILL.md usage guide and the MCP registration, so any client installs
   the whole surface in one step; harness actors call the same binary via
   the installed-tool allowlist (`tool_action`).
7. **Showcase**: an `example/` Dart plan over the family's fake CDP
   server — the mcp_flutter showcase-drives precedent — proving the Dart
   composition face and the runner end-to-end; it doubles as the
   executable documentation agents read.

## Consequences

- Agents get one vocabulary (snapshot/action/verify + behavior profiles +
  receipts) across browser and, later, OS tiers — the ADR 0038 promise,
  landed for the non-Flutter tiers.
- oka stays the lifecycle owner: plans reference `session-<name>`-style
  bindings; the toolkit attaches and reports, never owns.
- The plugin makes adoption zero-config for MCP clients; the CLI path
  keeps harness actors (no native MCP) first-class.

## Non-claims

- The intent layer is contract-shaped (the `IntentAutomationHint` JSON
  shape), not a package dependency: `universal_automation_toolkit` does
  not depend on intentcall packages; manifest files exported by
  intentcall parse verbatim. A typed adapter may link later.
- v1 links the CDP tier only; `webdriver`, `osAccessibility`, and
  `vmService` transports resolve to loud failures until their binding
  lands.
- No OS-tier AOT proof: `dart compile exe` silently drops native code
  assets, so once the OS tier links, the binary must build via
  `dart build cli` — untested in this ADR (v1 is pure Dart).
- MCP surface is tools-only; resources/prompts/sampling are future work.
- Plan validation cannot check driver capabilities (no attach at validate
  time); capability mismatches surface at run time as loud failures.
- No hot-reload story for Flutter apps (grep-verified family gap, ADR
  0038 leaves the instrumented tier to mcp_flutter's toolkit).
