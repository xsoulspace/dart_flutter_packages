import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Direct bindings to the Swift accessibility driver bridge.
///
/// Internal to the package; the public surface is `MacosDriver` and
/// `AxDriverBridge`. The asset id is the code asset registered by
/// `hook/build.dart` (`package:<pkg>/<name>`); native assets keeps this
/// path fresh on every `dart test/run`.

// FFI declarations mirror C ABI signatures; positional bools are the
// bridge's shape, not a Dart API design choice.
// ignore_for_file: avoid_positional_boolean_parameters

@Native<Pointer<Utf8> Function()>(
  symbol: 'xs_axdrv_version',
  assetId: 'package:universal_driver_macos/xs_ax_driver',
)
/// Bridge version string.
external Pointer<Utf8> axdrvVersion();

@Native<Bool Function()>(
  symbol: 'xs_axdrv_ax_trusted',
  assetId: 'package:universal_driver_macos/xs_ax_driver',
)
/// Whether the Accessibility TCC grant is present.
external bool axdrvAxTrusted();

@Native<Bool Function()>(
  symbol: 'xs_axdrv_request_trust',
  assetId: 'package:universal_driver_macos/xs_ax_driver',
)
/// Prompts with the system Accessibility consent dialog.
external bool axdrvRequestTrust();

/// Fills [outJson] with a malloc'd JSON string (free via [axdrvFree]).
@Native<Int32 Function(Int32, Int32, Pointer<Pointer<Utf8>>)>(
  symbol: 'xs_axdrv_snapshot_json',
  assetId: 'package:universal_driver_macos/xs_ax_driver',
)
external int axdrvSnapshotJson(
  int maxDepth,
  int maxNodes,
  Pointer<Pointer<Utf8>> outJson,
);

/// Fills [outJson] with a malloc'd JSON string (free via [axdrvFree]).
@Native<Int32 Function(Double, Double, Pointer<Pointer<Utf8>>)>(
  symbol: 'xs_axdrv_element_at_position_json',
  assetId: 'package:universal_driver_macos/xs_ax_driver',
)
external int axdrvElementAtPositionJson(
  double x,
  double y,
  Pointer<Pointer<Utf8>> outJson,
);

@Native<Int32 Function(Int32)>(
  symbol: 'xs_axdrv_press',
  assetId: 'package:universal_driver_macos/xs_ax_driver',
)
/// Performs AXPress on the cached element handle.
external int axdrvPress(int handle);

@Native<Int32 Function(Int32)>(
  symbol: 'xs_axdrv_focus',
  assetId: 'package:universal_driver_macos/xs_ax_driver',
)
/// Focuses the cached element handle.
external int axdrvFocus(int handle);

@Native<Int32 Function(Pointer<Utf8>)>(
  symbol: 'xs_axdrv_type_text',
  assetId: 'package:universal_driver_macos/xs_ax_driver',
)
/// Types [text] into the focused control.
external int axdrvTypeText(Pointer<Utf8> text);

@Native<Int32 Function(Pointer<Utf8>)>(
  symbol: 'xs_axdrv_key_press',
  assetId: 'package:universal_driver_macos/xs_ax_driver',
)
/// Presses and releases the named [key].
external int axdrvKeyPress(Pointer<Utf8> key);

@Native<Int32 Function(Double, Double)>(
  symbol: 'xs_axdrv_scroll',
  assetId: 'package:universal_driver_macos/xs_ax_driver',
)
/// Posts one wheel-line scroll bundle.
/// Posts one wheel-line scroll bundle (dy>0 up, dx>0 right).
external int axdrvScroll(double dx, double dy);

@Native<Int32 Function(Double, Double, Int64)>(
  symbol: 'xs_axdrv_pointer_move',
  assetId: 'package:universal_driver_macos/xs_ax_driver',
)
/// Moves the pointer to (x, y); dragged event while a button is down.
/// [modifierFlags] is the raw CGEventFlags chord mask (0 = none).
external int axdrvPointerMove(double x, double y, int modifierFlags);

@Native<Int32 Function(Double, Double, Pointer<Utf8>, Bool, Int32, Int64)>(
  symbol: 'xs_axdrv_pointer_button',
  assetId: 'package:universal_driver_macos/xs_ax_driver',
)
/// Presses/releases [button] (`left`/`right`/`middle`) at (x, y) with
/// [clickCount] as the event's click state and [modifierFlags] as the
/// chord mask.
external int axdrvPointerButton(
  double x,
  double y,
  Pointer<Utf8> button,
  bool down,
  int clickCount,
  int modifierFlags,
);

@Native<Int32 Function(Pointer<Utf8>)>(
  symbol: 'xs_axdrv_key_down',
  assetId: 'package:universal_driver_macos/xs_ax_driver',
)
/// Presses (holds) the named [key].
external int axdrvKeyDown(Pointer<Utf8> key);

@Native<Int32 Function(Pointer<Utf8>)>(
  symbol: 'xs_axdrv_key_up',
  assetId: 'package:universal_driver_macos/xs_ax_driver',
)
/// Releases the named [key].
external int axdrvKeyUp(Pointer<Utf8> key);

@Native<Void Function()>(
  symbol: 'xs_axdrv_release_all',
  assetId: 'package:universal_driver_macos/xs_ax_driver',
)
/// Drops cached handles and scroll fractions.
/// Drops cached element handles and scroll fractions.
external void axdrvReleaseAll();

@Native<
  Int32 Function(Uint32, Int32, Pointer<Pointer<Uint8>>, Pointer<IntPtr>)
>(
  symbol: 'xs_axdrv_screenshot_png',
  assetId: 'package:universal_driver_macos/xs_ax_driver',
)
/// Captures one PNG frame; 10 = Screen Recording consent missing,
/// `maxPx` caps the long side (0 = raw).
external int axdrvScreenshotPng(
  int displayId,
  int maxPx,
  Pointer<Pointer<Uint8>> outData,
  Pointer<IntPtr> outLen,
);

@Native<
  Int32 Function(Uint32, Int32, Pointer<Pointer<Uint8>>, Pointer<IntPtr>)
>(
  symbol: 'xs_axdrv_screenshot_window_png',
  assetId: 'package:universal_driver_macos/xs_ax_driver',
)
/// Captures one window's PNG; 10 = Screen Recording consent missing,
/// 2 = unknown window.
external int axdrvScreenshotWindowPng(
  int windowId,
  int maxPx,
  Pointer<Pointer<Uint8>> outData,
  Pointer<IntPtr> outLen,
);

@Native<Int32 Function(Int32, Pointer<Pointer<Utf8>>)>(
  symbol: 'xs_axdrv_windows_json',
  assetId: 'package:universal_driver_macos/xs_ax_driver',
)
/// Fills [outJson] with the on-screen windows owned by [pid]
/// (0 = every regular app).
external int axdrvWindowsJson(int pid, Pointer<Pointer<Utf8>> outJson);

@Native<Int32 Function(Pointer<Pointer<Utf8>>)>(
  symbol: 'xs_axdrv_apps_json',
  assetId: 'package:universal_driver_macos/xs_ax_driver',
)
/// Fills [outJson] with the running regular applications as JSON.
external int axdrvAppsJson(Pointer<Pointer<Utf8>> outJson);

@Native<Int32 Function(Pointer<Pointer<Utf8>>)>(
  symbol: 'xs_axdrv_frontmost_json',
  assetId: 'package:universal_driver_macos/xs_ax_driver',
)
/// Fills [outJson] with the frontmost application as JSON.
external int axdrvFrontmostJson(Pointer<Pointer<Utf8>> outJson);

@Native<Int32 Function(Int32)>(
  symbol: 'xs_axdrv_activate_app',
  assetId: 'package:universal_driver_macos/xs_ax_driver',
)
/// Brings the application with [pid] to the front.
external int axdrvActivateApp(int pid);

@Native<Int32 Function(Pointer<Utf8>)>(
  symbol: 'xs_axdrv_launch_app',
  assetId: 'package:universal_driver_macos/xs_ax_driver',
)
/// Launches (or activates) [bundleId]; returns its pid, negative on error.
external int axdrvLaunchApp(Pointer<Utf8> bundleId);

@Native<Int32 Function(Int32)>(
  symbol: 'xs_axdrv_terminate_app',
  assetId: 'package:universal_driver_macos/xs_ax_driver',
)
/// Asks the application with [pid] to quit.
external int axdrvTerminateApp(int pid);

@Native<Int32 Function(Int32, Int32, Int32, Pointer<Pointer<Utf8>>)>(
  symbol: 'xs_axdrv_snapshot_app_json',
  assetId: 'package:universal_driver_macos/xs_ax_driver',
)
/// Fills [outJson] with ANY application's tree by [pid].
external int axdrvSnapshotAppJson(
  int maxDepth,
  int maxNodes,
  int pid,
  Pointer<Pointer<Utf8>> outJson,
);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'xs_axdrv_free',
  assetId: 'package:universal_driver_macos/xs_ax_driver',
)
/// Frees a malloc'd native buffer.
/// Frees a malloc'd native buffer.
external void axdrvFree(Pointer<Void> pointer);

/// Copies a malloc'd UTF-8 string out and frees it with [axdrvFree].
String copyAndFreeCString(Pointer<Utf8> pointer) {
  final value = pointer.toDartString();
  axdrvFree(pointer.cast<Void>());
  return value;
}

/// Copies a malloc'd byte buffer out and frees it with [axdrvFree].
Uint8List copyAndFreeBytes(Pointer<Uint8> data, int length) {
  final bytes = Uint8List.fromList(data.asTypedList(length));
  axdrvFree(data.cast<Void>());
  return bytes;
}
