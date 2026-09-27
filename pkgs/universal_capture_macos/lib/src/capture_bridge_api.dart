import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';

import 'capture_bindings.dart';
import 'capture_exceptions.dart';

/// High-level, pure-Dart API over the Swift capture bridge.
abstract final class CaptureBridge {
  static const int _maxDisplays = 8;
  static bool _loaded = false;

  /// Guards the first native call: refuses non-macOS platforms early so
  /// the error is the family's typed one, not a dlopen trace.
  static void ensureLoaded() {
    if (!Platform.isMacOS) {
      throw DriverUnsupportedException(
        'universal_capture_macos only loads on macOS',
      );
    }
    _loaded = true;
  }

  /// Bridge version string, e.g. `xs-capture-bridge/1`.
  static String version() {
    ensureLoaded();
    return bridgeVersion().toDartString();
  }

  /// Whether this process may drive the accessibility tree. Never
  /// prompts.
  static bool get axTrusted {
    ensureLoaded();
    return axIsTrusted();
  }

  /// Whether screen capture is already permitted. Never prompts.
  static bool get screenPermissionPreflight {
    ensureLoaded();
    return screenPreflightNative();
  }

  /// Shows the system screen-recording consent prompt. Call only as an
  /// explicit, user-initiated action.
  static bool requestScreenPermission() {
    ensureLoaded();
    return screenPermissionRequest();
  }

  /// Online display ids (main display first when present).
  static List<int> listDisplays() {
    ensureLoaded();
    final ids = calloc<Uint32>(_maxDisplays);
    final count = calloc<Int32>();
    try {
      final code = listDisplaysNative(ids, _maxDisplays, count);
      if (code != 0) {
        throw CaptureBridgeException('listDisplays failed', code: code);
      }
      return [for (var i = 0; i < count.value; i++) ids[i]];
    } finally {
      calloc.free(ids);
      calloc.free(count);
    }
  }

  /// Captures one PNG frame of [displayId] (0 = main display).
  ///
  /// Throws [CapturePermissionDeniedException] when screen recording is
  /// not yet permitted — call [requestScreenPermission] as an explicit
  /// user action first.
  static Uint8List screenshotPng({int displayId = 0}) {
    ensureLoaded();
    final outData = calloc<Pointer<Uint8>>();
    final outLength = calloc<IntPtr>();
    try {
      final code = screenshotPngNative(displayId, outData, outLength);
      switch (code) {
        case 0:
          break;
        case 10:
          throw CapturePermissionDeniedException();
        default:
          throw CaptureBridgeException('screenshotPng failed', code: code);
      }
      final length = outLength.value;
      final pointer = outData.value;
      final bytes = Uint8List.fromList(pointer.asTypedList(length));
      captureFree(pointer);
      return bytes;
    } finally {
      calloc.free(outData);
      calloc.free(outLength);
    }
  }
}
