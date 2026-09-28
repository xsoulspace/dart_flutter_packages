# ADR 0037: The `universal_automation_*` family (drivers, screencast, WebRTC)

- Status: Accepted
- Date: 2026-09-27
- North Star impact: `applies`
- Builds on: [ADR 0001](0001_native_ffi_bridge_acp.md) (native-assets hook
  pattern, no-Flutter-plugin rule), [ADR 0036](0036_harness_product_relocated.md)
  (one-way dependency direction across repos)

## Context

Sibling projects already prove the need for a shared automation stack:

- `mcp_flutter` drives instrumented Flutter apps over the Dart VM service
  (`mcp_toolkit` extensions + `flutter_mcp_harness`), but not web.
- `oka` owns declarative runtime/session lifecycle (browser session targets,
  process leases, `StartMode {start, attach}`) and deliberately excludes
  protocol clients: a readiness probe, never a CDP client.
- `~/xs/smartdev/plagiarism` drives browser fleets in production and already
  paid for the screencast lessons: socket-frame media rejected for the media
  plane, frames are read-only and never evidence, pacing and single-flight at
  the source, error-frame-then-close, `frames != semantics`,
  `video != evidence`.

No neutral, Flutter-free Dart package family speaks CDP, WebDriver,
declarative frame pipelines, or WebRTC. Writing them per-repo would repeat the
AFM failure (a Flutter plugin surface that forced the Flutter engine on
pure-Dart consumers).

## Decision

Add a **neutral-named package family** (no `xsoulspace_` prefix, following the
`universal_storage_*` precedent):

| Wave | Package | Role |
| --- | --- | --- |
| 1 | `universal_automation_interface` | Pure-Dart contracts: endpoints, session-handle naming (oka-compatible `session-<name>-handle`), driver/actions/snapshot types, fail-closed typed specs, audience/policy vocabulary, structured events |
| 1 | `universal_browser_cdp` | Pure-Dart Chrome DevTools Protocol client (WebSocket JSON-RPC, discovery via `/json/version` + `/json/list`, a11y snapshots, input synthesis, screenshots) + a fake CDP server for tests |
| 1 | `universal_screencast` | Declarative frame pipeline: `FrameSource` (CDP screencast, paced polling) → `FrameSink` (binary WebSocket, MJPEG HTTP, file recorder) with fail-closed composition validation and audience policies |
| 1 | `universal_automation_conformance` | One-call conformance suites proving drivers, frame sources, and sinks are swappable |
| 2 | `universal_browser_webdriver` | W3C WebDriver client (classic HTTP) + `safaridriver` endpoint adapter (Safari, no Java/Node) |
| 2 | `universal_capture_macos` | macOS-native capture via **Dart native-assets build hooks** (`hook/build.dart` → swiftc → code asset → `@Native`), per the ADR 0001 pattern. No Flutter plugin surface |
| 3 | `universal_webrtc_raw` | webrtc-rs sidecar protocol: process supervision + JSON-lines wire (`xs-webrtc-sidecar/1`) |
| 3 | `universal_webrtc` | High-level WebRTC: `SignalingChannel`, peer factory over the sidecar, `FrameSink` over the WebRTC data channel |

House rules applied to the family:

1. **No Flutter plugin surface** (ADR 0001 guardrail). Cores are pure Dart;
   Flutter consumers get thin adapters in their own repos.
2. **Lifecycle stays in oka.** These packages take an endpoint and attach;
   they never own browser process lifecycle in production composition.
   Spawning for tests/examples is allowed.
3. **Frames are read-only observations.** Frames never mutate session state
   and never replace semantic snapshots (`frames != semantics`).
4. **WebRTC from day one as a contract.** The media plane is separated from
   the control plane (signaling socket vs WebRTC transport). The engine is a
   **webrtc-rs sidecar** (Rust, per the mix-Rust-when-it-pays policy): data
   plane v1 over the WebRTC data channel, media tracks as the v2 roadmap.

## Consequences

- oka's `session-<name>-handle` naming and `browser-debug-uri` artifact gain a
  protocol-client consumer without breaking oka's no-CDP-client boundary.
- `mcp_flutter`'s harness can add web/Jaspr targets by adapting
  `universal_browser_cdp`, mirroring `oka_harness.AndroidAppTarget`.
- The plagiarism project's invariants are encoded in
  `universal_screencast` composition validation and the conformance suites,
  so adopting the Dart packages later is contract-compatible.
- The family must ship `README.md`, `CHANGELOG.md`, `LICENSE`, and pass the
  workspace gates (`just docs-check`, analyze, test) like every other package.

## Non-claims

- Web is not a client target for the CDP/WebDriver clients (they require
  `dart:io`); WebRTC has a browser path via `dart:js_interop` later.
- `universal_capture_macos` ships single-frame capture and permission checks;
  continuous ScreenCaptureKit streaming and AX tree reads are future work.
- Windows/Linux for the WebRTC sidecar are untested builds, not proof.
- Nothing here publishes to pub.dev under a different name or claims Flutter
  compatibility.

## Roadmap glossary (what the future-work items are, and why)

- **WebDriver BiDi** — the next-generation W3C browser-automation
  protocol: a single bidirectional WebSocket with events (console,
  network, page lifecycle) instead of classic WebDriver's
  request-per-action HTTP. Needed because the classic protocol cannot
  stream observations, which the family's observe/act/verify loop wants
  for Firefox/WebKit parity with what CDP gives Chromium.
- **ScreenCaptureKit streaming** — Apple's modern macOS capture
  framework: continuous, damage-driven frames with per-window
  filtering, at a fraction of the cost of repeated full-display
  snapshots. Needed because `universal_capture_macos` v1 is
  single-frame; streaming is what turns the OS-native tier from
  "screenshots on demand" into live observation for agents and humans.
- **AT-SPI / UIA drivers** — the Linux (AT-SPI2 over D-Bus) and Windows
  (UI Automation, COM) accessibility trees: the platform equivalents of
  macOS's AX API. Needed to extend the OS-native driver tier beyond
  macOS so any application on those platforms can be semantically
  observed and actuated — the cross-platform computer-use story.
- **TURN/STUN configuration** — NAT traversal for WebRTC: STUN
  discovers a publicly reachable address; TURN relays traffic when a
  direct connection is impossible (symmetric NATs, restrictive
  firewalls). Needed because the sidecar today only negotiates host
  candidates (same machine/LAN); any cross-network peer pairing — a
  remote viewer watching a local browser session — requires STUN, and
  roughly a fifth of real-world paths require TURN.
  **Proven (2026-09-27):** `transportPolicy: relay` + a real coturn
  allocation — relay-only peers connect and exchange frames through the
  relay (`XS_TEST_TURN=1`; `universal_webrtc/test/turn_relay_test.dart`).
  The relay-forced proof runs both peers on one host with coturn's
  `--allow-loopback-peers`; a physical two-network pass (peers on
  distinct subnets, coturn on a third vantage) needs a second network
  and remains the full-field evidence gate.
