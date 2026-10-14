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
  Future<void> initialize(RustoreBillingConfig config) async {
    _callbackApi = RustoreBillingCallbackApiImpl(
      onPurchaseResultCallback: (result) {
        _billingResultController.add(RustoreBillingResult.purchase(result));
      },
      onPurchaseErrorCallback: (error) {
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
  Future<List<RustoreProduct>> getProducts(List<String> productIds) =>
      _api.getProducts(productIds);

  @override
  Future<List<RustorePurchase>> getPurchases(
    RustorePurchaseFilter? filter,
  ) => _api.getPurchases(filter);

  @override
  Future<RustorePurchase?> getPurchase(String purchaseId) =>
      _api.getPurchase(purchaseId);

  @override
  Future<RustoreProductPurchaseResult> purchase(
    RustoreProductPurchaseParams params, {
    RustorePreferredPurchaseType preferredPurchaseType =
        RustorePreferredPurchaseType.unknown,
    RustoreBillingTheme sdkTheme = RustoreBillingTheme.system,
  }) => _api.purchase(params, preferredPurchaseType, sdkTheme);

  @override
  Future<RustoreProductPurchaseResult> purchaseTwoStep(
    RustoreProductPurchaseParams params, {
    RustoreBillingTheme sdkTheme = RustoreBillingTheme.system,
  }) => _api.purchaseTwoStep(params, sdkTheme);

  @override
  Future<void> confirmTwoStepPurchase(
    String purchaseId, {
    String? developerPayload,
  }) async {
    await _api.confirmTwoStepPurchase(purchaseId, developerPayload);
  }

  @override
  Future<void> cancelTwoStepPurchase(String purchaseId) async {
    await _api.cancelTwoStepPurchase(purchaseId);
  }

  @override
  void setCallbackApi(RustoreBillingCallbackApi callbackApi) {
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
  void onPurchaseResult(RustoreProductPurchaseResult result) {
    onPurchaseResultCallback(result);
  }

  @override
  void onPurchaseError(RustorePurchaseError error) {
    onPurchaseErrorCallback(error);
  }
}
