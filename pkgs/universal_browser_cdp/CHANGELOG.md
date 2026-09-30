# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.1.1 - 2026-09-30

### Added

- feat: `CdpPage.scroll` + `CdpDriver` `ScrollAction` support —
  `Input.dispatchMouseEvent` mouse-wheel at the viewport center.

## 0.1.0 - 2026-09-27

### Added

- feat: `CdpDiscovery` readiness probe and target enumeration.
- feat: `CdpConnection` correlated JSON-RPC WebSocket client with events.
- feat: `CdpPage` navigation, evaluation, a11y snapshots, screenshots,
  and trusted input synthesis.
- feat: `CdpDriver`/`CdpBrowserSession` implementing the family driver
  contract.
- feat: `FakeCdpServer` test double (`package:universal_browser_cdp/testing.dart`).
