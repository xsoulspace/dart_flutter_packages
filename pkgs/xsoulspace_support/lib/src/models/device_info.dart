import 'package:from_json_to_json/from_json_to_json.dart';

/// Extension type that represents device metadata for support requests.
///
/// Contains device platform and system information that is useful for
/// debugging and support purposes.
///
/// Uses from_json_to_json for type-safe JSON handling.
///
/// Can be used to encapsulate device metadata for support requests,
/// debugging, and platform-specific functionality.
///
/// Provides functionality to handle JSON serialization/deserialization
/// and device information access.
extension type const DeviceInfo._(Map<String, dynamic> value) {
  /// {@macro device_info}
  factory DeviceInfo.fromJson(final dynamic json) =>
      DeviceInfo._(jsonDecodeMapAs(json));

  /// {@macro device_info}
  factory DeviceInfo({
    required final String platform,
    required final String model,
    required final String osVersion,
    final String? manufacturer,
    final String? deviceId,
  }) => DeviceInfo._({
    'platform': platform,
    'model': model,
    'os_version': osVersion,
    'manufacturer': manufacturer,
    'device_id': deviceId,
  });

  /// The platform name (e.g., "Android", "iOS", "Web")
  String get platform => jsonDecodeString(value['platform']);

  /// The device model (e.g., "iPhone 15 Pro", "Pixel 7")
  String get model => jsonDecodeString(value['model']);

  /// The operating system version (e.g., "iOS 17.2", "Android 14")
  String get osVersion => jsonDecodeString(value['os_version']);

  /// The device manufacturer (e.g., "Apple", "Samsung")
  String? get manufacturer => jsonDecodeString(value['manufacturer']);

  /// A unique identifier for the device (if available)
  String? get deviceId => jsonDecodeString(value['device_id']);

  Map<String, dynamic> toJson() => value;

  static const empty = DeviceInfo._({});
}
