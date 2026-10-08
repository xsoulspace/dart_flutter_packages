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

0. **Composition is typed Dart code, primary — and first-class code** —
   the family's harness grammar, following the mcp_flutter harness and
   oka precedent and flutter's own builder shape: scenarios are lists of
   typed step values built with a lowercase grammar (`navigate`,
   `click`, `typeText`, `verifyThat`, `waitFor`, `intent`, `record`,
   `code`/`exec`), scenario composition is ordinary Dart. **Code steps**
   carry closures — terminal commands (`exec`), oka calls, arbitrary
   checks — everything a document cannot express; they are Dart-only by
   design and cannot cross the snapshot boundary. YAML/JSON documents
   are **snapshots** (the interchange for agents, MCP, and existing
   scattered configs) via `planDocument(plan)`, which refuses to export
   code steps; parsed snapshots become identical step values executed by
   the one runner. No second engine, no closure/AST split.
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
4. **MCP server** (`serve`): newline-delimited JSON-RPC 2.0 over stdio,
   or loopback HTTP (`serve --http <port>`; `POST /mcp`, one JSON
   response per request — the stateless shape of the streamable-HTTP
   transport) for clients that cannot spawn processes (ChatGPT
   connectors). Tools `automation_observe`, `automation_act`,
   `automation_verify`, `automation_screenshot`,
   `automation_validate_plan`, `automation_run_plan`; tools-only server.
   The default face comes from `--cdp`, `--webdriver`, or `--os` (the
   endpoint-free desktop tier — macOS AX binds the focused
   application); tools accept a per-call `endpoint` + `transport`
   override, so one server serves any reachable browser or the focused
   desktop app.
5. **Transport registry**: injectable `DriverFactory` per transport;
   built-ins link the CDP tier (incl. `BehavioralCdpDriver`), W3C
   WebDriver, and the OS-native tier (macOS AX focused-app —
   endpoint-free binding; Linux AT-SPI over the session D-Bus; Windows
   UIA sidecar, refusing loudly off Windows). The macOS native-assets
   hook no-ops off-Darwin, so one binary builds everywhere (AOT via
   `dart build cli` only). `vmService` (the instrumented Flutter tier,
   `ToolkitDriver` in mcp_flutter) resolves through registered
   factories — composition roots link it without reversing ADR 0036's
   dependency direction; unregistered transports fail loudly with
   `TransportNotLinkedException`. Surface-action discovery (`actions`
   verb) exposes a driver's `AutomationActionCatalog`; handle bindings
   resolve from `--set` overrides or `session-<name>-handle` artifacts
   under a handles directory (oka's publish convention). The screencast
   plane lands as a `record` step (CDP → `FileRecorderSink`:
   `.mjpeg` + receipt manifest).
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
- Live proof is platform-bound: macOS + CDP are live-proven; the
  Linux/Windows bindings are wired against their pure-Dart family
  packages and proven through those packages' fakes, not live sessions.
- The Flutter JIT tier ships no OOTB binding (composition-root
  injection only); `SessionPacing` remains CDP-refused (ADR 0044 v1).
- No OS-tier AOT proof: `dart compile exe` silently drops native code
  assets, so once the OS tier links, the binary must build via
  `dart build cli` — untested in this ADR (v1 is pure Dart).
- MCP surface is tools-only; resources/prompts/sampling are future work.
  The HTTP transport binds loopback only; exposing it beyond localhost
  (ChatGPT connectors require a public HTTPS origin) is a deliberate
  fronting/tunneling decision with auth, not part of this package.
- Plan validation cannot check driver capabilities (no attach at validate
  time); capability mismatches surface at run time as loud failures.
- No hot-reload story for Flutter apps (grep-verified family gap, ADR
  0038 leaves the instrumented tier to mcp_flutter's toolkit).
