/// The type of purchase provider.
enum PurchaseProviderType {
  /// {@template purchase_provider_type_mobile_google_apple_pay}
  /// The purchase provider is the mobile Google Apple Pay.
  /// based on [in_app_purchase](https://pub.dev/packages/in_app_purchase)
  /// {@endtemplate}
  mobileGooglePlay('Google Play'),

  /// {@template purchase_provider_type_mobile_app_store}
  /// The purchase provider is the mobile Apple App Store.
  /// based on [in_app_purchase](https://pub.dev/packages/in_app_purchase)
  /// {@endtemplate}
  mobileAppleAppStore('App Store'),

  /// {@template purchase_provider_type_rustore}
  /// The purchase provider is the rustore.
  /// {@endtemplate}
  rustore('RuStore'),

  /// {@template purchase_provider_type_huawei}
  /// The purchase provider is the huawei.
  /// {@endtemplate}
  huawei('Huawei AppGallery');

  const PurchaseProviderType(this.storeName);

  /// The name of the store.
  final String storeName;
}
