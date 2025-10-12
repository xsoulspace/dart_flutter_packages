import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:xsoulspace_logger/xsoulspace_logger.dart';

import '../models/models.dart';

/// {@template app_info_service}
/// Service for collecting application information for support requests.
///
/// Retrieves app version, build number, package name, and other
/// metadata useful for debugging and support purposes.
/// {@endtemplate}
class AppInfoService {
  /// {@macro app_info_service}
  const AppInfoService({final Logger? logger}) : _logger = logger;

  final Logger? _logger;

  /// {@template get_app_info}
  /// Retrieves comprehensive application information.
  ///
  /// Returns app metadata including version, build number,
  /// package name, and app name.
  /// {@endtemplate}
  Future<AppInfo> getAppInfo() async {
    _logger?.debug('APP_INFO_SERVICE', 'Collecting app information');
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final appInfo = AppInfo(
        version: packageInfo.version,
        buildNumber: packageInfo.buildNumber,
        packageName: packageInfo.packageName,
        appName: packageInfo.appName,
      );
      _logger?.info(
        'APP_INFO_SERVICE',
        'App info collected successfully',
        data: {
          'version': appInfo.version,
          'buildNumber': appInfo.buildNumber,
          'packageName': appInfo.packageName,
        },
      );
      return appInfo;
    } catch (e, stackTrace) {
      _logger?.error(
        'APP_INFO_SERVICE',
        'Failed to get app info',
        error: e,
        stackTrace: stackTrace,
      );
      debugPrint('Failed to get app info: $e');
      return _getFallbackAppInfo();
    }
  }

  /// Returns fallback app information when package info retrieval fails.
  AppInfo _getFallbackAppInfo() => AppInfo(
    version: 'Unknown',
    buildNumber: 'Unknown',
    packageName: 'unknown.package',
    appName: 'Unknown App',
  );
}
