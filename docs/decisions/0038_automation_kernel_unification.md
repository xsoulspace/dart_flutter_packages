# ADR 0038: The family is the automation kernel; toolkit and IntentCall adopt contracts

- Status: Accepted
- Date: 2026-09-27
- North Star impact: `applies`
- Builds on: [ADR 0037](0037_universal_automation_family.md)

## Context

Three sibling efforts overlap: `mcp_toolkit` (in mcp_flutter) drives
Flutter apps over the Dart VM service and exposes that as MCP tools and
a CLI; IntentCall registers what apps can do (intent truth, manifests,
platform projections); the `universal_automation_*` family (ADR 0037)
now provides neutral driver/protocol/observation contracts and
implementations. The same observe/act/verify shape exists in all three.

## Research findings

1. The efforts are **layered, not competing**: IntentCall = WHAT an app
   offers (intent truth, trust, projection); the family = HOW to reach
   apps (driver contracts, protocol clients, observation pipelines);
   `mcp_toolkit` = the Flutter **instrumented driver implementation**
   plus its MCP/CLI transports.
2. Every family driver already speaks the same
   `AutomationDriver` (observe/act/verify) contract that
   `mcp_toolkit`'s VM-service extensions implement implicitly — the
   toolkit's semantic snapshot/tap/enterText map 1:1 onto
   `Snapshot`/`Snapshot` actions.
3. The capture side (`universal_screencast` + `universal_capture_macos`)
   is already framework-free; a Flutter-side emitter only needs the
   house `_flutter` adapter grammar.

## Decision

1. **`universal_automation_interface` is the shared automation
   contract.** `mcp_toolkit` should implement `AutomationDriver` over
   its VM-service extensions (a `ToolkitDriver`), keeping its MCP and
   CLI surfaces as thin transports — the transport-from-engine rule the
   harness already follows.
2. **IntentCall references driver capabilities instead of redefining
   them.** IntentPack entries may declare an `automation` hint
   (driver transport + locator); invocation can route to a driver
   action. IntentCall stays the intent/truth layer; it does not grow
   drivers.
3. **Capture split (direction):** a future `universal_capture_flutter`
   (house `_flutter` grammar) will emit frames and widget-semantic
   snapshots from a running Flutter app over `mcp_toolkit`'s
   extensions, consuming `universal_screencast`'s pipeline contracts.
   `universal_screencast` stays the pipeline core;
   `universal_capture_macos` stays the native observation plane.
4. **No repos move.** `mcp_toolkit` remains mcp_flutter's product
   harness (IntentCall's north star already assigns it there); the
   family remains this repo's neutral home.

## Consequences

- Adoption is additive: implement one interface, expose one adapter —
  no breaking change to toolkit, MCP tools, or intentcall registries.
- Agents get one vocabulary across Flutter (instrumented), browsers
  (CDP/WebDriver/BiDi), and OS-native tiers (AX/AT-SPI/UIA).

## Adoption status (2026-09-27)

- **ToolkitDriver landed** in mcp_flutter's `packages/harness`: the
  toolkit's `AutomationDriver` over `ext.mcp.toolkit.*`, passing the
  family driver conformance suite; the showcase drives
  (`tool/drive_flutter_demo.dart`, `tool/drive_web_demo.dart`) prove the
  instrumented and browser tiers share one vocabulary end-to-end.
- **`universal_capture_flutter` landed** (this repo): the capture split's
  instrumented observation plane — `ToolkitFrameSource` +
  `VmScreenshotGrabber` over the toolkit's `view_screenshots` extension,
  conformant with the family frame-source suite.
- **IntentCall hint landed**: `IntentAutomationHint` (driver transport +
  action + locator) is carried on `AgentIntentDescriptor`; IntentCall
  states how an intent could be driven and still grows no drivers. The
  hint projects onto the MCP wire as tool `_meta`
  (`dev.intentcall/automation`), and mcp_flutter's harness
  (`IntentDriverRouter`) routes hints into `AutomationDriver` actions —
  proven live against the showcase app (routed click/type/navigate).
- **Composition owns the capture adapters** (mcp_flutter restructure):
  the showcase drive programs live in a `showcase/drivers` composition
  package whose `FlutterAppFrames` implements `FrameSource` over the
  harness's own VM client; `flutter_mcp_harness` depends only on
  contracts and protocol clients. The generic
  `universal_capture_flutter` (with `VmScreenshotGrabber`) remains the
  family's self-contained option for non-harness consumers.

## Non-claims

- This ADR does not move packages, republish toolkit APIs, or define
  IntentCall's manifest schema; the wire projection of the automation
  hint (a richer MCP tool-annotation schema) remains future work;
  the `_meta` projection and driver-routed invocation have landed.
