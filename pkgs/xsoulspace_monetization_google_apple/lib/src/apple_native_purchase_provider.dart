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
        productIds.map((final e) => e.value).toList(),
      );
      if (result == null) return [];

      return result.map(_mapStoreKitProductToModel).toList();
    } on PlatformException catch (e) {
      throw Exception(e.message);
    }
  }

  /// Maps App Store Connect API product data to PurchaseProductDetailsModel
  PurchaseProductDetailsModel _mapStoreKitProductToModel(
    final dynamic productDataRaw,
  ) {
    final productData = jsonDecodeMapAs<String, dynamic>(productDataRaw);
    if (productData.isEmpty) {
      throw Exception('Invalid product data format');
    }

    // Extract basic product information
    final productId = jsonDecodeString(productData['id']);
    final attributes = jsonDecodeMapAs<String, dynamic>(
      productData['attributes'],
    );

    // Extract product name and description
    final displayName = jsonDecodeString(attributes['name']);
    final descriptionData = jsonDecodeNullableMap(attributes['description']);
    final description = jsonDecodeString(descriptionData?['standard']);

    // Determine product type from attributes
    final kind = jsonDecodeString(attributes['kind']);
    final isSubscription = jsonDecodeBool(attributes['isSubscription']);
    final productType = _mapAppStoreKindToProductType(kind, isSubscription);

    // Extract pricing information from first offer
    final offers = jsonDecodeListAs<Map<String, dynamic>>(attributes['offers']);
    final firstOffer = offers.isNotEmpty ? offers.first : <String, dynamic>{};

    final price =
        jsonDecodeDouble(firstOffer['price']) / 100; // Convert from cents
    final currencyCode = jsonDecodeString(firstOffer['currencyCode']);
    final displayPrice = jsonDecodeString(firstOffer['priceFormatted']);

    // Extract subscription duration from recurring period
    final recurringPeriod = jsonDecodeString(
      firstOffer['recurringSubscriptionPeriod'],
    );
    final duration = jsonDecodeDurationFromISO8601(recurringPeriod);

    // TODO: Extract free trial information when available in the API response
    final freeTrialDuration = PurchaseDurationModel.zero;

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

  /// Maps App Store Connect API kind to PurchaseProductType
  PurchaseProductType _mapAppStoreKindToProductType(
    final String kind,
    final bool isSubscription,
  ) {
    if (isSubscription) return PurchaseProductType.subscription;
    return switch (kind.toLowerCase()) {
      'auto-renewable subscription' ||
      'non-renewable subscription' ||
      'autorenewable' => PurchaseProductType.subscription,
      'consumable' => PurchaseProductType.consumable,
      'non-consumable' || 'nonconsumable' => PurchaseProductType.nonConsumable,
      _ =>
        isSubscription
            ? PurchaseProductType.subscription
            : PurchaseProductType.nonConsumable,
    };
  }

  /// Extracts duration from transaction product data (simplified version)
  Duration _extractDurationFromTransactionProduct(
    final Map<String, dynamic>? productData,
  ) {
    if (productData == null) return Duration.zero;

    // Try to find subscription period in transaction product data
    final subscription = jsonDecodeNullableMap(productData['subscription']);
    if (subscription == null) return Duration.zero;

    final period = jsonDecodeNullableMap(subscription['subscriptionPeriod']);
    if (period == null) return Duration.zero;

    final unit = jsonDecodeString(period['unit']);
    final value = jsonDecodeInt(period['value']);

    return switch (unit.toLowerCase()) {
      'day' => Duration(days: value),
      'week' => Duration(days: value * 7),
      'month' => Duration(days: value * 30),
      'year' => Duration(days: value * 365),
      _ => Duration.zero,
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

  Future<PurchaseDetailsModel> getPurchaseDetails(
    final PurchaseProductId productId,
  ) async {
    try {
      final result = await _purchasesChannel.invokeMethod<String>(
        'getPurchaseDetails',
        productId.value,
      );
      if (result == null) {
        throw Exception('Failed to get purchase details.');
      }

      return _mapTransactionToPurchaseDetails(
        jsonDecodeMapAs<String, dynamic>(result),
      );
    } on PlatformException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<PurchaseDetailsModel> getPurchaseDetailsByPurchaseId(
    final PurchaseId purchaseId,
  ) async {
    try {
      final result = await _purchasesChannel.invokeMethod<String>(
        'getPurchaseDetailsByPurchaseId',
        purchaseId.value,
      );
      if (result == null) {
        throw Exception('Failed to get purchase details.');
      }

      return _mapTransactionToPurchaseDetails(
        jsonDecodeMapAs<String, dynamic>(result),
      );
    } on PlatformException catch (e) {
      throw Exception(e.message);
    }
  }

  PurchaseDetailsModel _mapTransactionToPurchaseDetails(
    final Map<String, dynamic> transactionData,
  ) {
    final productData = jsonDecodeNullableMap(transactionData['product']);
    final productId = jsonDecodeString(transactionData['productID']);
    final purchaseId = jsonDecodeString(transactionData['id']);
    final purchaseDate =
        dateTimeFromMillisecondsSinceEpoch(transactionData['purchaseDate']) ??
        DateTime.now();
    final status = _mapTransactionStatus(
      jsonDecodeString(transactionData['status']),
    );
    final expiryDate = dateTimeFromMillisecondsSinceEpoch(
      transactionData['expiresDate'],
    );
    final name = jsonDecodeString(productData?['displayName']);
    final formattedPrice = jsonDecodeString(productData?['displayPrice']);
    // For transaction data, we might not have the same detailed subscription info
    // Try to extract from product data if available, otherwise use defaults
    final duration = _extractDurationFromTransactionProduct(productData);
    const freeTrialDuration =
        Duration.zero; // Transaction data typically doesn't include trial info

    return PurchaseDetailsModel(
      purchaseId: PurchaseId.fromJson(purchaseId),
      productId: PurchaseProductId.fromJson(productId),
      priceId: PurchasePriceId.fromJson(productId),
      status: status,
      purchaseDate: purchaseDate,
      purchaseType: PurchaseProductType.nonConsumable,
      source: 'app_store',
      name: name,
      duration: duration,
      expiryDate: expiryDate,
      formattedPrice: formattedPrice,
    );
  }

  PurchaseStatus _mapTransactionStatus(final String status) =>
      switch (status.toLowerCase()) {
        'purchased' => PurchaseStatus.purchased,
        'pending' => PurchaseStatus.pending,
        'failed' => PurchaseStatus.error,
        'deferred' => PurchaseStatus.pending,
        'restored' => PurchaseStatus.purchased,
        _ => PurchaseStatus.error,
      };
}
