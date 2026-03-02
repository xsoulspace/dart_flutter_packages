import 'dart:async';

import '../models/rustore_billing_result.dart';
import '../rustore_api.g.dart';
import '../rustore_billing_platform.dart';

class RustoreBillingAndroid extends RustoreBillingPlatform {
  RustoreBillingAndroid._() : super();

  static void registerWith() {
    RustoreBillingPlatform.instance = RustoreBillingAndroid._();
  }

  final RustoreBillingApi _api = RustoreBillingApi();
  RustoreBillingCallbackApi? _callbackApi;

  final StreamController<RustoreBillingResult> _billingResultController =
      StreamController<RustoreBillingResult>.broadcast();

  Stream<RustoreBillingResult> get updatesStream =>
      _billingResultController.stream;

  @override
  Future<void> initialize(final RustoreBillingConfig config) async {
    _callbackApi = RustoreBillingCallbackApiImpl(
      onPurchaseResultCallback: (final result) {
        _billingResultController.add(RustoreBillingResult.purchase(result));
      },
      onPurchaseErrorCallback: (final error) {
        _billingResultController.add(RustoreBillingResult.error(error));
      },
    );
    RustoreBillingCallbackApi.setUp(_callbackApi);
    await _api.initialize(config);
  }

  @override
  Future<RustorePurchaseAvailabilityResult> getPurchaseAvailability() =>
      _api.getPurchaseAvailability();

  @override
  Future<bool> getUserAuthorizationStatus() =>
      _api.getUserAuthorizationStatus();

  @override
  Future<List<RustoreProduct>> getProducts(final List<String> productIds) =>
      _api.getProducts(productIds);

  @override
  Future<List<RustorePurchase>> getPurchases(
    final RustorePurchaseFilter? filter,
  ) => _api.getPurchases(filter);

  @override
  Future<RustorePurchase?> getPurchase(final String purchaseId) =>
      _api.getPurchase(purchaseId);

  @override
  Future<RustoreProductPurchaseResult> purchase(
    final RustoreProductPurchaseParams params, {
    final RustorePreferredPurchaseType preferredPurchaseType =
        RustorePreferredPurchaseType.unknown,
    final RustoreBillingTheme sdkTheme = RustoreBillingTheme.system,
  }) => _api.purchase(params, preferredPurchaseType, sdkTheme);

  @override
  Future<RustoreProductPurchaseResult> purchaseTwoStep(
    final RustoreProductPurchaseParams params, {
    final RustoreBillingTheme sdkTheme = RustoreBillingTheme.system,
  }) => _api.purchaseTwoStep(params, sdkTheme);

  @override
  Future<void> confirmTwoStepPurchase(
    final String purchaseId, {
    final String? developerPayload,
  }) async {
    await _api.confirmTwoStepPurchase(purchaseId, developerPayload);
  }

  @override
  Future<void> cancelTwoStepPurchase(final String purchaseId) async {
    await _api.cancelTwoStepPurchase(purchaseId);
  }

  @override
  void setCallbackApi(final RustoreBillingCallbackApi callbackApi) {
    _callbackApi = callbackApi;
    RustoreBillingCallbackApi.setUp(callbackApi);
  }

  Future<void> dispose() async {
    await _billingResultController.close();
    RustoreBillingCallbackApi.setUp(null);
    _callbackApi = null;
  }
}

class RustoreBillingCallbackApiImpl extends RustoreBillingCallbackApi {
  RustoreBillingCallbackApiImpl({
    required this.onPurchaseResultCallback,
    required this.onPurchaseErrorCallback,
  });

  final void Function(RustoreProductPurchaseResult result)
  onPurchaseResultCallback;
  final void Function(RustorePurchaseError error) onPurchaseErrorCallback;

  @override
  void onPurchaseResult(final RustoreProductPurchaseResult result) {
    onPurchaseResultCallback(result);
  }

  @override
  void onPurchaseError(final RustorePurchaseError error) {
    onPurchaseErrorCallback(error);
  }
}
