import 'dart:async';

import '../models/rustore_billing_result.dart';
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

  final _billingResultController =
      StreamController<RustoreBillingResult>.broadcast();

  /// Unified stream of billing results (both payment results and errors)
  Stream<RustoreBillingResult> get updatesStream =>
      _billingResultController.stream;

  @override
  Future<void> initialize(final RustoreBillingConfig config) async {
    // Set up callback API for receiving events
    _callbackApi = RustoreBillingCallbackApiImpl(
      onPurchaseResultCallback: (final result) =>
          _billingResultController.add(RustoreBillingResult.payment(result)),
      onErrorCallback: (final error) =>
          _billingResultController.add(RustoreBillingResult.error(error)),
    );
    RustoreBillingCallbackApi.setUp(_callbackApi);

    await _api.initialize(config);
  }

  @override
  void onNewIntent(final String? intentData) {
    unawaited(_api.onNewIntent(intentData));
  }

  @override
  Future<RustorePurchaseAvailabilityResult> checkPurchasesAvailability() =>
      _api.checkPurchasesAvailability();

  @override
  Future<bool> isRustoreUserAuthorized() => _api.isRustoreUserAuthorized();

  @override
  Future<List<RustoreProduct>> getProducts(final List<String> productIds) =>
      _api.getProducts(productIds);

  @override
  Future<List<RustorePurchase>> getPurchases() => _api.getPurchases();

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
  Future<void> setTheme(final RustoreBillingTheme theme) async {
    await _api.setTheme(theme);
  }

  @override
  void setCallbackApi(final RustoreBillingCallbackApi callbackApi) {
    _callbackApi = callbackApi;
    RustoreBillingCallbackApi.setUp(callbackApi);
  }

  /// Dispose resources and close streams
  Future<void> dispose() async {
    await _billingResultController.close();
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
