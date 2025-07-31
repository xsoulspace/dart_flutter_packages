import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../models/models.dart';

/// {@template device_info_service}
/// Service for collecting device information for support requests.
///
/// Automatically detects platform and retrieves relevant device
/// metadata for debugging and support purposes.
/// {@endtemplate}
class DeviceInfoService {
  /// {@macro device_info_service}
  factory DeviceInfoService() => _instance;
  const DeviceInfoService._();

  /// {@macro device_info_service}
  static const _instance = DeviceInfoService._();

  /// {@template get_device_info}
  /// Retrieves comprehensive device information for the current platform.
  ///
  /// Returns device metadata including platform, model, OS version,
  /// and manufacturer information.
  /// {@endtemplate}
  Future<DeviceInfo> getDeviceInfo() async {
    try {
      final deviceInfoPlugin = DeviceInfoPlugin();

      if (Platform.isAndroid) {
        return await _getAndroidDeviceInfo(deviceInfoPlugin);
      } else if (Platform.isIOS) {
        return await _getIOSDeviceInfo(deviceInfoPlugin);
      } else if (kIsWeb) {
        return await _getWebDeviceInfo(deviceInfoPlugin);
      } else {
        return _getUnknownDeviceInfo();
      }
    } catch (e) {
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
