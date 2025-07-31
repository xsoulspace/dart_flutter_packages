import 'package:from_json_to_json/from_json_to_json.dart';

/// Extension type that represents application metadata for support requests.
///
/// Contains app version and build information that is useful for
/// debugging and support purposes.
///
/// Uses from_json_to_json for type-safe JSON handling.
///
/// Can be used to encapsulate application metadata for support requests,
/// debugging, and version tracking.
///
/// Provides functionality to handle JSON serialization/deserialization
/// and app version information access.
extension type const AppInfo._(Map<String, dynamic> value) {
  /// {@macro app_info}
  factory AppInfo({
    required final String version,
    required final String buildNumber,
    required final String packageName,
    final String? appName,
  }) => AppInfo._({
    'version': version,
    'build_number': buildNumber,
    'package_name': packageName,
    'app_name': appName,
  });

  /// {@macro app_info}
  factory AppInfo.fromJson(final dynamic json) =>
      AppInfo._(jsonDecodeMapAs(json));

  /// The semantic version of the app (e.g., "1.0.0")
  String get version => jsonDecodeString(value['version']);

  /// The build number (e.g., "1", "42")
  String get buildNumber => jsonDecodeString(value['build_number']);

  /// The package identifier (e.g., "com.example.app")
  String get packageName => jsonDecodeString(value['package_name']);

  /// The display name of the app (e.g., "My App")
  String? get appName => jsonDecodeString(value['app_name']);

  Map<String, dynamic> toJson() => value;

  static const empty = AppInfo._({});
}
