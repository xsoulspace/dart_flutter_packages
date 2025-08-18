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
    final attributes = jsonDecodeMapAs<String, dynamic>(
      productData['attributes'],
    );
    final productId = jsonDecodeString(attributes['offerName']);

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

    final price = jsonDecodeDouble(firstOffer['price']);
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
    final attributes = jsonDecodeNullableMap(productData?['attributes']);
    final productId = jsonDecodeString(transactionData['productId']);
    final purchaseId = jsonDecodeString(transactionData['id']);
    final purchaseDate =
        dateTimeFromMillisecondsSinceEpoch(transactionData['purchaseDate']) ??
        DateTime.now();

    final expiryDate = dateTimeFromMillisecondsSinceEpoch(
      transactionData['expiresDate'],
    );
    final status = expiryDate?.isAfter(DateTime.now()) == true
        ? PurchaseStatus.purchased
        : PurchaseStatus.canceled;
    final name = jsonDecodeString(attributes?['name']);
    final offers = jsonDecodeListAs<Map<String, dynamic>>(
      attributes?['offers'],
    );
    final firstOffer = offers.isNotEmpty ? offers.first : <String, dynamic>{};
    final price = jsonDecodeDouble(transactionData['price']);
    final currencyCode = jsonDecodeString(transactionData['currencyCode']);
    final formattedPrice = jsonDecodeString(firstOffer['priceFormatted']);
    // For transaction data, we might not have the same detailed subscription info
    // Try to extract from product data if available, otherwise use defaults
    final duration = jsonDecodeDurationFromISO8601(
      firstOffer['recurringSubscriptionPeriod'],
    );
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
      price: price,
      currency: currencyCode,
      formattedPrice: formattedPrice,
      duration: duration,
      expiryDate: expiryDate,
    );
  }
}
