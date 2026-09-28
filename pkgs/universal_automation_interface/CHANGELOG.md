# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.1.0 - 2026-09-27

### Added

- feat: `ScrollAction` — scroll the surface (direction + optional
  distance) so harness scenarios can reach off-screen semantics.
### Added

- feat: `ElementNotFoundException` — a locator matched no node in the driver's latest observation (distinct from `DriverUnsupportedException`; retrying after a fresh snapshot is meaningful).

- feat: `AutomationEndpoint`, `AutomationTransport`, and oka-compatible
  `SessionHandles` naming convention.
- feat: `AutomationDriver` observe/act/verify contract with
  `DriverCapabilities`.
- feat: intent-level `AutomationAction` types and `Snapshot`/`AxNode`
  semantic-tree model.
- feat: fail-closed `TypedSpec` and `SessionDescriptor` (borrowed sessions
  can never be started).
- feat: structured `AutomationEvent` types (payload-free).
- feat: `AutomationException` hierarchy with structured details.
