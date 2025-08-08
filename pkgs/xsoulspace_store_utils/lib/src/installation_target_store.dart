/// The target store or platform the app is intended for.
enum InstallationTargetStore {
  /// {@template installation_target_store_mobile_google_play}
  /// The purchase provider is the mobile Google Apple Pay.
  /// based on [in_app_purchase](https://pub.dev/packages/in_app_purchase)
  /// {@endtemplate}
  mobileGooglePlay('Google Play'),

  /// {@template installation_target_store_mobile_apple_app_store}
  /// The purchase provider is the mobile Apple App Store.
  /// based on [in_app_purchase](https://pub.dev/packages/in_app_purchase)
  /// {@endtemplate}
  mobileAppleAppStore('App Store'),

  /// {@template installation_target_store_rustore}
  /// The purchase provider is the rustore.
  /// {@endtemplate}
  rustore('RuStore'),

  /// {@template installation_target_store_huawei}
  /// The purchase provider is the huawei.
  /// {@endtemplate}
  huawei('Huawei AppGallery');

  const InstallationTargetStore(this.name);

  /// Human-friendly name of the store/target.
  final String name;
}
