/// Represents the source from which the application was installed.
enum InstallationStoreSource {
  // android
  androidAmazonAppStore,
  androidGooglePlay,
  androidGooglePlayInstaller,
  androidHuaweiAppGallery,
  androidRuStore,
  androidSamsungGalaxyStore,
  androidSamsungSmartSwitchMobile,
  androidVivoAppStore,
  androidXiaomiGetApps,
  androidOppoAppMarket,
  androidApk,

  // apple
  appleIOSAppStore,
  appleIOSTestFlight,
  appleIOSIpa,
  appleMacOSAppStore,
  appleMacOSTestFlight,
  appleMacOSDmg,
  appleMacOSSteam,
  appleWatchOS,
  appleVisionOS,

  // desktop/web/other
  windowsStore,
  windowsSteam,
  linux,
  linuxSnap,
  linuxFlatpak,
  linuxSteam,
  fuchsia,
  unknown,
  webSelfhost,
  webItchIo;

  bool get isAndroid => name.startsWith('android');
  bool get isApple => name.startsWith('apple');

  bool get isAppleMacos => switch (this) {
    InstallationStoreSource.appleMacOSAppStore ||
    InstallationStoreSource.appleMacOSTestFlight ||
    InstallationStoreSource.appleMacOSDmg ||
    InstallationStoreSource.appleMacOSSteam => true,
    _ => false,
  };

  bool get isAppleIos => switch (this) {
    InstallationStoreSource.appleIOSAppStore ||
    InstallationStoreSource.appleIOSTestFlight ||
    InstallationStoreSource.appleIOSIpa => true,
    _ => false,
  };

  bool get isWindows => name.startsWith('windows');
  bool get isLinux => name.startsWith('linux');
  bool get isFuchsia => name.startsWith('fuchsia');
  bool get isWeb => name.startsWith('web');
}
