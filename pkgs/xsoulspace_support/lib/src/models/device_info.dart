/// {@template device_info}
/// Contains device platform and system information for support requests.
///
/// This model encapsulates device metadata that is useful for
/// debugging and support purposes.
/// {@endtemplate}
class DeviceInfo {
  /// {@macro device_info}
  const DeviceInfo({
    required this.platform,
    required this.model,
    required this.osVersion,
    this.manufacturer,
    this.deviceId,
  });

  /// The platform name (e.g., "Android", "iOS", "Web")
  final String platform;

  /// The device model (e.g., "iPhone 15 Pro", "Pixel 7")
  final String model;

  /// The operating system version (e.g., "iOS 17.2", "Android 14")
  final String osVersion;

  /// The device manufacturer (e.g., "Apple", "Samsung")
  final String? manufacturer;

  /// A unique identifier for the device (if available)
  final String? deviceId;
}
