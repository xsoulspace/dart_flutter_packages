/// FrameSource over a running Flutter app's MCP toolkit screenshots.
///
/// The `_flutter` grammar member of the `universal_automation_*` family
/// (ADR 0038 capture split): the pipeline core stays in
/// `universal_screencast`, the native observation plane in
/// `universal_capture_macos`, and this package emits frames from the
/// **instrumented** tier — a Flutter app bound to
/// [mcp_toolkit](https://pub.dev/packages/mcp_toolkit) — by polling
/// `ext.mcp.toolkit.view_screenshots` over the Dart VM service.
///
/// Frames are read-only observations (`frames != semantics`); semantic
/// snapshots come from an `AutomationDriver` (e.g. the toolkit's).
library;

export 'src/toolkit_frame_source.dart';
export 'src/vm_screenshot_grab.dart';
