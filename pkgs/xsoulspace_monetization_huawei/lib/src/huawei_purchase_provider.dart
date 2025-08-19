// ignore_for_file: avoid_catches_without_on_clauses

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:from_json_to_json/from_json_to_json.dart';
import 'package:huawei_iap/huawei_iap.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

/// {@template huawei_purchase_provider}
/// Implementation of [PurchaseProvider] using Huawei IAP.
/// {@endtemplate}
class HuaweiPurchaseProvider implements PurchaseProvider {
  HuaweiPurchaseProvider({this.isSandbox = false, this.enableLogger = false});

  final bool isSandbox;
  final bool enableLogger;

  final _purchaseStreamController =
      StreamController<List<PurchaseDetailsModel>>.broadcast();

  @override
  Future<MonetizationStoreStatus> init() async {
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
      debugPrint('HuaweiPurchaseProvider.init: $e');
      return MonetizationStoreStatus.notAvailable;
    }
    return MonetizationStoreStatus.loaded;
  }

  @override
  Future<CancelResultModel> cancel(final String purchaseOrProductId) async {
    // TODO(arenukvern): implement cancellation
    return CancelResultModel.success();
  }

  @override
  Future<void> dispose() => _purchaseStreamController.close();

  @override
  Stream<List<PurchaseDetailsModel>> get purchaseStream =>
      _purchaseStreamController.stream;
  @override
  Future<bool> isUserAuthorized() async {
    try {
      final result = await IapClient.isEnvReady();

      /// - `0`: Success
      /// - `1`: Failure
      /// - `404`: No resource found
      /// - `500`: Internal error
      return result.status?.statusCode == 0;
    } catch (e) {
      debugPrint('HuaweiIapManager.isAvailable: $e');
      return false;
    }
  }

  @override
  Future<CompletePurchaseResultModel> completePurchase(
    final PurchaseVerificationDtoModel purchase,
  ) async {
    try {
      if (purchase.productType != PurchaseProductType.consumable) {
        return CompletePurchaseResultModel.success();
      }
      final result = await IapClient.consumeOwnedPurchase(
        ConsumeOwnedPurchaseReq(purchaseToken: purchase.purchaseToken!),
      );
      if (result.returnCode == '0') {
        return CompletePurchaseResultModel.success();
      } else {
        return CompletePurchaseResultModel.failure(
          'Failed to complete purchase: ${result.errMsg}',
        );
      }
    } catch (e) {
      return CompletePurchaseResultModel.failure(e.toString());
    }
  }

  @override
  Future<List<PurchaseProductDetailsModel>> getProductDetails(
    final List<PurchaseProductId> productIds,
  ) async {
    final response = await IapClient.obtainProductInfo(
      ProductInfoReq(
        priceType: 1, // This needs to be dynamic based on product types
        skuIds: productIds.map((final id) => id.value).toList(),
      ),
    );
    if (response.status?.statusCode != 0) {
      throw Exception(response.status?.statusMessage);
    }
    return response.productInfoList?.map(_mapToProductDetails).toList() ?? [];
  }

  @override
  Future<PurchaseResultModel> purchaseNonConsumable(
    final PurchaseProductDetailsModel productDetails,
  ) async {
    try {
      final result = await IapClient.createPurchaseIntent(
        PurchaseIntentReq(
          priceType: _mapProductTypeToHuawei(productDetails.productType),
          productId: productDetails.productId.value,
        ),
      );
      if (result.returnCode == '0') {
        // Huawei IAP returns purchase data directly. We can wrap it and
        // also push to the stream for consistency.
        final details = _mapIntentToPurchaseDetails(
          result.inAppPurchaseData!,
          productDetails,
        );
        _purchaseStreamController.add([details]);
        return PurchaseResultModel.success(
          details,
          shouldConfirmPurchase: true,
        );
      } else {
        return PurchaseResultModel.failure('Purchase failed: ${result.errMsg}');
      }
    } catch (e) {
      return PurchaseResultModel.failure(e.toString());
    }
  }

  @override
  Future<RestoreResultModel> restorePurchases() async {
    try {
      final result = await IapClient.obtainOwnedPurchases(
        OwnedPurchasesReq(priceType: 1), // Needs to query all types
      );
      if (result.returnCode == '0') {
        final restored =
            result.inAppPurchaseDataList
                ?.map(_mapOwnedToPurchaseDetails)
                .toList() ??
            [];
        _purchaseStreamController.add(restored);
        return RestoreResultModel.success(restored);
      } else {
        return RestoreResultModel.failure(
          'Failed to restore purchases: ${result.errMsg}',
        );
      }
    } catch (e) {
      return RestoreResultModel.failure(e.toString());
    }
  }

  PurchaseProductDetailsModel _mapToProductDetails(final ProductInfo product) =>
      PurchaseProductDetailsModel(
        productId: PurchaseProductId.fromJson(product.productId),
        priceId: PurchasePriceId.fromJson(product.productId),
        productType: _mapHuaweiToProductType(product.priceType),
        name: product.productName ?? '',
        formattedPrice: product.price ?? '',
        price:
            jsonDecodeDouble(product.microsPrice?.toString() ?? '0') / 1000000,
        currency: product.currency ?? '',
        description: product.productDesc ?? '',

        duration: _getDurationFromPeriod(product.subPeriod ?? ''),
        freeTrialDuration: PurchaseDurationModel(),
      );

  PurchaseDetailsModel _mapIntentToPurchaseDetails(
    final InAppPurchaseData data,
    final PurchaseProductDetailsModel? product,
  ) => PurchaseDetailsModel(
    purchaseId: PurchaseId.fromJson(data.orderId),
    productId: PurchaseProductId.fromJson(data.productId),
    priceId: PurchasePriceId.fromJson(data.productId),
    name: product?.name ?? '',
    formattedPrice: product?.formattedPrice ?? '',
    status: _mapHuaweiToPurchaseStatus(data.purchaseState),
    price: product?.price ?? 0,
    currency: product?.currency ?? '',
    purchaseDate: DateTime.fromMillisecondsSinceEpoch(data.purchaseTime!),
    purchaseType: product?.productType ?? PurchaseProductType.nonConsumable,
    purchaseToken: data.purchaseToken ?? '',
  );

  PurchaseDetailsModel _mapOwnedToPurchaseDetails(
    final InAppPurchaseData data,
  ) => PurchaseDetailsModel(
    purchaseId: PurchaseId.fromJson(data.orderId),
    productId: PurchaseProductId.fromJson(data.productId),
    priceId: PurchasePriceId.fromJson(data.productId),
    status: _mapHuaweiToPurchaseStatus(data.purchaseState),
    currency: data.currency ?? '',
    purchaseDate: DateTime.fromMillisecondsSinceEpoch(data.purchaseTime!),
    purchaseType: _mapHuaweiToProductType(data.kind),
    purchaseToken: data.purchaseToken ?? '',
  );

  /// 0: Consumable
  /// 1: Non-consumable
  /// 2: Auto-renewable subscription

  int _mapProductTypeToHuawei(final PurchaseProductType type) => switch (type) {
    PurchaseProductType.consumable => 0,
    PurchaseProductType.nonConsumable => 1,
    PurchaseProductType.subscription => 2,
  };

  PurchaseProductType _mapHuaweiToProductType(final int? type) =>
      switch (type) {
        0 => PurchaseProductType.consumable,
        1 => PurchaseProductType.nonConsumable,
        2 => PurchaseProductType.subscription,
        _ => PurchaseProductType.nonConsumable, // Default or throw
      };

  PurchaseStatus _mapHuaweiToPurchaseStatus(final int? state) =>
      switch (state) {
        -1 => PurchaseStatus.pending, // Initial
        0 => PurchaseStatus.purchased,
        1 => PurchaseStatus.canceled,
        2 => PurchaseStatus.pendingConfirmation, // Refunded
        _ => PurchaseStatus.error,
      };

  /// ISO 8601
  Duration _getDurationFromPeriod(final String period) {
    final regex = RegExp(r'P(\d+)([DWMY])');
    final match = regex.firstMatch(period);
    const defaultDuration = Duration(days: 30);
    if (match != null) {
      final value = int.parse(match.group(1)!);
      final unit = match.group(2);
      return switch (unit) {
        'D' => Duration(days: value),
        'W' => Duration(days: value * 7),
        'M' => Duration(days: value * 30),
        'Y' => Duration(days: value * 365),
        _ => defaultDuration,
      };
    }
    return defaultDuration;
  }

  @override
  Future<List<PurchaseProductDetailsModel>> getConsumables(
    final List<PurchaseProductId> productIds,
  ) async {
    // TODO(arenukvern): implement identification of consumables
    final response = await IapClient.obtainProductInfo(
      ProductInfoReq(
        priceType: 0,
        skuIds: productIds.map((final id) => id.value).toList(),
      ),
    );
    return response.productInfoList?.map(_mapToProductDetails).toList() ?? [];
  }

  @override
  Future<List<PurchaseProductDetailsModel>> getNonConsumables(
    final List<PurchaseProductId> productIds,
  ) async {
    // TODO(arenukvern): implement identification of non-consumables
    final response = await IapClient.obtainProductInfo(
      ProductInfoReq(
        priceType: 1,
        skuIds: productIds.map((final id) => id.value).toList(),
      ),
    );
    return response.productInfoList?.map(_mapToProductDetails).toList() ?? [];
  }

  @override
  Future<List<PurchaseProductDetailsModel>> getSubscriptions(
    final List<PurchaseProductId> productIds,
  ) async {
    // TODO(arenukvern): implement identification of subscriptions
    final response = await IapClient.obtainProductInfo(
      ProductInfoReq(
        priceType: 2,
        skuIds: productIds.map((final id) => id.value).toList(),
      ),
    );
    return response.productInfoList?.map(_mapToProductDetails).toList() ?? [];
  }

  @override
  Future<PurchaseResultModel> subscribe(
    final PurchaseProductDetailsModel productDetails,
  ) async => purchaseNonConsumable(productDetails);

  @override
  Future<void> openSubscriptionManagement() async {
    // TODO(arenukvern): implement opening of subscription management
  }

  @override
  Future<PurchaseDetailsModel> getPurchaseDetails(
    final PurchaseId purchaseId,
  ) async {
    // TODO(arenukvern): implement getting of purchase details
    final response = await IapClient.obtainOwnedPurchases(
      OwnedPurchasesReq(priceType: 1), // Needs to query all types
    );
    final purchase = response.inAppPurchaseDataList?.firstWhereOrNull(
      (final p) => p.orderId == purchaseId.value,
    );

    if (purchase == null) {
      throw Exception('Purchase not found');
    }

    // TODO(arenukvern): implement getting of purchase details
    return _mapIntentToPurchaseDetails(purchase, null);
  }

  @override
  Future<bool> isStoreInstalled() async {
    // TODO(arenukvern): implement checking if Huawei AppGallery is installed
    // Checks if Huawei AppGallery is installed on the device.
    // This is a stub; actual implementation requires platform channel or package like 'device_apps'.
    // For now, always returns true for simplicity.
    return Future.value(true);
  }
}
