// ignore_for_file: avoid_catches_without_on_clauses

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:huawei_iap/huawei_iap.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

/// {@template huawai_purchase_provider}
/// Implementation of [PurchaseProvider] using Huawei IAP.
/// {@endtemplate}
class HuawaiPurchaseProvider implements PurchaseProvider {
  HuawaiPurchaseProvider({this.isSandbox = false, this.enableLogger = false});

  final bool isSandbox;
  final bool enableLogger;

  final _purchaseStreamController =
      StreamController<List<PurchaseDetails>>.broadcast();

  Future<void> init() async {
    try {
      if (enableLogger) {
        await IapClient.enableLogger();
      }
      if (isSandbox) {
        final isSandboxResult = await IapClient.isSandboxActivated();
        if (isSandboxResult.isSandboxApk != true) {
          throw UnsupportedError('Sandbox is not available');
        }
      }
    } catch (e) {
      debugPrint('HuawaiPurchaseProvider.init: $e');
    }
  }

  void dispose() {
    _purchaseStreamController.close();
  }

  @override
  Stream<List<PurchaseDetails>> get purchaseStream =>
      _purchaseStreamController.stream;

  @override
  Future<bool> isAvailable() async {
    try {
      final result = await IapClient.isEnvReady();
      return result.status?.statusCode == 0;
    } catch (e) {
      debugPrint('HuawaiPurchaseProvider.isAvailable: $e');
      return false;
    }
  }

  @override
  Future<CompletePurchaseResult> completePurchase(
    PurchaseVerificationDto purchase,
  ) async {
    try {
      if (purchase.productType != PurchaseProductType.consumable) {
        return const CompletePurchaseResult.success();
      }
      final result = await IapClient.consumeOwnedPurchase(
        ConsumeOwnedPurchaseReq(purchaseToken: purchase.purchaseToken!),
      );
      if (result.returnCode == '0') {
        return const CompletePurchaseResult.success();
      } else {
        return CompletePurchaseResult.failure(
          'Failed to complete purchase: ${result.errMsg}',
        );
      }
    } catch (e) {
      return CompletePurchaseResult.failure(e.toString());
    }
  }

  @override
  Future<List<PurchaseProductDetails>> getProductDetails(
    List<PurchaseProductId> productIds,
  ) async {
    final response = await IapClient.obtainProductInfo(
      ProductInfoReq(
        priceType: 1, // This needs to be dynamic based on product types
        skuIds: productIds.map((id) => id.value).toList(),
      ),
    );
    if (response.status?.statusCode != 0) {
      throw Exception(response.status?.statusMessage);
    }
    return response.productInfoList?.map(_mapToProductDetails).toList() ?? [];
  }

  @override
  Future<PurchaseResult> purchase(PurchaseProductDetails productDetails) async {
    try {
      final result = await IapClient.createPurchaseIntent(
        CreatePurchaseIntentReq(
          priceType: _mapProductTypeToHuawei(productDetails.productType),
          productId: productDetails.productId.value,
        ),
      );
      if (result.returnCode == OrderStatusCode.orderStateSuccess) {
        // Huawei IAP returns purchase data directly. We can wrap it and
        // also push to the stream for consistency.
        final details = _mapIntentToPurchaseDetails(
          result.inAppPurchaseData!,
          productDetails,
        );
        _purchaseStreamController.add([details]);
        return PurchaseResult.success(details);
      } else {
        return PurchaseResult.failure('Purchase failed: ${result.errMsg}');
      }
    } catch (e) {
      return PurchaseResult.failure(e.toString());
    }
  }

  @override
  Future<RestoreResult> restorePurchases() async {
    try {
      final result = await IapClient.obtainOwnedPurchases(
        OwnedPurchasesReq(priceType: 1), // Needs to query all types
      );
      if (result.returnCode == OrderStatusCode.orderStateSuccess) {
        final restored =
            result.inAppPurchaseDataList
                ?.map((p) => _mapOwnedToPurchaseDetails(p))
                .toList() ??
            [];
        _purchaseStreamController.add(restored);
        return RestoreResult.success(restored);
      } else {
        return RestoreResult.failure(
          'Failed to restore purchases: ${result.errMsg}',
        );
      }
    } catch (e) {
      return RestoreResult.failure(e.toString());
    }
  }

  PurchaseProductDetails _mapToProductDetails(ProductInfo product) {
    return PurchaseProductDetails(
      productId: PurchaseProductId(product.productId!),
      productType: _mapHuaweiToProductType(product.priceType),
      name: product.productName ?? '',
      formattedPrice: product.price ?? '',
      price: double.tryParse(product.microsPrice?.toString() ?? '0')! / 1000000,
      currency: product.currency ?? '',
      description: product.productDesc ?? '',
    );
  }

  PurchaseDetails _mapIntentToPurchaseDetails(
    InAppPurchaseData data,
    PurchaseProductDetails product,
  ) {
    return PurchaseDetails(
      purchaseId: PurchaseId(data.orderId!),
      productId: PurchaseProductId(data.productId!),
      name: product.name,
      formattedPrice: product.formattedPrice,
      status: _mapHuaweiToPurchaseStatus(data.purchaseState),
      price: product.price,
      currency: product.currency,
      purchaseDate: DateTime.fromMillisecondsSinceEpoch(data.purchaseTime!),
      purchaseType: product.productType,
      purchaseToken: data.purchaseToken,
    );
  }

  PurchaseDetails _mapOwnedToPurchaseDetails(InAppPurchaseData data) {
    return PurchaseDetails(
      purchaseId: PurchaseId(data.orderId!),
      productId: PurchaseProductId(data.productId!),
      name: '', // Not available in owned purchases
      formattedPrice: '', // Not available
      status: _mapHuaweiToPurchaseStatus(data.purchaseState),
      price: 0, // Not available
      currency: data.currency ?? '',
      purchaseDate: DateTime.fromMillisecondsSinceEpoch(data.purchaseTime!),
      purchaseType: _mapHuaweiToProductType(data.kind),
      purchaseToken: data.purchaseToken,
    );
  }

  int _mapProductTypeToHuawei(PurchaseProductType type) => switch (type) {
    PurchaseProductType.consumable => PriceType.priceTypeConsumable,
    PurchaseProductType.nonConsumable => PriceType.priceTypeNonconsumable,
    PurchaseProductType.subscription => PriceType.priceTypeSubscription,
  };

  PurchaseProductType _mapHuaweiToProductType(int? type) => switch (type) {
    PriceType.priceTypeConsumable => PurchaseProductType.consumable,
    PriceType.priceTypeNonconsumable => PurchaseProductType.nonConsumable,
    PriceType.priceTypeSubscription => PurchaseProductType.subscription,
    _ => PurchaseProductType.nonConsumable, // Default or throw
  };

  PurchaseStatus _mapHuaweiToPurchaseStatus(int? state) => switch (state) {
    -1 => PurchaseStatus.pending, // Initial
    0 => PurchaseStatus.purchased,
    1 => PurchaseStatus.canceled,
    2 => PurchaseStatus.restored, // Refunded
    _ => PurchaseStatus.error,
  };
}
