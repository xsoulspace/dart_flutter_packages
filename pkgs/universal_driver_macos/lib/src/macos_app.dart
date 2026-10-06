import 'dart:convert';

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
