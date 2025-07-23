import 'dart:async';

import '../rustore_api.g.dart';
import '../rustore_billing_platform.dart';

/// Android implementation of RuStore billing operations
class RustoreBillingAndroid extends RustoreBillingPlatform {
  RustoreBillingAndroid._() : super();

  /// Registers this class as the default instance of [RustoreBillingPlatform].
  static void registerWith() {
    RustoreBillingPlatform.instance = RustoreBillingAndroid._();
  }

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

  @override
  Future<void> initialize(final RustoreBillingConfig config) async {
    // Set up callback API for receiving events
    _callbackApi = RustoreBillingCallbackApiImpl(
      onPurchaseResultCallback: _purchaseResultController.add,
      onErrorCallback: _errorController.add,
    );
    RustoreBillingCallbackApi.setUp(_callbackApi);

    await _api.initialize(config);
  }

  @override
  void onNewIntent(final String? intentData) {
    unawaited(_api.onNewIntent(intentData));
  }

  @override
  Future<List<RustoreProduct>> getProducts(final List<String> productIds) =>
      _api.getProducts(productIds);

  @override
  Future<List<RustorePurchase>> getPurchases() async => _api.getPurchases();

  @override
  Future<RustorePaymentResult> purchaseProduct(
    final String productId, {
    final String? developerPayload,
  }) => _api.purchaseProduct(productId, developerPayload);

  @override
  Future<void> confirmPurchase(
    final String purchaseId, {
    final String? developerPayload,
  }) async {
    await _api.confirmPurchase(purchaseId, developerPayload);
  }

  @override
  Future<void> deletePurchase(final String purchaseId) async {
    await _api.deletePurchase(purchaseId);
  }

  @override
  void setCallbackApi(final RustoreBillingCallbackApi callbackApi) {
    _callbackApi = callbackApi;
    RustoreBillingCallbackApi.setUp(callbackApi);
  }

  /// Dispose resources and close streams
  Future<void> dispose() async {
    await _purchaseResultController.close();
    await _errorController.close();
    RustoreBillingCallbackApi.setUp(null);
    _callbackApi = null;
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
