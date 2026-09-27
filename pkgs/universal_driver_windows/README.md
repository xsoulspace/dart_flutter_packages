# universal_driver_windows

Windows accessibility driver for the `universal_automation_*` family:
**UI Automation through a Rust sidecar** (`xs-uia-sidecar`, JSON-lines
over stdio) — the same engine-sidecar pattern as the family's WebRTC
stack. Observe the Windows control tree as a semantic snapshot; act
through `InvokePattern`.

Part of [ADR 0037](../../docs/decisions/0037_universal_automation_family.md).

## Layout

- `rust/uia_sidecar/` — the Windows engine (windows-rs, `CUIAutomation`,
  ControlViewWalker, InvokePattern). Windows-gated: other targets
  compile a loud-failure stub. Build: `cargo build --release`.
- `lib/` — `UiaSidecarClient` (handshake, correlated requests, events),
  `UiaDriver` (control-type ids → family roles, name-located clicks).

## Capabilities (honest)

a11y tree ✓ · InvokePattern click ✓ · navigation/typing/keys/script ✗
(ValuePattern/SendInput are the next sidecar revisions).

## Non-claims

- The Dart client and protocol are tested via an in-memory sidecar; the
  Rust engine is Windows-gated and **untested until a Windows CI or
  desktop pass** — expect churn in the UIA walk.
