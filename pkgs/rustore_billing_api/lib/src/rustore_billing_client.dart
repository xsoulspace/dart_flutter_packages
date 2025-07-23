import 'dart:async';

import 'rustore_api.g.dart';

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
  static RustoreBillingClient get instance =>
      _instance ??= RustoreBillingClient._();

  final _api = RustoreBillingApi();
  RustoreBillingCallbackApi? _callbackApi;

  final _purchaseResultController =
      StreamController<RustorePaymentResult>.broadcast();
  final _errorController = StreamController<RustoreError>.broadcast();

  /// Stream of purchase results from payment flows
  Stream<RustorePaymentResult> get purchaseResults =>
      _purchaseResultController.stream;

  /// Stream of errors from billing operations
  Stream<RustoreError> get errors => _errorController.stream;

  var _initialized = false;

  /// Initialize the RuStore billing client
  ///
  /// Must be called before any other billing operations.
  ///
  /// [config] Configuration for the billing client including:
  /// - consoleApplicationId: Your app ID from RuStore console
  /// - deeplinkScheme: Deep link scheme for payment flows
  /// - debugLogs: Enable debug logging (default: false)
  ///
  /// Throws [RustoreBillingException] if initialization fails.
  Future<void> initialize(final RustoreBillingConfig config) async {
    if (_initialized) {
      throw const RustoreBillingException('Billing client already initialized');
    }

    try {
      // Set up callback API for receiving events
      _callbackApi = RustoreBillingCallbackApiImpl(
        onPurchaseResultCallback: _purchaseResultController.add,
        onErrorCallback: _errorController.add,
      );
      RustoreBillingCallbackApi.setUp(_callbackApi);

      await _api.initialize(config);
      _initialized = true;
    } catch (e) {
      throw RustoreBillingException('Failed to initialize billing client: $e');
    }
  }

  /// Handle deep link intent for payment flows
  ///
  /// Should be called when your app receives a deep link related to payments.
  /// Typically called from your main activity's onNewIntent method.
  Future<void> onNewIntent(final String? intentData) async {
    _ensureInitialized();
    await _api.onNewIntent(intentData);
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
    _ensureInitialized();

    try {
      return await _api.getProducts(productIds);
    } catch (e) {
      throw RustoreBillingException('Failed to get products: $e');
    }
  }

  /// Get existing purchases for the current user
  ///
  /// Returns list of [RustorePurchase] objects representing current purchases.
  /// Throws [RustoreBillingException] if operation fails.
  Future<List<RustorePurchase>> getPurchases() async {
    _ensureInitialized();

    try {
      return await _api.getPurchases();
    } catch (e) {
      throw RustoreBillingException('Failed to get purchases: $e');
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
    _ensureInitialized();

    try {
      return await _api.purchaseProduct(productId, developerPayload);
    } catch (e) {
      throw RustoreBillingException('Failed to purchase product: $e');
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
    _ensureInitialized();

    try {
      await _api.confirmPurchase(purchaseId, developerPayload);
    } catch (e) {
      throw RustoreBillingException('Failed to confirm purchase: $e');
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
    _ensureInitialized();

    try {
      await _api.deletePurchase(purchaseId);
    } catch (e) {
      throw RustoreBillingException('Failed to delete purchase: $e');
    }
  }

  /// Dispose resources and close streams
  Future<void> dispose() async {
    await _purchaseResultController.close();
    await _errorController.close();
    RustoreBillingCallbackApi.setUp(null);
    _callbackApi = null;
    _initialized = false;
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw const RustoreBillingException(
        'Billing client not initialized. Call initialize() first.',
      );
    }
  }
}

/// Implementation of callback API for receiving events from native side
class RustoreBillingCallbackApiImpl extends RustoreBillingCallbackApi {
  RustoreBillingCallbackApiImpl({
    required this.onPurchaseResultCallback,
    required this.onErrorCallback,
  });

  final void Function(RustorePaymentResult) onPurchaseResultCallback;
  final void Function(RustoreError) onErrorCallback;

  @override
  void onPurchaseResult(final RustorePaymentResult result) {
    onPurchaseResultCallback(result);
  }

  @override
  void onError(final RustoreError error) {
    onErrorCallback(error);
  }
}

/// Exception thrown by RuStore billing operations
class RustoreBillingException implements Exception {
  const RustoreBillingException(this.message);

  final String message;

  @override
  String toString() => 'RustoreBillingException: $message';
}
