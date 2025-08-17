import 'package:flutter/services.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

class AppleNativePurchaseProvider {
  static const _purchasesChannel = MethodChannel(
    'dev.xsoulspace.monetization/purchases',
  );
  static const _cancelSubChannel = MethodChannel(
    'dev.xsoulspace.monetization/cancelSubscription',
  );

  Future<List<PurchaseProductDetailsModel>> fetchProducts(
    final List<PurchaseProductId> productIds,
  ) async {
    try {
      final result = await _purchasesChannel.invokeMethod<List<dynamic>>(
        'fetchProducts',
        productIds.map((final e) => e.value).toSet(),
      );
      if (result == null) return [];
      return result.map(PurchaseProductDetailsModel.fromJson).toList();
    } on PlatformException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<PurchaseResultModel> purchaseProduct(
    final PurchaseProductDetailsModel productDetails,
  ) async {
    try {
      final result = await _purchasesChannel.invokeMethod<String>(
        'purchaseProduct',
        productDetails.productId.value,
      );
      if (result == null) {
        return PurchaseResultModel.failure('Purchase failed.');
      }
      return PurchaseResultModel.success(
        PurchaseDetailsModel(
          purchaseId: PurchaseId.fromJson(result),
          productId: productDetails.productId,
          priceId: productDetails.priceId,
          status: PurchaseStatus.purchased,
          purchaseDate: DateTime.now(),
          purchaseType: PurchaseProductType.nonConsumable,
          source: 'app_store',
          name: productDetails.name,
          duration: productDetails.duration,
          freeTrialDuration: productDetails.freeTrialDuration.duration,
        ),
        shouldConfirmPurchase: false,
      );
    } on PlatformException catch (e) {
      return PurchaseResultModel.failure(e.message ?? 'Unknown error');
    }
  }

  Future<CancelResultModel> cancelSubscription() async {
    try {
      await _cancelSubChannel.invokeMethod('showCancelSubSheet');
      return CancelResultModel.success();
    } on PlatformException catch (e) {
      return CancelResultModel.failure(e.message ?? 'Unknown error');
    }
  }
}
