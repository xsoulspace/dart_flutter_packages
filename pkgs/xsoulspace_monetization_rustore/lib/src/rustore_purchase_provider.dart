// ignore_for_file: avoid_catches_without_on_clauses, lines_longer_than_80_chars

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_rustore_billing/flutter_rustore_billing.dart';
import 'package:flutter_rustore_billing/pigeons/rustore.dart';
import 'package:from_json_to_json/from_json_to_json.dart';
import 'package:universal_io/io.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

typedef DurationFromProductId = Duration Function(PurchaseProductId);

/// {@template rustore_purchase_provider}
/// Implementation of [PurchaseProvider] using RuStore Billing.
/// {@endtemplate}
class RustorePurchaseProvider implements PurchaseProvider {
  RustorePurchaseProvider({
    required this.consoleApplicationId,
    required this.deeplinkScheme,
    this.enableLogger = false,
    this.productTypeChecker,
    final DurationFromProductId getDurationFromProductId =
        getDurationFromProductId,
  }) : _getDurationFromProductId = getDurationFromProductId;

  final String consoleApplicationId;
  final String deeplinkScheme;
  final DurationFromProductId _getDurationFromProductId;
  final bool enableLogger;
  final PurchaseProductType? Function(PurchaseProductId productId)?
  productTypeChecker;

  final _purchaseStreamController =
      StreamController<List<PurchaseDetailsModel>>.broadcast();

  @override
  Future<bool> init() async {
    if (!Platform.isAndroid) return false;
    try {
      await RustoreBillingClient.initialize(
        consoleApplicationId,
        deeplinkScheme,
        enableLogger,
      );
      return await _isAvailable();
    } catch (e) {
      debugPrint('RustorePurchaseProvider.init: $e');
      return false;
    }
  }

  @override
  Future<void> dispose() => _purchaseStreamController.close();

  @override
  Stream<List<PurchaseDetailsModel>> get purchaseStream =>
      _purchaseStreamController.stream;

  Future<bool> _isAvailable() async {
    // always returns false
    final isAuthorized = await RustoreBillingClient.getAuthorizationStatus();
    final isInstalled = await RustoreBillingClient.isRustoreInstalled();

    if (isInstalled) {
      final result = await RustoreBillingClient.available();
      return result.type == PurchaseAvailabilityType.available;
    }

    return false;
  }

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<CompletePurchaseResultModel> completePurchase(
    final PurchaseVerificationDtoModel purchase,
  ) async {
    try {
      if (purchase.productType != PurchaseProductType.consumable) {
        return CompletePurchaseResultModel.success();
      }
      final result = await RustoreBillingClient.confirm(
        purchase.purchaseId.value,
      );
      if (result.success) {
        return CompletePurchaseResultModel.success();
      } else {
        return CompletePurchaseResultModel.failure(
          'Failed to complete purchase: ${result.errorMessage}',
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
    final productsResponse = await RustoreBillingClient.products(
      productIds.map((final p) => p.value).toList(),
    );
    return productsResponse.products.nonNulls
        .map(_mapToPurchaseProductDetails)
        .toList();
  }

  @override
  Future<PurchaseResultModel> purchaseNonConsumable(
    final PurchaseProductDetailsModel productDetails,
  ) async {
    final result = await _processPurchase(productDetails);
    if (result.isSuccess) {
      _purchaseStreamController.add([?result.details]);
    }
    return result;
  }

  Future<PurchaseResultModel> _processPurchase(
    final PurchaseProductDetailsModel details,
  ) async {
    try {
      final purchase = await RustoreBillingClient.purchase(
        details.productId.value,
      );
      if (purchase.successPurchase == null) {
        return PurchaseResultModel.failure(
          'Purchase failed. ${purchase.invalidPurchase} ${purchase.invalidInvoice}',
        );
      }
      return PurchaseResultModel.success(
        PurchaseDetailsModel(
          status: details.productType == PurchaseProductType.consumable
              ? PurchaseStatus.restored
              : PurchaseStatus.purchased,
          purchaseId: PurchaseId.fromJson(purchase.successPurchase!.purchaseId),
          purchaseType: details.productType,
          productId: details.productId,
          priceId: details.priceId,
          name: details.name,
          formattedPrice: details.formattedPrice,
          price: details.price,
          currency: details.currency,
          purchaseDate: DateTime.now(),
          expiryDate: details.productType == PurchaseProductType.subscription
              ? DateTime.now().add(details.duration)
              : null,
        ),
      );
    } catch (e) {
      return PurchaseResultModel.failure(e.toString());
    }
  }

  @override
  Future<RestoreResultModel> restorePurchases() async {
    try {
      final purchases = await RustoreBillingClient.purchases();
      final restored = purchases.purchases.nonNulls.map((final p) {
        final productType = _productTypeFromRustoreJson(
          p.productType,
          PurchaseProductId.fromJson(p.productId),
        );
        return PurchaseDetailsModel(
          purchaseId: PurchaseId.fromJson(p.purchaseId),
          productId: PurchaseProductId.fromJson(p.productId),
          priceId: PurchasePriceId.fromJson(p.productId),
          status: _purchaseStatusFromRustoreState(p.purchaseState),
          purchaseDate:
              dateTimeFromIso8601String(p.purchaseTime) ?? DateTime.now(),
          purchaseType: productType,
          // expiryDate: p.finishTime != null
          //     ? dateTimeFromIso8601String(p.finishTime)
          //     : null,
        );
      }).toList();
      _purchaseStreamController.add(restored);

      return RestoreResultModel.success(restored);
    } catch (e) {
      return RestoreResultModel.failure(e.toString());
    }
  }

  PurchaseProductDetailsModel _mapToPurchaseProductDetails(
    final Product product,
  ) {
    final productId = PurchaseProductId.fromJson(product.productId);
    final duration = _getDurationFromProductId(productId);
    final freeTrialDuration = product.subscription?.freeTrialPeriod;
    final productType = _productTypeFromRustoreJson(
      product.productType,
      productId,
    );

    return PurchaseProductDetailsModel(
      productId: productId,
      productType: productType,
      name: product.title ?? '',
      formattedPrice: product.priceLabel ?? '',
      price: jsonDecodeDouble(product.price ?? '0'),
      currency: product.currency ?? '',
      duration: duration,
      freeTrialDuration: PurchaseDurationModel(
        years: freeTrialDuration?.years ?? 0,
        months: freeTrialDuration?.months ?? 0,
        days: freeTrialDuration?.days ?? 0,
      ),
    );
  }

  PurchaseProductType _productTypeFromRustoreJson(
    final String? json,
    final PurchaseProductId productId,
  ) {
    if (json == null || json == '') {
      final productType = productTypeChecker?.call(productId);
      if (productType != null) return productType;
    }
    return switch (json) {
      'NON_CONSUMABLE' => PurchaseProductType.nonConsumable,
      'CONSUMABLE' => PurchaseProductType.consumable,
      'SUBSCRIPTION' => PurchaseProductType.subscription,
      _ => throw Exception('Invalid purchase type: $json'),
    };
  }

  static Duration getDurationFromProductId(final PurchaseProductId id) {
    final parts = id.value.split('_');
    final unitIndex = parts.indexWhere(
      (final part) => ['day', 'month', 'year'].contains(part),
    );

    if (unitIndex == -1 || unitIndex + 1 >= parts.length) return Duration.zero;

    final unit = parts[unitIndex];
    final count = int.tryParse(parts[unitIndex + 1]) ?? 0;

    if (count == 0) return Duration.zero;

    return switch (unit) {
      'day' => Duration(days: count),
      'month' => Duration(days: count * 30),
      'year' => Duration(days: count * 365),
      _ => Duration.zero,
    };
  }

  @override
  Future<CancelResultModel> cancel(final PurchaseProductId productId) async {
    try {
      await RustoreBillingClient.deletePurchase(productId.value);
      return CancelResultModel.success();
    } catch (e) {
      return CancelResultModel.failure(e.toString());
    }
  }

  @override
  Future<List<PurchaseProductDetailsModel>> getConsumables(
    final List<PurchaseProductId> productIds,
  ) async {
    // TODO(arenukvern): implement identification of consumables
    final products = await RustoreBillingClient.products(
      productIds.map((final p) => p.value).toList(),
    );
    return products.products.nonNulls
        .map(_mapToPurchaseProductDetails)
        .toList();
  }

  @override
  Future<List<PurchaseProductDetailsModel>> getNonConsumables(
    final List<PurchaseProductId> productIds,
  ) async {
    // TODO(arenukvern): implement identification of non-consumables
    final products = await RustoreBillingClient.products(
      productIds.map((final p) => p.value).toList(),
    );
    return products.products.nonNulls
        .map(_mapToPurchaseProductDetails)
        .toList();
  }

  @override
  Future<List<PurchaseProductDetailsModel>> getSubscriptions(
    final List<PurchaseProductId> productIds,
  ) async {
    // TODO(arenukvern): implement identification of subscriptions
    final products = await RustoreBillingClient.products(
      productIds.map((final p) => p.value).toList(),
    );
    return products.products.nonNulls
        .map(_mapToPurchaseProductDetails)
        .toList();
  }

  @override
  Future<PurchaseResultModel> subscribe(
    final PurchaseProductDetailsModel productDetails,
  ) => _processPurchase(productDetails);

  @override
  Future<void> openSubscriptionManagement() async {
    // https://www.rustore.ru/help/sdk/rustore-deeplinks
    await launchUrlString('rustore://profile/subscriptions');
  }

  @override
  Future<PurchaseDetailsModel> getPurchaseDetails(
    final PurchaseId purchaseId,
  ) async {
    // TODO(arenukvern): implement getting of purchase details
    final purchase = await RustoreBillingClient.purchaseInfo(purchaseId.value);
    return PurchaseDetailsModel(
      purchaseId: purchaseId,
      productId: PurchaseProductId.fromJson(purchase.productId ?? ''),
      priceId: PurchasePriceId.fromJson(purchase.productId ?? ''),
      status: _purchaseStatusFromRustoreState(purchase.purchaseState),
      purchaseDate:
          dateTimeFromIso8601String(purchase.purchaseTime) ?? DateTime.now(),
      name: purchase.amountLabel ?? '',
      formattedPrice: purchase.amountLabel ?? '',
      price: jsonDecodeDouble(purchase.amount ?? '0'),
      currency: purchase.currency ?? '',
    );
  }
}

PurchaseStatus _purchaseStatusFromRustoreState(final String? json) =>
    switch (json) {
      'CREATED' || 'INVOICE_CREATED' || 'PAUSED' => PurchaseStatus.pending,
      'PAID' => PurchaseStatus.restored,
      'CANCELLED' || 'CLOSED' || 'TERMINATED' => PurchaseStatus.canceled,
      'CONSUMED' || 'CONFIRMED' => PurchaseStatus.purchased,
      _ => throw Exception('Invalid purchase status: $json'),
    };
