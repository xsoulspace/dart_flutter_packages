// ignore_for_file: avoid_catches_without_on_clauses, lines_longer_than_80_chars

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_rustore_billing/flutter_rustore_billing.dart';
import 'package:flutter_rustore_billing/pigeons/rustore.dart';
import 'package:from_json_to_json/from_json_to_json.dart';
import 'package:universal_io/io.dart';
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
    DurationFromProductId getDurationFromProductId = getDurationFromProductId,
  }) : _getDurationFromProductId = getDurationFromProductId;

  final String consoleApplicationId;
  final String deeplinkScheme;
  final DurationFromProductId _getDurationFromProductId;
  final bool enableLogger;
  final PurchaseProductType? Function(PurchaseProductId productId)?
  productTypeChecker;

  final _purchaseStreamController =
      StreamController<List<PurchaseDetails>>.broadcast();

  Future<void> init() async {
    if (!Platform.isAndroid) return;
    try {
      await RustoreBillingClient.initialize(
        consoleApplicationId,
        deeplinkScheme,
        enableLogger,
      );
    } catch (e) {
      debugPrint('RustorePurchaseProvider.init: $e');
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
    final isAuthorized = await RustoreBillingClient.getAuthorizationStatus();
    if (isAuthorized) {
      final result = await RustoreBillingClient.available();
      return result.type == PurchaseAvailabilityType.available;
    }
    return false;
  }

  @override
  Future<CompletePurchaseResult> completePurchase(
    PurchaseVerificationDto purchase,
  ) async {
    try {
      if (purchase.productType != PurchaseProductType.consumable) {
        return const CompletePurchaseResult.success();
      }
      final result = await RustoreBillingClient.confirm(
        purchase.purchaseId.value,
      );
      if (result.success) {
        return const CompletePurchaseResult.success();
      } else {
        return CompletePurchaseResult.failure(
          'Failed to complete purchase: ${result.errorMessage}',
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
    final productsResponse = await RustoreBillingClient.products(
      productIds.map((p) => p.value).toList(),
    );
    return productsResponse.products.nonNulls
        .map(_mapToPurchaseProductDetails)
        .toList();
  }

  @override
  Future<PurchaseResult> purchase(PurchaseProductDetails productDetails) async {
    final result = await _processPurchase(productDetails);
    result.when(
      success: (details) {
        _purchaseStreamController.add([details]);
      },
      failure: (_) {},
    );
    return result;
  }

  Future<PurchaseResult> _processPurchase(
    final PurchaseProductDetails details,
  ) async {
    try {
      final purchase = await RustoreBillingClient.purchase(
        details.productId.value,
      );
      if (purchase.successPurchase == null) {
        return PurchaseResult.failure(
          'Purchase failed. ${purchase.invalidPurchase} ${purchase.invalidInvoice}',
        );
      }
      return PurchaseResult.success(
        PurchaseDetails(
          status: details.productType == PurchaseProductType.consumable
              ? PurchaseStatus.restored
              : PurchaseStatus.purchased,
          purchaseId: PurchaseId(purchase.successPurchase!.purchaseId),
          purchaseType: details.productType,
          productId: details.productId,
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
      return PurchaseResult.failure(e.toString());
    }
  }

  @override
  Future<RestoreResult> restorePurchases() async {
    try {
      final purchases = await RustoreBillingClient.purchases();
      final restored = purchases.purchases.nonNulls.map((p) {
        final productType = _productTypeFromRustoreJson(
          p.productType,
          PurchaseProductId(p.productId ?? ''),
        );
        return PurchaseDetails(
          purchaseId: PurchaseId(p.purchaseId ?? ''),
          productId: PurchaseProductId(p.productId ?? ''),
          name: '',
          formattedPrice: '',
          status: _purchaseStatusFromRustoreState(p.purchaseState),
          price: 0,
          currency: '',
          purchaseDate:
              dateTimeFromIso8601String(p.purchaseTime) ?? DateTime.now(),
          purchaseType: productType,
          // expiryDate: p.finishTime != null
          //     ? dateTimeFromIso8601String(p.finishTime)
          //     : null,
        );
      }).toList();

      _purchaseStreamController.add(restored);
      return RestoreResult.success(restored);
    } catch (e) {
      return RestoreResult.failure(e.toString());
    }
  }

  PurchaseProductDetails _mapToPurchaseProductDetails(Product product) {
    final productId = PurchaseProductId(product.productId);
    final duration = _getDurationFromProductId(productId);
    final freeTrialDuration = product.subscription?.freeTrialPeriod;
    final productType = _productTypeFromRustoreJson(
      product.productType,
      productId,
    );

    return PurchaseProductDetails(
      productId: productId,
      productType: productType,
      name: product.title ?? '',
      formattedPrice: product.priceLabel ?? '',
      price: jsonDecodeDouble(product.price ?? '0'),
      currency: product.currency ?? '',
      duration: duration,
      freeTrialDuration: PurchaseDuration(
        years: freeTrialDuration?.years ?? 0,
        months: freeTrialDuration?.months ?? 0,
        days: freeTrialDuration?.days ?? 0,
      ),
    );
  }

  PurchaseProductType _productTypeFromRustoreJson(
    String? json,
    PurchaseProductId productId,
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
}

PurchaseStatus _purchaseStatusFromRustoreState(String? json) => switch (json) {
  'CREATED' || 'INVOICE_CREATED' || 'PAUSED' => PurchaseStatus.pending,
  'PAID' => PurchaseStatus.restored,
  'CANCELLED' || 'CLOSED' || 'TERMINATED' => PurchaseStatus.canceled,
  'CONSUMED' || 'CONFIRMED' => PurchaseStatus.purchased,
  _ => throw Exception('Invalid purchase status: $json'),
};
