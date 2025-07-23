import 'dart:async';

import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

/// A no-op implementation of [PurchaseProvider] that simulates successful
/// purchases without any real transactions. Useful for development, testing,
/// or for monetization models that do not include real purchases.
class NoopPurchaseProvider implements PurchaseProvider {
  final _purchaseStreamController =
      StreamController<List<PurchaseDetailsModel>>.broadcast();

  @override
  Stream<List<PurchaseDetailsModel>> get purchaseStream =>
      _purchaseStreamController.stream;

  @override
  Future<MonetizationStatus> init() async => MonetizationStatus.notAvailable;

  @override
  Future<CompletePurchaseResultModel> completePurchase(
    final PurchaseVerificationDtoModel details,
  ) async => CompletePurchaseResultModel.success();

  @override
  Future<PurchaseDetailsModel> getPurchaseDetails(
    final PurchaseId purchaseId,
  ) async => throw UnimplementedError(
    'getPurchaseDetails is not implemented in NoOpPurchaseProvider',
  );

  @override
  Future<List<PurchaseProductDetailsModel>> getSubscriptions(
    final List<PurchaseProductId> productIds,
  ) async => [];

  @override
  Future<List<PurchaseProductDetailsModel>> getNonConsumables(
    final List<PurchaseProductId> productIds,
  ) async => [];

  @override
  Future<CancelResultModel> cancel(final PurchaseProductId productId) async =>
      CancelResultModel.success();

  @override
  Future<void> dispose() async {
    await _purchaseStreamController.close();
  }

  @override
  Future<List<PurchaseProductDetailsModel>> getConsumables(
    final List<PurchaseProductId> productIds,
  ) async => [];
  @override
  Future<bool> isUserAuthorized() async => false;

  @override
  Future<void> openSubscriptionManagement() async =>
      throw UnimplementedError('Not supported');

  @override
  Future<PurchaseResultModel> purchaseNonConsumable(
    final PurchaseProductDetailsModel productDetails,
  ) async => PurchaseResultModel.failure('Not supported');

  @override
  Future<RestoreResultModel> restorePurchases() async =>
      RestoreResultModel.failure('Not supported');

  @override
  Future<PurchaseResultModel> subscribe(
    final PurchaseProductDetailsModel productDetails,
  ) async => PurchaseResultModel.failure('Not supported');

  @override
  Future<List<PurchaseProductDetailsModel>> getProductDetails(
    final List<PurchaseProductId> productIds,
  ) async => [];

  @override
  Future<bool> isStoreInstalled() async => false;
}
