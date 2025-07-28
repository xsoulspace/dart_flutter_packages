import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/models.dart';

/// {@template app_info_service}
/// Service for collecting application information for support requests.
///
/// Retrieves app version, build number, package name, and other
/// metadata useful for debugging and support purposes.
/// {@endtemplate}
class AppInfoService {
  /// {@macro app_info_service}
  factory AppInfoService() => _instance;
  const AppInfoService._();

  /// {@macro app_info_service}
  static const _instance = AppInfoService._();

  /// {@template get_app_info}
  /// Retrieves comprehensive application information.
  ///
  /// Returns app metadata including version, build number,
  /// package name, and app name.
  /// {@endtemplate}
  Future<AppInfo> getAppInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return AppInfo(
        version: packageInfo.version,
        buildNumber: packageInfo.buildNumber,
        packageName: packageInfo.packageName,
        appName: packageInfo.appName,
      );
    } catch (e) {
      debugPrint('Failed to get app info: $e');
      return _getFallbackAppInfo();
    }
  }

  /// Returns fallback app information when package info retrieval fails.
  AppInfo _getFallbackAppInfo() => const AppInfo(
    version: 'Unknown',
    buildNumber: 'Unknown',
    packageName: 'unknown.package',
    appName: 'Unknown App',
  );
}
