import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'driver_bindings.dart';

/// Outcome of one bridge observation call: an error code plus the JSON
/// payload (empty when the code is non-zero).
typedef BridgeJsonResult = ({int code, String json});

/// Outcome of one bridge screenshot call.
typedef BridgeBytesResult = ({int code, Uint8List bytes});

/// The seam between [MacosDriver] and the native bridge.
///
/// Injectable so the driver's action logic is unit-testable without the
/// dylib (the `universal_driver_linux` FakeBus pattern); production code
/// uses [NativeAxDriverBridge].
abstract interface class AxDriverBridge {
  /// Bridge version string, e.g. `xs-ax-driver/1`.
  String version();

  /// Whether this process may read the accessibility tree. Never prompts.
  bool axTrusted();

  /// Raises the system Accessibility consent prompt when untrusted.
  bool requestTrust();

  /// Serializes the focused application's tree. See the Swift bridge for
  /// the error-code table.
  BridgeJsonResult snapshotJson({required int maxDepth, required int maxNodes});

  /// Serializes ANY application's tree by pid (7 = unknown pid).
  BridgeJsonResult snapshotAppJson({
    required int maxDepth,
    required int maxNodes,
    required int pid,
  });

  /// Serializes the running regular applications as a JSON array.
  BridgeJsonResult appsJson();

  /// Serializes the frontmost application as a JSON object.
  BridgeJsonResult frontmostJson();

  /// Brings the application with [pid] to the front (7 unknown, 8 failed).
  int activateApp(int pid);

  /// Launches (or activates) [bundleId]; returns its pid, negative on
  /// error (-7 unknown bundle id, -8 launch failed).
  int launchApp(String bundleId);

  /// Asks the application with [pid] to quit (7 unknown, 8 refused).
  int terminateApp(int pid);

  /// Hit-tests one element at top-left-origin screen coordinates.
  BridgeJsonResult elementAtPositionJson({
    required double x,
    required double y,
  });

  /// Performs AXPress on the cached element [handle].
  int press(int handle);

  /// Makes the cached element [handle] the focused control.
  int focus(int handle);

  /// Types [text] into the focused control (single unicode CGEvent).
  int typeText(String text);

  /// Presses and releases one named key.
  int keyPress(String key);

  /// One scroll bundle in wheel lines (dy > 0 up, dx > 0 right).
  int scroll(double dx, double dy);

  /// Drops cached element handles and scroll fractions.
  void releaseAll();

  /// One PNG frame of [displayId] (0 = main display).
  BridgeBytesResult screenshotPng({int displayId = 0});
}

/// Production bridge: straight onto the native symbols.
final class NativeAxDriverBridge implements AxDriverBridge {
  @override
  String version() {
    final pointer = axdrvVersion();
    return pointer.toDartString();
  }

  @override
  bool axTrusted() => axdrvAxTrusted();

  @override
  bool requestTrust() => axdrvRequestTrust();

  @override
  BridgeJsonResult snapshotJson({
    required int maxDepth,
    required int maxNodes,
  }) {
    final out = calloc<Pointer<Utf8>>();
    try {
      final code = axdrvSnapshotJson(maxDepth, maxNodes, out);
      final json = code == 0 ? copyAndFreeCString(out.value) : '';
      return (code: code, json: json);
    } finally {
      calloc.free(out);
    }
  }

  @override
  BridgeJsonResult elementAtPositionJson({
    required double x,
    required double y,
  }) {
    final out = calloc<Pointer<Utf8>>();
    try {
      final code = axdrvElementAtPositionJson(x, y, out);
      final json = code == 0 ? copyAndFreeCString(out.value) : '';
      return (code: code, json: json);
    } finally {
      calloc.free(out);
    }
  }

  @override
  BridgeJsonResult snapshotAppJson({
    required int maxDepth,
    required int maxNodes,
    required int pid,
  }) {
    final out = calloc<Pointer<Utf8>>();
    try {
      final code = axdrvSnapshotAppJson(maxDepth, maxNodes, pid, out);
      final json = code == 0 ? copyAndFreeCString(out.value) : '';
      return (code: code, json: json);
    } finally {
      calloc.free(out);
    }
  }

  @override
  BridgeJsonResult appsJson() {
    final out = calloc<Pointer<Utf8>>();
    try {
      final code = axdrvAppsJson(out);
      final json = code == 0 ? copyAndFreeCString(out.value) : '';
      return (code: code, json: json);
    } finally {
      calloc.free(out);
    }
  }

  @override
  BridgeJsonResult frontmostJson() {
    final out = calloc<Pointer<Utf8>>();
    try {
      final code = axdrvFrontmostJson(out);
      final json = code == 0 ? copyAndFreeCString(out.value) : '';
      return (code: code, json: json);
    } finally {
      calloc.free(out);
    }
  }

  @override
  int activateApp(int pid) => axdrvActivateApp(pid);

  @override
  int launchApp(String bundleId) {
    final pointer = bundleId.toNativeUtf8();
    try {
      return axdrvLaunchApp(pointer);
    } finally {
      calloc.free(pointer);
    }
  }

  @override
  int terminateApp(int pid) => axdrvTerminateApp(pid);

  @override
  int press(int handle) => axdrvPress(handle);

  @override
  int focus(int handle) => axdrvFocus(handle);

  @override
  int typeText(String text) {
    final pointer = text.toNativeUtf8();
    try {
      return axdrvTypeText(pointer);
    } finally {
      calloc.free(pointer);
    }
  }

  @override
  int keyPress(String key) {
    final pointer = key.toNativeUtf8();
    try {
      return axdrvKeyPress(pointer);
    } finally {
      calloc.free(pointer);
    }
  }

  @override
  int scroll(double dx, double dy) => axdrvScroll(dx, dy);

  @override
  void releaseAll() => axdrvReleaseAll();

  @override
  BridgeBytesResult screenshotPng({int displayId = 0}) {
    final outData = calloc<Pointer<Uint8>>();
    final outLen = calloc<IntPtr>();
    try {
      final code = axdrvScreenshotPng(displayId, outData, outLen);
      final bytes = code == 0
          ? copyAndFreeBytes(outData.value, outLen.value)
          : Uint8List(0);
      return (code: code, bytes: bytes);
    } finally {
      calloc
        ..free(outData)
        ..free(outLen);
    }
  }
}
