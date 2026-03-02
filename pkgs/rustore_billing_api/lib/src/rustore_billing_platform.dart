import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'rustore_api.g.dart';

abstract class RustoreBillingPlatform extends PlatformInterface {
  RustoreBillingPlatform() : super(token: _token);

  static final Object _token = Object();
  static RustoreBillingPlatform _instance = _PlaceholderImplementation();

  static RustoreBillingPlatform get instance => _instance;

  static set instance(final RustoreBillingPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  Future<void> initialize(final RustoreBillingConfig config) {
    throw UnimplementedError('initialize() has not been implemented.');
  }

  Future<RustorePurchaseAvailabilityResult> getPurchaseAvailability() {
    throw UnimplementedError(
      'getPurchaseAvailability() has not been implemented.',
    );
  }

  Future<bool> getUserAuthorizationStatus() {
    throw UnimplementedError(
      'getUserAuthorizationStatus() has not been implemented.',
    );
  }

  Future<List<RustoreProduct>> getProducts(final List<String> productIds) {
    throw UnimplementedError('getProducts() has not been implemented.');
  }

  Future<List<RustorePurchase>> getPurchases(
    final RustorePurchaseFilter? filter,
  ) {
    throw UnimplementedError('getPurchases() has not been implemented.');
  }

  Future<RustorePurchase?> getPurchase(final String purchaseId) {
    throw UnimplementedError('getPurchase() has not been implemented.');
  }

  Future<RustoreProductPurchaseResult> purchase(
    final RustoreProductPurchaseParams params, {
    final RustorePreferredPurchaseType preferredPurchaseType =
        RustorePreferredPurchaseType.unknown,
    final RustoreBillingTheme sdkTheme = RustoreBillingTheme.system,
  }) {
    throw UnimplementedError('purchase() has not been implemented.');
  }

  Future<RustoreProductPurchaseResult> purchaseTwoStep(
    final RustoreProductPurchaseParams params, {
    final RustoreBillingTheme sdkTheme = RustoreBillingTheme.system,
  }) {
    throw UnimplementedError('purchaseTwoStep() has not been implemented.');
  }

  Future<void> confirmTwoStepPurchase(
    final String purchaseId, {
    final String? developerPayload,
  }) {
    throw UnimplementedError(
      'confirmTwoStepPurchase() has not been implemented.',
    );
  }

  Future<void> cancelTwoStepPurchase(final String purchaseId) {
    throw UnimplementedError(
      'cancelTwoStepPurchase() has not been implemented.',
    );
  }

  void setCallbackApi(final RustoreBillingCallbackApi callbackApi) {
    throw UnimplementedError('setCallbackApi() has not been implemented.');
  }
}

class _PlaceholderImplementation extends RustoreBillingPlatform {}
