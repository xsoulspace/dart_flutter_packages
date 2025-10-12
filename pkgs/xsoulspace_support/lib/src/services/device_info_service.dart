import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:xsoulspace_logger/xsoulspace_logger.dart';

import '../models/models.dart';

/// {@template device_info_service}
/// Service for collecting device information for support requests.
///
/// Automatically detects platform and retrieves relevant device
/// metadata for debugging and support purposes.
/// {@endtemplate}
class DeviceInfoService {
  /// {@macro device_info_service}
  const DeviceInfoService({final Logger? logger}) : _logger = logger;

  final Logger? _logger;

  /// {@template get_device_info}
  /// Retrieves comprehensive device information for the current platform.
  ///
  /// Returns device metadata including platform, model, OS version,
  /// and manufacturer information.
  /// {@endtemplate}
  Future<DeviceInfo> getDeviceInfo() async {
    _logger?.debug('DEVICE_INFO_SERVICE', 'Collecting device information');
    try {
      final deviceInfoPlugin = DeviceInfoPlugin();

      final DeviceInfo deviceInfo;
      if (Platform.isAndroid) {
        deviceInfo = await _getAndroidDeviceInfo(deviceInfoPlugin);
      } else if (Platform.isIOS) {
        deviceInfo = await _getIOSDeviceInfo(deviceInfoPlugin);
      } else if (kIsWeb) {
        deviceInfo = await _getWebDeviceInfo(deviceInfoPlugin);
      } else {
        deviceInfo = _getUnknownDeviceInfo();
      }

      _logger?.info(
        'DEVICE_INFO_SERVICE',
        'Device info collected successfully',
        data: {
          'platform': deviceInfo.platform,
          'model': deviceInfo.model,
          'osVersion': deviceInfo.osVersion,
        },
      );

      return deviceInfo;
    } catch (e, stackTrace) {
      _logger?.error(
        'DEVICE_INFO_SERVICE',
        'Failed to get device info',
        error: e,
        stackTrace: stackTrace,
      );
      debugPrint('Failed to get device info: $e');
      return _getUnknownDeviceInfo();
    }
  }

  /// Retrieves Android-specific device information.
  Future<DeviceInfo> _getAndroidDeviceInfo(
    final DeviceInfoPlugin plugin,
  ) async {
    final androidInfo = await plugin.androidInfo;
    return DeviceInfo(
      platform: 'Android',
      model: androidInfo.model,
      osVersion:
          '${androidInfo.version.release} (API ${androidInfo.version.sdkInt})',
      manufacturer: androidInfo.manufacturer,
      deviceId: androidInfo.id,
    );
  }

  /// Retrieves iOS-specific device information.
  Future<DeviceInfo> _getIOSDeviceInfo(final DeviceInfoPlugin plugin) async {
    final iosInfo = await plugin.iosInfo;
    return DeviceInfo(
      platform: 'iOS',
      model: iosInfo.model,
      osVersion: '${iosInfo.systemName} ${iosInfo.systemVersion}',
      manufacturer: 'Apple',
      deviceId: iosInfo.identifierForVendor,
    );
  }

  /// Retrieves Web-specific device information.
  Future<DeviceInfo> _getWebDeviceInfo(final DeviceInfoPlugin plugin) async {
    final webInfo = await plugin.webBrowserInfo;
    return DeviceInfo(
      platform: 'Web',
      model: webInfo.browserName.name,
      osVersion: webInfo.appVersion ?? 'Unknown',
      manufacturer: webInfo.userAgent,
    );
  }

  /// Returns fallback device information when platform detection fails.
  DeviceInfo _getUnknownDeviceInfo() => DeviceInfo(
    platform: 'Unknown',
    model: 'Unknown',
    osVersion: 'Unknown',
    manufacturer: 'Unknown',
  );
}
