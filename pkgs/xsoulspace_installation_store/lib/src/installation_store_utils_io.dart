import 'dart:io';

// import 'package:store_checker/store_checker.dart';

import 'installation_store_source.dart';

/// IO implementation to detect install source on mobile/desktop.
class InstallationStoreUtils {
  const InstallationStoreUtils();

  Future<InstallationStoreSource> getInstallationSource() async {
    // final Source installationSource = await StoreChecker.getSource;

    // final InstallSource? mapped = switch (installationSource) {
    //   // Android
    //   Source.IS_INSTALLED_FROM_PLAY_STORE => InstallSource.androidGooglePlay,
    //   Source.IS_INSTALLED_FROM_PLAY_PACKAGE_INSTALLER =>
    //     InstallSource.androidGooglePlayInstaller,
    //   Source.IS_INSTALLED_FROM_AMAZON_APP_STORE =>
    //     InstallSource.androidAmazonAppStore,
    //   Source.IS_INSTALLED_FROM_HUAWEI_APP_GALLERY =>
    //     InstallSource.androidHuaweiAppGallery,
    //   Source.IS_INSTALLED_FROM_SAMSUNG_GALAXY_STORE =>
    //     InstallSource.androidSamsungGalaxyStore,
    //   Source.IS_INSTALLED_FROM_SAMSUNG_SMART_SWITCH_MOBILE =>
    //     InstallSource.androidSamsungSmartSwitchMobile,
    //   Source.IS_INSTALLED_FROM_XIAOMI_GET_APPS =>
    //     InstallSource.androidXiaomiGetApps,
    //   Source.IS_INSTALLED_FROM_OPPO_APP_MARKET =>
    //     InstallSource.androidOppoAppMarket,
    //   Source.IS_INSTALLED_FROM_VIVO_APP_STORE =>
    //     InstallSource.androidVivoAppStore,
    //   Source.IS_INSTALLED_FROM_OTHER_SOURCE => InstallSource.androidApk,
    //   Source.IS_INSTALLED_FROM_RU_STORE => InstallSource.androidRuStore,

    //   // Apple
    //   Source.IS_INSTALLED_FROM_APP_STORE when Platform.isIOS =>
    //     InstallSource.appleIOSAppStore,
    //   Source.IS_INSTALLED_FROM_TEST_FLIGHT when Platform.isIOS =>
    //     InstallSource.appleIOSTestFlight,
    //   Source.IS_INSTALLED_FROM_APP_STORE => InstallSource.appleMacOSAppStore,
    //   Source.IS_INSTALLED_FROM_TEST_FLIGHT =>
    //     InstallSource.appleMacOSTestFlight,
    //   Source.IS_INSTALLED_FROM_LOCAL_SOURCE || Source.UNKNOWN => null,
    // };

    // if (mapped != null) return mapped;

    if (Platform.isAndroid) return InstallationStoreSource.androidApk;
    if (Platform.isIOS) return InstallationStoreSource.appleIOSIpa;
    if (Platform.isMacOS) return InstallationStoreSource.appleMacOSDmg;
    if (Platform.isWindows) return InstallationStoreSource.windowsStore;
    if (Platform.isLinux) return InstallationStoreSource.linux;
    if (Platform.isFuchsia) return InstallationStoreSource.fuchsia;
    return InstallationStoreSource.unknown;
  }
}
