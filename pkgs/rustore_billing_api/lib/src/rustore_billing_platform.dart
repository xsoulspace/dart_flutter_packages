import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'rustore_api.g.dart';

/// Platform interface for RuStore billing operations
abstract class RustoreBillingPlatform extends PlatformInterface {
  /// Constructs platform interface
  RustoreBillingPlatform() : super(token: _token);

  static final _token = Object();
  static RustoreBillingPlatform _instance = _PlaceholderImplementation();

  /// The instance of the RustoreBillingPlatform
  static RustoreBillingPlatform get instance => _instance;

  /// Platform-specific plugins should override this with their own
  /// platform-specific class that extends [RustoreBillingPlatform] when they
  /// register themselves.
  static set instance(final RustoreBillingPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// Initialize the RuStore billing client
  Future<void> initialize(final RustoreBillingConfig config) {
    throw UnimplementedError('initialize() has not been implemented.');
  }

  /// Handle deep link intent for payment flows
  void onNewIntent(final String? intentData) {
    throw UnimplementedError('onNewIntent() has not been implemented.');
  }

  /// Check if purchases are available on this device
  Future<RustorePurchaseAvailabilityResult> checkPurchasesAvailability() {
    throw UnimplementedError(
      'checkPurchasesAvailability() has not been implemented.',
    );
  }

  /// Check if RuStore is installed on the device
  Future<bool> isRustoreUserAuthorized() {
    throw UnimplementedError(
      'isRustoreUserAuthorized() has not been implemented.',
    );
  }

  /// Get available products by their IDs
  Future<List<RustoreProduct>> getProducts(final List<String> productIds) {
    throw UnimplementedError('getProducts() has not been implemented.');
  }

  /// Get existing purchases for the current user
  Future<List<RustorePurchase>> getPurchases() {
    throw UnimplementedError('getPurchases() has not been implemented.');
  }

  /// Start purchase flow for a product
  Future<RustorePaymentResult> purchaseProduct(
    final String productId, {
    final String? developerPayload,
  }) {
    throw UnimplementedError('purchaseProduct() has not been implemented.');
  }

  /// Confirm a successful purchase
  Future<void> confirmPurchase(
    final String purchaseId, {
    final String? developerPayload,
  }) {
    throw UnimplementedError('confirmPurchase() has not been implemented.');
  }

  /// Delete a purchase
  Future<void> deletePurchase(final String purchaseId) {
    throw UnimplementedError('deletePurchase() has not been implemented.');
  }

  /// Set the billing client theme
  Future<void> setTheme(final RustoreBillingTheme theme) {
    throw UnimplementedError('setTheme() has not been implemented.');
  }

  /// Set up callback API for receiving events
  void setCallbackApi(final RustoreBillingCallbackApi callbackApi) {
    throw UnimplementedError('setCallbackApi() has not been implemented.');
  }
}

/// Placeholder implementation for when platform is not available
class _PlaceholderImplementation extends RustoreBillingPlatform {}
