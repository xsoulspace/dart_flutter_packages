import 'dart:async';

import 'android/rustore_billing_android.dart';
import 'models/rustore_billing_result.dart';
import 'rustore_api.g.dart';
import 'rustore_billing_platform.dart';

/// {@template rustore_billing_client}
/// Main client for RuStore billing operations.
///
/// Provides methods for initializing the billing client, retrieving products,
/// managing purchases, and handling payment flows.
/// {@endtemplate}
class RustoreBillingClient {
  /// {@macro rustore_billing_client}
  RustoreBillingClient._();

  static RustoreBillingClient? _instance;
  // ignore: prefer_constructors_over_static_methods
  static RustoreBillingClient get instance =>
      _instance ??= RustoreBillingClient._();

  /// Get the platform instance
  RustoreBillingPlatform get _platform => RustoreBillingPlatform.instance;

  /// Unified stream of billing results (both payment results and errors)
  Stream<RustoreBillingResult> get updatesStream {
    if (_platform is RustoreBillingAndroid) {
      return (_platform as RustoreBillingAndroid).updatesStream;
    }
    return const Stream.empty();
  }

  /// Initialize the RuStore billing client
  ///
  /// Must be called before any other billing operations.
  ///
  /// [config] Configuration for the billing client including:
  /// - consoleApplicationId: Your app ID from RuStore console
  /// - deeplinkScheme: Deep link scheme for payment flows
  /// - debugLogs: Enable debug logging (default: false)
  /// - theme: Billing client theme (default: light)
  /// - enableLogging: Enable external payment logging (default: false)
  ///
  /// Throws [RustoreBillingException] if initialization fails.
  Future<void> initialize(final RustoreBillingConfig config) async {
    try {
      await _platform.initialize(config);
    } catch (e, stackTrace) {
      throw RustoreBillingException(
        'Failed to initialize billing client: $e',
        stackTrace,
      );
    }
  }

  /// Handle deep link intent for payment flows
  ///
  /// Should be called when your app receives a deep link related to payments.
  /// Typically called from your main activity's onNewIntent method.
  void onNewIntent(final String? intentData) {
    _platform.onNewIntent(intentData);
  }

  /// Check if purchases are available on this device
  ///
  /// Returns [RustorePurchaseAvailabilityResult] indicating whether purchases
  /// can be made on this device. This checks if RuStore is installed and
  /// properly configured.
  ///
  /// Throws [RustoreBillingException] if operation fails.
  Future<RustorePurchaseAvailabilityResult> checkPurchasesAvailability() async {
    try {
      return await _platform.checkPurchasesAvailability();
    } catch (e, stackTrace) {
      throw RustoreBillingException(
        'Failed to check purchases availability: $e',
        stackTrace,
      );
    }
  }

  /// Check if RuStore is installed on the device
  ///
  /// Returns true if RuStore user is authorized, false otherwise.
  /// Throws [RustoreBillingException] if operation fails.
  Future<bool> isRustoreUserAuthorized() async {
    try {
      return await _platform.isRustoreUserAuthorized();
    } catch (e, stackTrace) {
      throw RustoreBillingException(
        'Failed to check RuStore user authorization: $e',
        stackTrace,
      );
    }
  }

  /// Get available products by their IDs
  ///
  /// [productIds] List of product IDs to retrieve
  ///
  /// Returns list of [RustoreProduct] objects with product information.
  /// Throws [RustoreBillingException] if operation fails.
  Future<List<RustoreProduct>> getProducts(
    final List<String> productIds,
  ) async {
    try {
      return await _platform.getProducts(productIds);
    } catch (e, stackTrace) {
      throw RustoreBillingException('Failed to get products: $e', stackTrace);
    }
  }

  /// Get existing purchases for the current user
  ///
  /// Returns list of [RustorePurchase] objects representing current purchases.
  /// Throws [RustoreBillingException] if operation fails.
  Future<List<RustorePurchase>> getPurchases() async {
    try {
      return await _platform.getPurchases();
    } catch (e, stackTrace) {
      throw RustoreBillingException('Failed to get purchases: $e', stackTrace);
    }
  }

  /// Start purchase flow for a product
  ///
  /// [productId] ID of the product to purchase
  /// [developerPayload] Optional developer payload for tracking
  ///
  /// Returns [RustorePaymentResult] with the payment outcome.
  /// Also emits result via [purchaseResults] stream.
  /// Throws [RustoreBillingException] if operation fails.
  Future<RustorePaymentResult> purchaseProduct(
    final String productId, {
    final String? developerPayload,
  }) async {
    try {
      return await _platform.purchaseProduct(
        productId,
        developerPayload: developerPayload,
      );
    } catch (e, stackTrace) {
      throw RustoreBillingException(
        'Failed to purchase product: $e',
        stackTrace,
      );
    }
  }

  /// Confirm a successful purchase
  ///
  /// Must be called after receiving a successful payment result to finalize
  /// the purchase and deliver the product to the user.
  ///
  /// [purchaseId] ID of the purchase to confirm
  /// [developerPayload] Optional developer payload for verification
  ///
  /// Throws [RustoreBillingException] if operation fails.
  Future<void> confirmPurchase(
    final String purchaseId, {
    final String? developerPayload,
  }) async {
    try {
      await _platform.confirmPurchase(
        purchaseId,
        developerPayload: developerPayload,
      );
    } catch (e, stackTrace) {
      throw RustoreBillingException(
        'Failed to confirm purchase: $e',
        stackTrace,
      );
    }
  }

  /// Delete a purchase
  ///
  /// Use this to remove a purchase that cannot be fulfilled.
  ///
  /// [purchaseId] ID of the purchase to delete
  ///
  /// Throws [RustoreBillingException] if operation fails.
  Future<void> deletePurchase(final String purchaseId) async {
    try {
      await _platform.deletePurchase(purchaseId);
    } catch (e, stackTrace) {
      throw RustoreBillingException(
        'Failed to delete purchase: $e',
        stackTrace,
      );
    }
  }

  /// Set the billing client theme
  ///
  /// Changes the theme of the billing interface dynamically.
  ///
  /// [theme] The theme to apply (light or dark)
  ///
  /// Throws [RustoreBillingException] if operation fails.
  Future<void> setTheme(final RustoreBillingTheme theme) async {
    try {
      await _platform.setTheme(theme);
    } catch (e, stackTrace) {
      throw RustoreBillingException('Failed to set theme: $e', stackTrace);
    }
  }

  /// Dispose resources and close streams
  Future<void> dispose() async {
    if (_platform is RustoreBillingAndroid) {
      await (_platform as RustoreBillingAndroid).dispose();
    }
  }
}

/// Exception thrown by RuStore billing operations
class RustoreBillingException implements Exception {
  const RustoreBillingException(this.message, this.stackTrace);

  final String message;
  final StackTrace stackTrace;

  @override
  String toString() => 'RustoreBillingException: $message\n$stackTrace';
}
