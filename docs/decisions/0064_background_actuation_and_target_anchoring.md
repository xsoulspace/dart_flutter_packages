# ADR 0064: Background actuation and target anchoring — the focus contract, the semantic write path, and the resident job plane

Date: 2026-10-12
Status: Accepted and implemented (2026-10-12)
Related: 0044 (behavior composition), 0046 (toolkit one-runner), 0052
(semantic snapshots, images opt-in), 0053 (coordinate verbs, "coordinates
last"), 0038 (mcp_flutter dependency direction)

## Context

Codex and ChatGPT run automations that never need app focus or synthetic
pointer clicks, and the mechanism is not better clicking — it is
architecture. Three separable designs:

1. **Codex: execution/control-plane split.** `codex app-server` is a
   long-lived daemon hosting agent sessions; the desktop app and IDE
   extension are thin JSON-RPC clients. The agent's effectors are shell,
   files, and APIs — zero GUI events are synthesized, so focus is not a
   variable. Background "connection" = resident process + task queue.
2. **ChatGPT Work with Apps: accessibility read, nothing more** — the
   macOS AX API for reading app context; actuation happens elsewhere.
3. **ChatGPT Agent mode: virtualized display** — a cloud browser VM;
   focus exists inside the VM, the user's desktop is untouched.

The unifying principle: **focus is a property of event routing, not of
the task.** An automation needs focus only if it injects into the global
event stream. There are exactly four escape routes: drive an API below
the UI; act below the focus layer (AX actions, pid-scoped events);
virtualize the display; decouple execution from the UI process
(resident daemon + queue).

Our desktop tier could already *read* any app in background
(`snapshotOfApp(pid)`, `windows(pid)`, occlusion-tolerant
`windowScreenshot`) and could *press* AX elements (`bridge.press` =
AXPress, which does not require focus). But the tier was
focus-anchored at every layer above the driver: the registry's only
ad-hoc attach was `attachFocused` (`oka:focused` sentinel), the macOS
driver's `snapshot()` bound the focused application, `TypeAction`
degraded to typing into whatever control held keyboard focus, and the
only element verbs were `press` and `focus`. The 10-08 live recipe
therefore was "activate the app first" — exactly the cost this family
exists to avoid.

## Decision

**The focus contract becomes structural: semantic verbs act on the
anchored target in background; global-event verbs refuse unless the
anchor owns the event stream; foreground is an explicit, opt-in,
recorded fallback — "focus last", the actuation sibling of ADR 0053's
"coordinates last".**

1. **Target anchoring (universal).** An OS-tier session may anchor to an
   application instead of to focus: URI anchors `ax://pid/<pid>`,
   `ax://bundle/<bundleId>`, `ax://name/<name>` (resolved through the
   running-apps record at attach; bundle/name resolve to a pid). Plans
   get this for free through `SessionBinding.uri`; MCP/CLI ad-hoc calls
   pass `app: {pid|bundleId|name}`. `attachFocused` stays as the
   convenience default, never a precondition. The anchor vocabulary is
   platform-neutral by construction (a future uiautomator driver anchors
   `ax://device/<serial>`, UIA is pid-native).
2. **Semantic write path (family-wide release).** Two new sealed
   [AutomationAction] cases — the deliberate-verbs list grows once, per
   the `InvokeAction` law:
   - `SetValueAction` — set an element's value attribute (AX value,
     UIA ValuePattern, AT-SPI Value, web `input.value` + events). The
     background text path: no keyboard focus, no event stream.
   - `ElementAction` — perform one action the element *advertises*
     (`AXConfirm`, `AXShowMenu`, `AXPick`, …), read from the snapshot's
     per-node `axActions`; the CUA `performSecondaryAction` analog.
   Drivers that cannot honor them refuse loudly
   (`DriverUnsupportedException`); macOS implements both; the CDP and
   WebDriver tiers implement `SetValueAction` through their existing
   element seams.
3. **The focus contract, enforced in the driver.** Global-event verbs
   (`type`, `key`, `scroll`, `clickAt`, `moveTo`, `drag`) are honest
   about routing: the driver refuses them with
   `ForegroundRequiredException` (kind `foregroundRequired`) unless the
   application that would receive the global stream is the one the
   session last observed (the anchor's pid, or the focused app at
   snapshot time). Before this contract, a mid-session focus switch made
   `type` silently enter text into *the wrong application* — a safety
   bug, not a style choice. Semantic verbs (`click`/`setValue`/
   `elementAction` by locator) act below the focus layer and never
   check focus. The refusal message names the rung needed: activate the
   anchor, or use a semantic verb.
4. **The ladder, in the toolkit, with opt-in.** On
   `foregroundRequired`, the toolkit escalates only when the caller
   explicitly asked: `foreground: true` (MCP) activates the anchor
   (`activate(pid)`), retries the action once, and records
   `focusContract: "activated"` in the result detail. Default is refuse.
   The ladder is: semantic verb → (opt-in) activate + global events.
   PID-scoped CGEvent posting (`CGEventPostToPid`) stays a recorded
   future rung, not an implementation claim.
5. **The resident job plane.** `serve` (stdio/HTTP) is already a
   resident process; it gains submit-and-detach execution:
   `automation_run_background` loads a plan, enqueues it, returns a
   `jobId` immediately; `automation_job` reports status and, when done,
   the full run report. Jobs execute sequentially (one desktop, one
   driver per anchor — no double-driving), persist every transition to
   the jobs directory (`--jobs-dir`), and survive client disconnects.
   This is the v1 of the Codex-shaped split: the client is a control
   plane, the serve process owns execution. Residency is deployment,
   not protocol — owned by oka's supervisor convergence (see
   Follow-through), never a launchd plist or a second daemon.
6. **AI-native surface.** `automation_list_apps` enumerates the running,
   anchorable applications (pid/bundleId/name/frontmost) — the discovery
   record every anchor consumes. Snapshots carry per-node `axActions`
   where the host advertises them, so the model sees pressable /
   settable / confirmable in the same read that produced the refs.
   `returnState` (the act loop's closing read, ADR 0052) is the
   verification channel — background actuation verifies by AX diff, not
   by screenshots.

## Consequences

- Sealed-case growth touches every driver; all six in-repo drivers are
  updated in the same wave (implement or refuse loudly), per the
  refuse-not-degrade rule. mcp_flutter's router consumes actions
  additively; any exhaustive switch there is a follow-up commit in that
  repo (ADR 0038 direction: toolkit never reaches into mcp_flutter).
- The foreground check adds one cheap native call (`frontmost`) before
  global-event dispatch; no tree walk.
- Anchored sessions snapshot by pid; locator verbs resolve against the
  anchored tree. A stale anchor (app quit) fails loudly as
  `elementNotFound`/protocol — re-resolve via `automation_list_apps`.
- Jobs are in-process and sequential; a serve restart loses queued (not
  yet started) jobs but never corrupts completed receipts (persisted
  per transition).

## Follow-through (2026-10-12)

Three recorded rungs landed, each with live or gate evidence:

- **PID-scoped CGEvent rung — landed (keyboard only).** In an anchored
  session, `TypeAction`/`KeyPressAction` post their keyboard events
  straight to the target's event queue (`CGEventPostToPid`) instead of
  refusing: the user's focus never moves. Honest scope: delivery is
  fire-and-forget (the API reports nothing) — apps that drop events
  while mid-transition or inactive fall back to the explicit
  `foreground: true` ladder. Pointer/scroll verbs stay focus-bound:
  they carry global screen coordinates, and posting those to a pid
  would act on whatever sits under the cursor. Live proof: text landed
  in a background-opened TextEdit while another instance held the
  focus (`docs/evidence/pid-scoped-rung-2026-10-12/`), scroll refused,
  focus unchanged. `DriverCapabilities.pidScopedEvents` declares the
  rung.
- **Linux AT-SPI write path — landed.** `SetValueAction` ladders
  `EditableText.SetTextContents` → numeric `Value.CurrentValue` → loud
  refusal; `ElementAction` resolves the target's advertised
  `Action` names (exact, then case-insensitive) to a `DoAction` index
  and names the advertised set on a miss. Windows UIA keeps its loud
  refusal (still a non-claim).
- **Resident plane supervision — oka supervisor convergence, not
  launchd.** An initial LaunchAgent manifest was built and then
  rejected by the owner: oka_supervisor already owns "keep a service
  up" as declarative convergence, is cross-platform (the macOS serve
  and a Linux AT-SPI host take the same spec), and keeps the facts in
  the substrate. The serve is a `ComponentSpec`
  (`SupervisionShape.service`, `TcpConnect` readiness, budgeted
  restarts) converged by the harness lane
  (`~/xs/ecsai_harness/.dart_tool/uatk/serve-lane.exe`, built by
  `tool/build_uatk_lane.dart`).
  Live cycle in `docs/evidence/resident-plane-2026-10-12/`: failed
  start → budgeted restart → converged steady state → resident
  declarative-plan job `succeeded` with a durable receipt. Two
  environment lessons recorded there: the launcher must use the same
  dart SDK the workspace hooks were built with, and a converged lease
  must be spawned outside a sandboxed agent shell or it is reaped.
- **Shell-free runtime and AOT live reload — landed.** Both MCP
  clients (zcode, codex) and the plugin manifests exec the serve AOT
  bundle directly (`build/cli/*/bundle/bin/universal_automation serve
  --os`) — no shell wrapper, no `dart run`, no build hooks at boot;
  the SDK-hash failure class is structurally gone. The supervisor lane
  is itself an AOT exe that spawns the bundle; `--reload` is the AOT
  live-reload verb: rebuild the bundle, stop the lease, converge under
  a fresh policy revision (the planner records "declaration changed")
  — proven live (old pid → new pid, tools answering). A process-managing
  consumer (Last Answer first) drives the same ~20-line DesiredState
  natively; in-process kernel reload remains the JIT live-patch story.
- **Consent composition — landed.** The toolkit adapts
  `xsoulspace_permission_core` (whose `accessibility` /
  `screenRecording` kinds already model the TCC surfaces):
  `ConsentGatedDriver` decorates any driver so snapshots/acts ask
  `accessibility`, screenshots ask `screenRecording`; deny refuses
  before the driver call, escalations resolve through the gate's sink,
  and an allow is never mistaken for the OS grant (the drivers' typed
  TCC exceptions still surface). `ToolkitMcpServer(consentGate:)`
  composes it over MCP sessions, opt-in; the behavioral tier is not
  gated in v1.
- **Declarative test harness — the plan documents.** The acceptance
  lives as committed plan YAML (`pkgs/universal_automation_toolkit/
  plans/`), validated by tests and executable anywhere through the
  `app` handle override; last_answer wires its smoke plan via
  `configs/automation.json`, vosges composes the toolkit as a library
  (`vosges_harness` `DesktopAutomation`).

## Non-claims

- PID-scoped delivery is keyboard-verbs-only and fire-and-forget; it
  does not make every verb backgroundable (pointer/scroll verbs keep
  the foreground contract), and it cannot prove delivery — an app that
  ignores pid-posted events needs `foreground: true`.
- Windows UIA keeps focused-session behavior; it refuses
  `SetValueAction`/`ElementAction` loudly until its write path lands.
- No Android/uiautomator driver; only the anchor vocabulary is reserved.
- Secure input fields, raw-input games, and DRM-fenced surfaces cannot
  be automated in background; the contract *declares* foreground there,
  it does not remove it.
- Jobs do not stream progress incrementally (poll `automation_job`);
  no SSE/websocket channel in v1.
