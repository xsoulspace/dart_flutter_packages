// ignore_for_file: avoid_catches_without_on_clauses

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:from_json_to_json/from_json_to_json.dart';
import 'package:huawei_iap/huawei_iap.dart';
import 'package:url_launcher/url_launcher_string.dart';
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
    try {
      // Huawei IAP doesn't provide direct API for subscription cancellation
      // Redirect user to subscription management page where they can cancel
      await openSubscriptionManagement();
      return CancelResultModel.success();
    } catch (e) {
      return CancelResultModel.failure(
        'Failed to open subscription management: $e',
      );
    }
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
        return PurchaseResultModel.success(details);
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
      // Query all product types: 0 (consumable), 1 (non-consumable), 2 (subscription)
      final results = await Future.wait([
        IapClient.obtainOwnedPurchases(OwnedPurchasesReq(priceType: 0)),
        IapClient.obtainOwnedPurchases(OwnedPurchasesReq(priceType: 1)),
        IapClient.obtainOwnedPurchases(OwnedPurchasesReq(priceType: 2)),
      ]);

      final restored = <PurchaseDetailsModel>[];
      for (final result in results) {
        if (result.returnCode == '0') {
          final purchases =
              result.inAppPurchaseDataList
                  ?.map(_mapOwnedToPurchaseDetails)
                  .toList() ??
              [];
          restored.addAll(purchases);
        }
      }

      _purchaseStreamController.add(restored);
      return RestoreResultModel.success(restored);
    } catch (e) {
      return RestoreResultModel.failure(e.toString());
    }
  }

  PurchaseProductDetailsModel _mapToProductDetails(final ProductInfo product) {
    final duration = _getDurationFromPeriod(product.subPeriod ?? '');

    // Try to extract free trial period from Huawei's ProductInfo
    // Huawei may provide subFreeTrialPeriod or similar field
    final freeTrialDuration = _extractFreeTrialDuration(product);

    return PurchaseProductDetailsModel(
      productId: PurchaseProductId.fromJson(product.productId),
      priceId: PurchasePriceId.fromJson(product.productId),
      productType: _mapHuaweiToProductType(product.priceType),
      name: product.productName ?? '',
      formattedPrice: product.price ?? '',
      price: jsonDecodeDouble(product.microsPrice?.toString() ?? '0'),
      currency: product.currency ?? '',
      description: product.productDesc ?? '',
      duration: duration,
      freeTrialDuration: freeTrialDuration,
    );
  }

  PurchaseDetailsModel _mapIntentToPurchaseDetails(
    final InAppPurchaseData data,
    final PurchaseProductDetailsModel? product,
  ) {
    final rawPurchaseTime = data.purchaseTime;
    final purchaseDate = rawPurchaseTime != null
        ? DateTime.fromMillisecondsSinceEpoch(rawPurchaseTime)
        : DateTime.now();
    final productType =
        product?.productType ?? PurchaseProductType.nonConsumable;
    final duration = product?.duration ?? Duration.zero;

    // Calculate expiry date for subscriptions
    final expiryDate = _calculateExpiryDate(
      data,
      purchaseDate,
      productType,
      duration,
    );

    return PurchaseDetailsModel(
      purchaseId: PurchaseId.fromJson(data.orderId),
      productId: PurchaseProductId.fromJson(data.productId),
      priceId: PurchasePriceId.fromJson(data.productId),
      name: product?.name ?? '',
      formattedPrice: product?.formattedPrice ?? '',
      status: _mapHuaweiToPurchaseStatus(data.purchaseState),
      price: product?.price ?? 0,
      currency: product?.currency ?? '',
      purchaseDate: purchaseDate,
      purchaseType: productType,
      purchaseToken: data.purchaseToken ?? '',
      expiryDate: expiryDate,
      duration: duration,
      freeTrialDuration: product?.freeTrialDuration.duration ?? Duration.zero,
    );
  }

  PurchaseDetailsModel _mapOwnedToPurchaseDetails(
    final InAppPurchaseData data,
  ) {
    final rawPurchaseTime = data.purchaseTime;
    final purchaseDate = rawPurchaseTime != null
        ? DateTime.fromMillisecondsSinceEpoch(rawPurchaseTime)
        : DateTime.now();
    final productType = _mapHuaweiToProductType(data.kind);

    // Note: InAppPurchaseData doesn't include subscription period info
    // Duration must be obtained from product details separately
    const duration = Duration.zero;

    // Calculate expiry date for subscriptions
    final expiryDate = _calculateExpiryDate(
      data,
      purchaseDate,
      productType,
      duration,
    );

    return PurchaseDetailsModel(
      purchaseId: PurchaseId.fromJson(data.orderId),
      productId: PurchaseProductId.fromJson(data.productId),
      priceId: PurchasePriceId.fromJson(data.productId),
      status: _mapHuaweiToPurchaseStatus(data.purchaseState),
      currency: data.currency ?? '',
      purchaseDate: purchaseDate,
      purchaseType: productType,
      purchaseToken: data.purchaseToken ?? '',
      expiryDate: expiryDate,
    );
  }

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

  /// Maps Huawei purchase states to internal status
  ///
  /// Huawei IAP purchase states:
  /// - `-1`: Initial/Pending - purchase initiated but not yet confirmed
  /// - `0`: Purchased - successfully completed and owned
  /// - `1`: Canceled - user cancelled the purchase
  /// - `2`: Refunded - purchase was refunded
  /// - `3+`: Other states (errors, expired, etc.)
  ///
  /// For subscriptions:
  /// - Active subscriptions have state 0 (purchased)
  /// - Expired subscriptions may have state 1 (canceled)
  /// - Grace period subscriptions remain in state 0
  PurchaseStatus _mapHuaweiToPurchaseStatus(final int? state) =>
      switch (state) {
        -1 => PurchaseStatus.pendingVerification, // Initial/pending purchase
        0 => PurchaseStatus.purchased, // Successfully purchased
        1 => PurchaseStatus.canceled, // User cancelled
        2 => PurchaseStatus.pendingVerification, // Refunded, needs verification
        _ => PurchaseStatus.error, // Unknown or error state
      };

  /// Parses ISO 8601 duration format (e.g., P1Y, P1M, P7D)
  Duration _getDurationFromPeriod(final String period) =>
      jsonDecodeDurationFromISO8601(period);

  /// Extracts free trial duration from Huawei ProductInfo
  ///
  /// Huawei may provide trial period in various formats.
  /// This attempts to parse it similar to the subscription period.
  PurchaseDurationModel _extractFreeTrialDuration(final ProductInfo product) {
    try {
      // Attempt to access subFreeTrialPeriod or similar fields
      // Note: Actual field name may vary based on Huawei IAP SDK version
      final trialPeriod = product.subFreeTrialPeriod ?? '';
      if (trialPeriod.isEmpty) {
        return PurchaseDurationModel.zero;
      }

      final duration = _getDurationFromPeriod(trialPeriod);
      return PurchaseDurationModel(
        years: duration.inDays ~/ 365,
        months: (duration.inDays % 365) ~/ 30,
        days: duration.inDays % 30,
      );
    } catch (e) {
      debugPrint('Failed to extract free trial duration: $e');
      return PurchaseDurationModel.zero;
    }
  }

  /// Calculates expiry date for subscriptions
  ///
  /// For subscriptions, calculates when the subscription will expire based on:
  /// 1. Huawei-provided expiry date (if available in InAppPurchaseData)
  /// 2. Purchase date + duration (fallback calculation)
  DateTime? _calculateExpiryDate(
    final InAppPurchaseData data,
    final DateTime purchaseDate,
    final PurchaseProductType productType,
    final Duration duration,
  ) {
    // Only subscriptions have expiry dates
    if (productType != PurchaseProductType.subscription) {
      return null;
    }

    try {
      // Try to get expiry date from Huawei data if available
      // Huawei may provide expirationDate, subEndTime, or similar fields
      if (data.expirationDate != null && data.expirationDate! > 0) {
        return DateTime.fromMillisecondsSinceEpoch(data.expirationDate!);
      }

      // Fallback: calculate from purchase date + duration
      if (duration > Duration.zero) {
        return purchaseDate.add(duration);
      }

      return null;
    } catch (e) {
      debugPrint('Failed to calculate expiry date: $e');
      // Fallback to purchase date + duration
      return duration > Duration.zero ? purchaseDate.add(duration) : null;
    }
  }

  @override
  Future<List<PurchaseProductDetailsModel>> getConsumables(
    final List<PurchaseProductId> productIds,
  ) async {
    final response = await IapClient.obtainProductInfo(
      ProductInfoReq(
        priceType: 0, // Consumables
        skuIds: productIds.map((final id) => id.value).toList(),
      ),
    );
    return response.productInfoList?.map(_mapToProductDetails).toList() ?? [];
  }

  @override
  Future<List<PurchaseProductDetailsModel>> getNonConsumables(
    final List<PurchaseProductId> productIds,
  ) async {
    final response = await IapClient.obtainProductInfo(
      ProductInfoReq(
        priceType: 1, // Non-consumables
        skuIds: productIds.map((final id) => id.value).toList(),
      ),
    );
    return response.productInfoList?.map(_mapToProductDetails).toList() ?? [];
  }

  @override
  Future<List<PurchaseProductDetailsModel>> getSubscriptions(
    final List<PurchaseProductId> productIds,
  ) async {
    final response = await IapClient.obtainProductInfo(
      ProductInfoReq(
        priceType: 2, // Subscriptions
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
    try {
      // Try to use IapClient to open subscription management
      // Huawei provides TYPE_SUBSCRIBE_MANAGER_ACTIVITY to open subscription settings
      try {
        await IapClient.startIapActivity(
          StartIapActivityReq(
            type: StartIapActivityReq.TYPE_SUBSCRIBE_MANAGER_ACTIVITY,
          ),
        );
      } catch (e) {
        debugPrint('Failed to use IapClient for subscription management: $e');
        // Fallback approach would be to use deeplink:
        // 'appmarket://com.huawei.appmarket/sub'
        await launchUrlString('appmarket://com.huawei.appmarket/sub');
      }
    } catch (e) {
      debugPrint('HuaweiPurchaseProvider.openSubscriptionManagement: $e');
      rethrow;
    }
  }

  @override
  Future<PurchaseDetailsModel> getPurchaseDetails(
    final PurchaseId purchaseId,
  ) async {
    try {
      // Query all product types: 0 (consumable), 1 (non-consumable), 2 (subscription)
      final responseResults = await Future.wait([
        IapClient.obtainOwnedPurchases(OwnedPurchasesReq(priceType: 0)),
        IapClient.obtainOwnedPurchases(OwnedPurchasesReq(priceType: 1)),
        IapClient.obtainOwnedPurchases(OwnedPurchasesReq(priceType: 2)),
      ]);

      final results = responseResults.map((final response) {
        if (response.returnCode == '0') {
          final purchase = response.inAppPurchaseDataList?.firstWhereOrNull(
            (final p) => p.orderId == purchaseId.value,
          );
          if (purchase != null) {
            return _mapOwnedToPurchaseDetails(purchase);
          }
        }
        return null;
      }).whereType<PurchaseDetailsModel>();

      final result = results.firstOrNull;
      if (result != null) {
        return result;
      }

      throw Exception('Purchase not found: ${purchaseId.value}');
    } catch (e) {
      throw Exception('Failed to get purchase details: $e');
    }
  }

  @override
  Future<bool> isStoreInstalled() async {
    try {
      // Use Huawei HMS availability check via IapClient
      final result = await IapClient.isEnvReady();

      /// Status codes:
      /// - `0`: Success (environment ready)
      /// - `1`: Failure
      /// - `404`: No resource found
      /// - `500`: Internal error
      return result.status?.statusCode == 0;
    } catch (e) {
      debugPrint('HuaweiPurchaseProvider.isStoreInstalled: $e');
      return false;
    }
  }
}
