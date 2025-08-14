// ignore_for_file: lines_longer_than_80_chars
/// {@template installation_store_source}
/// Enum representing the detected source from which the application was installed,
/// covering all major app stores and distribution channels across Android, Apple (iOS/macOS),
/// Windows, Linux, Fuchsia, and Web platforms.
///
/// Use with [InstallationStoreUtils.getInstallationSource] to determine the current install source.
///
/// ### Example
/// ```dart
/// final source = await InstallationStoreUtils().getInstallationSource();
/// if (source.isAndroid) {
///   // Handle Android-specific logic
/// }
/// ```
///
/// See also:
/// - [InstallationStoreUtils] for detection logic
/// - [InstallationTargetStore] for intended distribution targets
/// {@endtemplate}
enum InstallationStoreSource {
  /// {@template android_amazon_app_store}
  /// Installed from Amazon Appstore (Android).
  /// {@endtemplate}
  androidAmazonAppStore,

  /// {@template android_google_play}
  /// Installed from Google Play Store (Android).
  /// {@endtemplate}
  androidGooglePlay,

  /// {@template android_google_play_installer}
  /// Installed via Google Play Installer (Android).
  /// {@endtemplate}
  androidGooglePlayInstaller,

  /// {@template android_huawei_app_gallery}
  /// Installed from Huawei AppGallery (Android).
  /// {@endtemplate}
  androidHuaweiAppGallery,

  /// {@template android_ru_store}
  /// Installed from RuStore (Android).
  /// {@endtemplate}
  androidRuStore,

  /// {@template android_samsung_galaxy_store}
  /// Installed from Samsung Galaxy Store (Android).
  /// {@endtemplate}
  androidSamsungGalaxyStore,

  /// {@template android_samsung_smart_switch_mobile}
  /// Installed via Samsung Smart Switch Mobile (Android).
  /// {@endtemplate}
  androidSamsungSmartSwitchMobile,

  /// {@template android_vivo_app_store}
  /// Installed from Vivo App Store (Android).
  /// {@endtemplate}
  androidVivoAppStore,

  /// {@template android_xiaomi_get_apps}
  /// Installed from Xiaomi GetApps (Android).
  /// {@endtemplate}
  androidXiaomiGetApps,

  /// {@template android_oppo_app_market}
  /// Installed from Oppo App Market (Android).
  /// {@endtemplate}
  androidOppoAppMarket,

  /// {@template android_apk}
  /// Installed via APK (sideloaded or unknown Android source).
  /// {@endtemplate}
  androidApk,

  /// {@template apple_ios_app_store}
  /// Installed from Apple App Store (iOS).
  /// {@endtemplate}
  appleIOSAppStore,

  /// {@template apple_ios_test_flight}
  /// Installed via TestFlight (iOS).
  /// {@endtemplate}
  appleIOSTestFlight,

  /// {@template apple_ios_ipa}
  /// Installed via IPA (sideloaded or unknown iOS source).
  /// {@endtemplate}
  appleIOSIpa,

  /// {@template apple_macos_app_store}
  /// Installed from Mac App Store (macOS).
  /// {@endtemplate}
  appleMacOSAppStore,

  /// {@template apple_macos_test_flight}
  /// Installed via TestFlight (macOS).
  /// {@endtemplate}
  appleMacOSTestFlight,

  /// {@template apple_macos_dmg}
  /// Installed via DMG (macOS, direct download).
  /// {@endtemplate}
  appleMacOSDmg,

  /// {@template apple_macos_steam}
  /// Installed from Steam (macOS).
  /// {@endtemplate}
  appleMacOSSteam,

  /// {@template apple_watchos}
  /// Installed on Apple Watch (watchOS).
  /// {@endtemplate}
  appleWatchOS,

  /// {@template apple_visionos}
  /// Installed on Apple Vision Pro (visionOS).
  /// {@endtemplate}
  appleVisionOS,

  /// {@template windows_store}
  /// Installed from Microsoft Store (Windows).
  /// {@endtemplate}
  windowsStore,

  /// {@template windows_steam}
  /// Installed from Steam (Windows).
  /// {@endtemplate}
  windowsSteam,

  /// {@template linux}
  /// Installed on Linux (generic/unknown source).
  /// {@endtemplate}
  linux,

  /// {@template linux_snap}
  /// Installed via Snap (Linux).
  /// {@endtemplate}
  linuxSnap,

  /// {@template linux_flatpak}
  /// Installed via Flatpak (Linux).
  /// {@endtemplate}
  linuxFlatpak,

  /// {@template linux_steam}
  /// Installed from Steam (Linux).
  /// {@endtemplate}
  linuxSteam,

  /// {@template fuchsia}
  /// Installed on Fuchsia OS.
  /// {@endtemplate}
  fuchsia,

  /// {@template unknown}
  /// Unknown or undetectable installation source.
  /// {@endtemplate}
  unknown,

  /// {@template web_selfhost}
  /// Web: Self-hosted deployment.
  /// {@endtemplate}
  webSelfhost,

  /// {@template web_itchio}
  /// Web: Hosted on Itch.io.
  /// {@endtemplate}
  webItchIo;

  /// {@template installation_store_source_is_android}
  /// Returns `true` if the source is any Android store or installer.
  /// {@endtemplate}
  bool get isAndroid => name.startsWith('android');

  /// {@template installation_store_source_is_apple}
  /// Returns `true` if the source is any Apple platform (iOS, macOS, watchOS, visionOS).
  /// {@endtemplate}
  bool get isApple => name.startsWith('apple');

  /// {@template installation_store_source_is_apple_macos}
  /// Returns `true` if the source is a macOS-specific Apple store or installer.
  /// {@endtemplate}
  bool get isAppleMacos => switch (this) {
    InstallationStoreSource.appleMacOSAppStore ||
    InstallationStoreSource.appleMacOSTestFlight ||
    InstallationStoreSource.appleMacOSDmg ||
    InstallationStoreSource.appleMacOSSteam => true,
    _ => false,
  };

  /// {@template installation_store_source_is_apple_ios}
  /// Returns `true` if the source is an iOS-specific Apple store or installer.
  /// {@endtemplate}
  bool get isAppleIos => switch (this) {
    InstallationStoreSource.appleIOSAppStore ||
    InstallationStoreSource.appleIOSTestFlight ||
    InstallationStoreSource.appleIOSIpa => true,
    _ => false,
  };

  /// {@template installation_store_source_is_windows}
  /// Returns `true` if the source is a Windows store or installer.
  /// {@endtemplate}
  bool get isWindows => name.startsWith('windows');

  /// {@template installation_store_source_is_linux}
  /// Returns `true` if the source is a Linux store or installer.
  /// {@endtemplate}
  bool get isLinux => name.startsWith('linux');

  /// {@template installation_store_source_is_fuchsia}
  /// Returns `true` if the source is Fuchsia OS.
  /// {@endtemplate}
  bool get isFuchsia => name.startsWith('fuchsia');

  /// {@template installation_store_source_is_web}
  /// Returns `true` if the source is a web deployment.
  /// {@endtemplate}
  bool get isWeb => name.startsWith('web');
}
