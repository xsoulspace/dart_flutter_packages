import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'driver_bindings.dart';

/// Outcome of one bridge observation call: an error code plus the JSON
/// payload (empty when the code is non-zero).
typedef BridgeJsonResult = ({int code, String json});

/// Outcome of one bridge screenshot call.
typedef BridgeBytesResult = ({int code, Uint8List bytes});

/// CGEventFlags raw mask for the family's modifier names (shift
/// 0x020000, control 0x040000, alt/option 0x080000, meta/command
/// 0x100000); unknown names contribute 0.
int cgEventModifierMask(final Iterable<String> modifiers) {
  var mask = 0;
  for (final modifier in modifiers) {
    mask |= switch (modifier) {
      'shift' => 0x020000,
      'control' => 0x040000,
      'alt' => 0x080000,
      'meta' => 0x100000,
      _ => 0,
    };
  }
  return mask;
}

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

  /// Moves the pointer to top-left-origin screen coordinates; the native
  /// bridge posts a dragged event while a button is logically down.
  /// [modifiers] carries an active chord.
  int pointerMove({
    required double x,
    required double y,
    Iterable<String> modifiers = const [],
  });

  /// Presses or releases [button] (`left`/`right`/`middle`) at (x, y);
  /// [clickCount] feeds the host's multi-click recognition, [modifiers]
  /// holds the chord keys.
  int pointerButton({
    required double x,
    required double y,
    required String button,
    required bool down,
    int clickCount = 1,
    Iterable<String> modifiers = const [],
  });

  /// Presses (holds) one named key.
  int keyDown(String key);

  /// Releases one named key.
  int keyUp(String key);

  /// Drops cached element handles and scroll fractions.
  void releaseAll();

  /// One PNG frame of [displayId] (0 = main display); `maxPx` caps the
  /// long side (0/null = raw). Code 10 = Screen Recording consent.
  BridgeBytesResult screenshotPng({int displayId = 0, int maxPx = 0});

  /// One PNG frame of a single window. Code 10 = Screen Recording
  /// consent, 2 = unknown window.
  BridgeBytesResult screenshotWindowPng({required int windowId, int maxPx = 0});

  /// The on-screen windows owned by [pid] (0 = every regular app) as a
  /// JSON array.
  BridgeJsonResult windowsJson({int pid = 0});
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
  int pointerMove({
    required double x,
    required double y,
    Iterable<String> modifiers = const [],
  }) => axdrvPointerMove(x, y, cgEventModifierMask(modifiers));

  @override
  int pointerButton({
    required double x,
    required double y,
    required String button,
    required bool down,
    int clickCount = 1,
    Iterable<String> modifiers = const [],
  }) {
    final pointer = button.toNativeUtf8();
    try {
      return axdrvPointerButton(
        x,
        y,
        pointer,
        down,
        clickCount,
        cgEventModifierMask(modifiers),
      );
    } finally {
      calloc.free(pointer);
    }
  }

  @override
  int keyDown(String key) {
    final pointer = key.toNativeUtf8();
    try {
      return axdrvKeyDown(pointer);
    } finally {
      calloc.free(pointer);
    }
  }

  @override
  int keyUp(String key) {
    final pointer = key.toNativeUtf8();
    try {
      return axdrvKeyUp(pointer);
    } finally {
      calloc.free(pointer);
    }
  }

  @override
  void releaseAll() => axdrvReleaseAll();

  @override
  BridgeBytesResult screenshotPng({int displayId = 0, int maxPx = 0}) =>
      _captureBytes((outData, outLen) =>
          axdrvScreenshotPng(displayId, maxPx, outData, outLen));

  @override
  BridgeBytesResult screenshotWindowPng({
    required int windowId,
    int maxPx = 0,
  }) => _captureBytes(
    (outData, outLen) =>
        axdrvScreenshotWindowPng(windowId, maxPx, outData, outLen),
  );

  @override
  BridgeJsonResult windowsJson({int pid = 0}) {
    final out = calloc<Pointer<Utf8>>();
    try {
      final code = axdrvWindowsJson(pid, out);
      final json = code == 0 ? copyAndFreeCString(out.value) : '';
      return (code: code, json: json);
    } finally {
      calloc.free(out);
    }
  }

  BridgeBytesResult _captureBytes(
    int Function(Pointer<Pointer<Uint8>>, Pointer<IntPtr>) call,
  ) {
    final outData = calloc<Pointer<Uint8>>();
    final outLen = calloc<IntPtr>();
    try {
      final code = call(outData, outLen);
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
