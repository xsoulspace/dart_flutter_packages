import 'dart:convert';

import 'package:universal_automation_interface/universal_automation_interface.dart';

/// One running, Dock-able macOS application — the discovery record the
/// app-management surface (`MacosDriver.runningApps` / `frontmost`)
/// returns and every targeting call (`activate`, `terminate`, per-app
/// `snapshot`) consumes.
final class MacosApp {
  /// Creates a record.
  const MacosApp({
    required this.pid,
    required this.name,
    required this.active,
    required this.hidden,
    this.bundleId,
  });

  /// Decodes one bridge record.
  factory MacosApp.fromJson(Map<String, Object?> json) => MacosApp(
    pid: switch (json['pid']) {
      final num pid => pid.toInt(),
      _ => 0,
    },
    name: json['name'] as String? ?? '',
    active: json['active'] as bool? ?? false,
    hidden: json['hidden'] as bool? ?? false,
    bundleId: json['bundleId'] as String?,
  );

  /// Process id — the handle every app-targeted bridge call takes.
  final int pid;

  /// Bundle identifier (`com.apple.Safari`), when the app has one.
  final String? bundleId;

  /// Display name (`localizedName`).
  final String name;

  /// Whether the app currently owns the frontmost, key window.
  final bool active;

  /// Whether the app is hidden.
  final bool hidden;

  /// Decodes a bridge JSON array.
  static List<MacosApp> listFromJson(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! List<Object?>) {
      throw const FormatException('apps payload is not a JSON array');
    }
    return [
      for (final entry in decoded)
        MacosApp.fromJson(
          (entry! as Map<Object?, Object?>).cast<String, Object?>(),
        ),
    ];
  }

  @override
  String toString() =>
      'MacosApp(pid: $pid, bundleId: $bundleId, name: $name, '
      'active: $active)';
}


/// One on-screen window of a running application — the discovery record
/// for window-scoped capture.
final class MacosWindow {
  /// Creates a window record.
  const MacosWindow({
    required this.windowId,
    required this.pid,
    required this.name,
    this.bounds,
  });

  /// Restores a window record from one bridge JSON object.
  factory MacosWindow.fromJson(Map<String, Object?> json) {
    final rawBounds = json['bounds'];
    return MacosWindow(
      windowId: (json['windowId']! as num).toInt(),
      pid: (json['pid']! as num).toInt(),
      name: json['name']! as String,
      bounds: rawBounds is Map<String, Object?>
          ? AxBounds.fromJson({
              'left': (rawBounds['left']! as num).toDouble(),
              'top': (rawBounds['top']! as num).toDouble(),
              'width': (rawBounds['width']! as num).toDouble(),
              'height': (rawBounds['height']! as num).toDouble(),
            })
          : null,
    );
  }

  /// The CGWindow number capture addresses.
  final int windowId;

  /// Owning application pid.
  final int pid;

  /// Window title; may be empty without Screen Recording consent.
  final String name;

  /// Global bounds, when the window list published them.
  final AxBounds? bounds;

  /// Decodes a bridge JSON array.
  static List<MacosWindow> listFromJson(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! List<Object?>) {
      throw const FormatException('windows payload is not a JSON array');
    }
    return [
      for (final entry in decoded)
        MacosWindow.fromJson(
          (entry! as Map<Object?, Object?>).cast<String, Object?>(),
        ),
    ];
  }

  @override
  String toString() => 'MacosWindow(#$windowId pid=$pid name="$name")';
}
