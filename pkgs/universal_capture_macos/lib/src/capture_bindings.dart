import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Direct bindings to the Swift capture bridge.
///
/// Kept internal to the package: the public surface is `CaptureBridge`
/// (see `universal_capture_macos.dart`). The asset id is the code asset
/// registered by `hook/build.dart` (`package:<pkg>/<name>`); native
/// assets keeps this path fresh on every `dart test/run`, so resolution
/// is always against the newest compiled bridge.

@Native<Pointer<Utf8> Function()>(
  symbol: 'xs_capture_bridge_version',
  assetId: 'package:universal_capture_macos/xs_capture_bridge',
)
external Pointer<Utf8> bridgeVersion();

@Native<Bool Function()>(
  symbol: 'xs_capture_ax_is_trusted',
  assetId: 'package:universal_capture_macos/xs_capture_bridge',
)
external bool axIsTrusted();

@Native<Bool Function()>(
  symbol: 'xs_capture_screen_permission_preflight',
  assetId: 'package:universal_capture_macos/xs_capture_bridge',
)
external bool screenPreflightNative();

@Native<Bool Function()>(
  symbol: 'xs_capture_screen_permission_request',
  assetId: 'package:universal_capture_macos/xs_capture_bridge',
)
external bool screenPermissionRequest();

@Native<Int32 Function(Pointer<Uint32>, Int32, Pointer<Int32>)>(
  symbol: 'xs_capture_list_displays',
  assetId: 'package:universal_capture_macos/xs_capture_bridge',
)
external int listDisplaysNative(
  Pointer<Uint32> outIds,
  int maxCount,
  Pointer<Int32> outCount,
);

@Native<Int32 Function(Uint32, Pointer<Pointer<Uint8>>, Pointer<IntPtr>)>(
  symbol: 'xs_capture_screenshot_png',
  assetId: 'package:universal_capture_macos/xs_capture_bridge',
)
external int screenshotPngNative(
  int displayId,
  Pointer<Pointer<Uint8>> outData,
  Pointer<IntPtr> outLength,
);

@Native<Void Function(Pointer<Uint8>)>(
  symbol: 'xs_capture_free',
  assetId: 'package:universal_capture_macos/xs_capture_bridge',
)
external void captureFree(Pointer<Uint8> pointer);
