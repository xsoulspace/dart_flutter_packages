/// macOS-native screen capture and accessibility checks for pure Dart.
///
/// The native side is a Swift bridge compiled by this package's build
/// hook (`hook/build.dart`) and registered as a code asset — the ADR 0001
/// pattern: **pure Dart, no Flutter plugin surface**. Works under
/// `dart test`, `dart run`, and ACP agent subprocesses alike.
///
/// Trust model, mirroring macOS:
/// - `axTrusted` reports whether this process may drive the AX tree.
/// - `screenPermissionPreflight` reports whether screen capture is
///   already permitted; `requestScreenPermission` is the explicit,
///   user-facing consent prompt and is never called automatically.
///
/// Non-claims: single-frame capture only; continuous ScreenCaptureKit
/// streaming and AX-tree reads are future work (ADR 0037).
library;

export 'src/capture_kit_frame_source.dart';
export 'src/capture_bridge_api.dart';
export 'src/capture_exceptions.dart';
export 'src/capture_stream.dart';
