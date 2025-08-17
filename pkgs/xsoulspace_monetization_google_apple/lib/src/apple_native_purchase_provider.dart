import 'package:flutter/services.dart';
import 'package:from_json_to_json/from_json_to_json.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

class AppleNativePurchaseProvider {
  static const _purchasesChannel = MethodChannel(
    'dev.xsoulspace.monetization/purchases',
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

      return result.map(_mapStoreKitProductToModel).toList();
    } on PlatformException catch (e) {
      throw Exception(e.message);
    }
  }

  /// Maps StoreKit product data to PurchaseProductDetailsModel
  PurchaseProductDetailsModel _mapStoreKitProductToModel(
    final dynamic productData,
  ) {
    if (productData is! Map<String, dynamic>) {
      throw Exception('Invalid product data format');
    }

    final productId = jsonDecodeString(productData['id']);
    final displayName = jsonDecodeString(productData['displayName']);
    final description = jsonDecodeString(productData['description']);
    final price = jsonDecodeDouble(productData['price']);
    final currencyCode = jsonDecodeString(productData['currencyCode']);
    final displayPrice = jsonDecodeString(productData['displayPrice']);

    // Determine product type based on StoreKit type
    final type = jsonDecodeString(productData['type']);
    final productType = _mapStoreKitTypeToProductType(type);

    // Extract subscription information if available
    final subscription = jsonDecodeNullableMap(productData['subscription']);
    final duration = _extractDurationFromSubscription(subscription);
    final freeTrialDuration = _extractFreeTrialDuration(subscription);

    return PurchaseProductDetailsModel(
      productId: PurchaseProductId.fromJson(productId),
      priceId: PurchasePriceId.fromJson(productId),
      productType: productType,
      name: displayName,
      formattedPrice: displayPrice,
      price: price,
      currency: currencyCode,
      description: description,
      duration: duration,
      freeTrialDuration: freeTrialDuration,
    );
  }

  /// Maps StoreKit product type to PurchaseProductType
  PurchaseProductType _mapStoreKitTypeToProductType(
    final String storeKitType,
  ) => switch (storeKitType.toLowerCase()) {
    'consumable' => PurchaseProductType.consumable,
    'nonconsumable' => PurchaseProductType.nonConsumable,
    'autorenewable' => PurchaseProductType.subscription,
    // TODO(arenukvern): figure out what this is
    'nonrenewable' => PurchaseProductType.subscription,
    _ => PurchaseProductType.nonConsumable,
  };

  /// Helper to extract period unit and value from a subscription period map
  (String unit, int value)? _extractPeriodUnitValue(
    final Map<String, dynamic>? period,
  ) {
    if (period == null) return null;
    final unit = jsonDecodeString(period['unit']);
    final value = jsonDecodeInt(period['value']);
    return (unit, value);
  }

  /// Extracts duration from subscription data
  Duration _extractDurationFromSubscription(
    final Map<String, dynamic>? subscription,
  ) {
    final period = jsonDecodeNullableMap(subscription?['subscriptionPeriod']);
    final periodData = _extractPeriodUnitValue(period);
    if (periodData == null) return Duration.zero;
    final (unit, value) = periodData;
    return switch (unit.toLowerCase()) {
      'day' => Duration(days: value),
      'week' => Duration(days: value * 7),
      'month' => Duration(days: value * 30),
      'year' => Duration(days: value * 365),
      _ => Duration.zero,
    };
  }

  /// Extracts free trial duration from subscription data
  PurchaseDurationModel _extractFreeTrialDuration(
    final Map<String, dynamic>? subscription,
  ) {
    final introOffer = jsonDecodeNullableMap(
      subscription?['introductoryOffer'],
    );
    final period = jsonDecodeNullableMap(introOffer?['subscriptionPeriod']);
    final periodData = _extractPeriodUnitValue(period);
    if (periodData == null) return PurchaseDurationModel.zero;
    final (unit, value) = periodData;
    return switch (unit.toLowerCase()) {
      'day' => PurchaseDurationModel(days: value),
      'week' => PurchaseDurationModel(days: value * 7),
      'month' => PurchaseDurationModel(months: value),
      'year' => PurchaseDurationModel(years: value),
      _ => PurchaseDurationModel.zero,
    };
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
        shouldConfirmPurchase: true,
      );
    } on PlatformException catch (e) {
      return PurchaseResultModel.failure(e.message ?? 'Unknown error');
    }
  }

  Future<CancelResultModel> cancelSubscription() async {
    try {
      await _purchasesChannel.invokeMethod('showCancelSubSheet');
      return CancelResultModel.success();
    } on PlatformException catch (e) {
      return CancelResultModel.failure(e.message ?? 'Unknown error');
    }
  }
}
