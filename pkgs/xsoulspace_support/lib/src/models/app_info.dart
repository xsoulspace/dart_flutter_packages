/// {@template app_info}
/// Contains app version and build information for support requests.
///
/// This model encapsulates application metadata that is useful for
/// debugging and support purposes.
/// {@endtemplate}
class AppInfo {
  /// {@macro app_info}
  const AppInfo({
    required this.version,
    required this.buildNumber,
    required this.packageName,
    this.appName,
  });

  /// The semantic version of the app (e.g., "1.0.0")
  final String version;

  /// The build number (e.g., "1", "42")
  final String buildNumber;

  /// The package identifier (e.g., "com.example.app")
  final String packageName;

  /// The display name of the app (e.g., "My App")
  final String? appName;
}
