/// Windows accessibility driver for the universal automation family.
///
/// Speaks UI Automation through a Rust sidecar (`rust/uia_sidecar/`,
/// `uia-sidecar/1` JSON-lines over stdio) — the same engine-sidecar
/// pattern as the family's WebRTC stack. Observe the Windows control
/// tree as a semantic snapshot; act through `InvokePattern`.
///
/// Driver tier: **OS-native** — reaches any Windows application exposing
/// UIA (Win32, WPF, WinUI, Electron with accessibility enabled), with no
/// per-app cooperation required.
library;

export 'src/uia_driver.dart';
export 'src/uia_sidecar_client.dart';
