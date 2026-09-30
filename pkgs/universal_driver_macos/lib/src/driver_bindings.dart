import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Direct bindings to the Swift accessibility driver bridge.
///
/// Internal to the package; the public surface is `MacosDriver` and
/// `AxDriverBridge`. The asset id is the code asset registered by
/// `hook/build.dart` (`package:<pkg>/<name>`); native assets keeps this
/// path fresh on every `dart test/run`.

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

@Native<Void Function()>(
  symbol: 'xs_axdrv_release_all',
  assetId: 'package:universal_driver_macos/xs_ax_driver',
)
/// Drops cached handles and scroll fractions.
/// Drops cached element handles and scroll fractions.
external void axdrvReleaseAll();

@Native<Int32 Function(Uint32, Pointer<Pointer<Uint8>>, Pointer<IntPtr>)>(
  symbol: 'xs_axdrv_screenshot_png',
  assetId: 'package:universal_driver_macos/xs_ax_driver',
)
/// Captures one PNG frame; 10 = permission missing.
external int axdrvScreenshotPng(
  int displayId,
  Pointer<Pointer<Uint8>> outData,
  Pointer<IntPtr> outLen,
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
