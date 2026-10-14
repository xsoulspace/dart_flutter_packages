import 'dart:async';

import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

/// Purchase provider that returns deterministic no-op responses.
class NoopPurchaseProvider implements PurchaseProvider {
  final StreamController<List<PurchaseDetailsModel>> _purchaseController =
      StreamController<List<PurchaseDetailsModel>>.broadcast();

  @override
  Stream<List<PurchaseDetailsModel>> get purchaseStream =>
      _purchaseController.stream;

  @override
  Future<MonetizationStoreStatus> init() async =>
      MonetizationStoreStatus.notAvailable;

  @override
  Future<bool> isUserAuthorized() async => false;

  @override
  Future<bool> isStoreInstalled() async => false;

  @override
  Future<List<PurchaseProductDetailsModel>> getConsumables(
    List<PurchaseProductId> productIds,
  ) async => const <PurchaseProductDetailsModel>[];

  @override
  Future<List<PurchaseProductDetailsModel>> getNonConsumables(
    List<PurchaseProductId> productIds,
  ) async => const <PurchaseProductDetailsModel>[];

  @override
  Future<List<PurchaseProductDetailsModel>> getProductDetails(
    List<PurchaseProductId> productIds,
  ) async => const <PurchaseProductDetailsModel>[];

  @override
  Future<List<PurchaseProductDetailsModel>> getSubscriptions(
    List<PurchaseProductId> productIds,
  ) async => const <PurchaseProductDetailsModel>[];

  @override
  Future<PurchaseDetailsModel> getPurchaseDetails(PurchaseId productId) {
    return Future<PurchaseDetailsModel>.error(
      UnsupportedError('NoopPurchaseProvider does not store purchase details.'),
    );
  }

  @override
  Future<PurchaseResultModel> purchaseNonConsumable(
    PurchaseProductDetailsModel productDetails,
  ) async =>
      PurchaseResultModel.failure('Purchases are disabled in no-op mode.');

  @override
  Future<RestoreResultModel> restorePurchases() async =>
      RestoreResultModel.success(const <PurchaseDetailsModel>[]);

  @override
  Future<CompletePurchaseResultModel> completePurchase(
    PurchaseVerificationDtoModel purchase,
  ) async => CompletePurchaseResultModel.success();

  @override
  Future<PurchaseResultModel> subscribe(
    PurchaseProductDetailsModel productDetails,
  ) async =>
      PurchaseResultModel.failure('Subscriptions are disabled in no-op mode.');

  @override
  Future<CancelResultModel> cancel(String purchaseOrProductId) async =>
      CancelResultModel.success();

  @override
  Future<void> openSubscriptionManagement() async {}

  @override
  Future<void> dispose() async {
    await _purchaseController.close();
  }
}
