// ignore_for_file: avoid_catches_without_on_clauses, lines_longer_than_80_chars

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:from_json_to_json/from_json_to_json.dart';
// import 'package:flutter_rustore_billing/flutter_rustore_billing.dart';
// import 'package:flutter_rustore_billing/pigeons/rustore.dart';
import 'package:rustore_billing_api/rustore_billing_api.dart';
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
  final RustoreBillingClient _client = RustoreBillingClient.instance;

  @override
  Future<MonetizationStoreStatus> init() async {
    if (!Platform.isAndroid) return MonetizationStoreStatus.notAvailable;
    try {
      await _client.initialize(
        RustoreBillingConfig(
          consoleApplicationId: consoleApplicationId,
          deeplinkScheme: deeplinkScheme,
          debugLogs: enableLogger,
        ),
      );
      _client.updatesStream.listen((final e) {
        final purchase = e.paymentResult;
        final error = e.error;
        if (purchase != null) {
          _purchaseStreamController.add([
            PurchaseDetailsModel(
              purchaseId: PurchaseId.fromJson(purchase.purchaseId),
              productId: PurchaseProductId.fromJson(purchase.productId),
              purchaseDate: DateTime.now(),
              purchaseType: PurchaseProductType.nonConsumable,
              priceId: PurchasePriceId.fromJson(purchase.productId),
            ),
          ]);
        } else if (error != null) {
          debugPrint('RustorePurchaseProvider.init: $error');
        }
      });

      return MonetizationStoreStatus.loaded;
    } catch (e) {
      debugPrint('RustorePurchaseProvider.init: $e');
      return MonetizationStoreStatus.notAvailable;
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
      return await _client.isRustoreUserAuthorized();
    } catch (e, stackTrace) {
      debugPrint('RustorePurchaseProvider.isUserAuthorized: $e');
      debugPrint('RustorePurchaseProvider.isUserAuthorized: $stackTrace');
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
      await _client.confirmPurchase(purchase.purchaseId.value);
      return CompletePurchaseResultModel.success();
    } catch (e) {
      return CompletePurchaseResultModel.failure(e.toString());
    }
  }

  @override
  Future<List<PurchaseProductDetailsModel>> getProductDetails(
    final List<PurchaseProductId> productIds,
  ) async {
    final products = await _client.getProducts(
      productIds.map((final p) => p.value).toList(),
    );
    return products.map(_mapToPurchaseProductDetails).toList();
  }

  @override
  Future<PurchaseResultModel> purchaseNonConsumable(
    final PurchaseProductDetailsModel productDetails,
  ) async {
    final result = await _processPurchase(productDetails);
    if (result.isSuccess && result.details != null) {
      _purchaseStreamController.add([result.details!]);
    }
    return result;
  }

  Future<PurchaseResultModel> _processPurchase(
    final PurchaseProductDetailsModel details,
  ) async {
    try {
      final purchase = await _client.purchaseProduct(details.productId.value);
      if (purchase.resultType != RustorePaymentResultType.success) {
        return PurchaseResultModel.failure(
          'Purchase failed. ${purchase.errorMessage}',
        );
      }
      return PurchaseResultModel.success(
        PurchaseDetailsModel(
          status: details.productType == PurchaseProductType.consumable
              ? PurchaseStatus.restored
              : PurchaseStatus.purchased,
          purchaseId: PurchaseId.fromJson(purchase.purchaseId),
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
      final purchases = await _client.getPurchases();
      final restored = purchases.map((final p) {
        final productType = _productTypeFromRustoreJson(
          p.productType,
          PurchaseProductId.fromJson(p.productId ?? ''),
        );
        return PurchaseDetailsModel(
          purchaseId: PurchaseId.fromJson(p.purchaseId ?? ''),
          productId: PurchaseProductId.fromJson(p.productId ?? ''),
          priceId: PurchasePriceId.fromJson(p.productId ?? ''),
          status: _purchaseStatusFromRustoreState(p.purchaseState),
          purchaseDate:
              dateTimeFromIso8601String(p.purchaseTime) ?? DateTime.now(),
          purchaseType: productType,
          name: p.amountLabel ?? '',
          formattedPrice: p.amountLabel ?? '',
          price: (p.amount ?? 0).toDouble(),
          currency: p.currency ?? '',

          // expiryDate: (p.purchaseTime != null
          //     ? dateTimeFromIso8601String(p.purchaseTime)
          //     : null) + p.subscription?.period,
        );
      }).toList();
      _purchaseStreamController.add(restored);

      return RestoreResultModel.success(restored);
    } catch (e) {
      return RestoreResultModel.failure(e.toString());
    }
  }

  PurchaseProductDetailsModel _mapToPurchaseProductDetails(
    final RustoreProduct product,
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
      price: (product.price ?? 0).toDouble(),
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
    final RustoreProductType? json,
    final PurchaseProductId productId,
  ) => switch (json) {
    RustoreProductType.nonConsumable => PurchaseProductType.nonConsumable,
    RustoreProductType.consumable => PurchaseProductType.consumable,
    RustoreProductType.subscription => PurchaseProductType.subscription,
    _ => throw Exception('Invalid purchase type: $json'),
  };

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
  Future<CancelResultModel> cancel(final String purchaseId) async {
    try {
      await _client.deletePurchase(purchaseId);
      return CancelResultModel.success();
    } catch (e, stackTrace) {
      debugPrint('RustorePurchaseProvider.cancel: $e');
      debugPrint('RustorePurchaseProvider.cancel: $stackTrace');

      return CancelResultModel.failure(e.toString());
    }
  }

  @override
  Future<List<PurchaseProductDetailsModel>> getConsumables(
    final List<PurchaseProductId> productIds,
  ) async {
    // TODO(arenukvern): implement identification of consumables
    final products = await _client.getProducts(
      productIds.map((final p) => p.value).toList(),
    );
    return products.map(_mapToPurchaseProductDetails).toList();
  }

  @override
  Future<List<PurchaseProductDetailsModel>> getNonConsumables(
    final List<PurchaseProductId> productIds,
  ) async {
    // TODO(arenukvern): implement identification of non-consumables
    final products = await _client.getProducts(
      productIds.map((final p) => p.value).toList(),
    );
    return products.map(_mapToPurchaseProductDetails).toList();
  }

  @override
  Future<List<PurchaseProductDetailsModel>> getSubscriptions(
    final List<PurchaseProductId> productIds,
  ) async {
    try {
      // TODO(arenukvern): implement identification of subscriptions
      final products = await _client.getProducts(
        productIds.map((final p) => p.value).toList(),
      );
      return products.map(_mapToPurchaseProductDetails).toList();
    } on RustoreBillingException catch (e) {
      throw PlatformException(
        code: 'RustoreBillingException',
        message: e.message,
        details: e,
        stacktrace: e.stackTrace.toString(),
      );
    }
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
    final purchases = await _client.getPurchases();
    final purchase = purchases.firstWhere(
      (final p) => p.purchaseId == purchaseId.value,
      orElse: RustorePurchase.new,
    );
    final purchaseDate =
        dateTimeFromIso8601String(purchase.purchaseTime) ?? DateTime.now();
    return PurchaseDetailsModel(
      purchaseId: purchaseId,
      productId: PurchaseProductId.fromJson(purchase.productId ?? ''),
      priceId: PurchasePriceId.fromJson(purchase.productId ?? ''),
      status: _purchaseStatusFromRustoreState(purchase.purchaseState),
      purchaseDate: purchaseDate,
      name: purchase.amountLabel ?? '',
      formattedPrice: purchase.amountLabel ?? '',
      price: (purchase.amount ?? 0).toDouble(),
      currency: purchase.currency ?? '',
    );
  }

  @override
  Future<bool> isStoreInstalled() async {
    try {
      final availability = await _client.checkPurchasesAvailability();
      return availability.resultType ==
              RustorePurchaseAvailabilityType.available ||
          availability.resultType == RustorePurchaseAvailabilityType.unknown;
    } catch (e, stackTrace) {
      debugPrint('RustorePurchaseProvider.isStoreInstalled: $e');
      debugPrint('RustorePurchaseProvider.isStoreInstalled: $stackTrace');
      return false;
    }
  }
}

PurchaseStatus _purchaseStatusFromRustoreState(
  final RustorePurchaseState? state,
) => switch (state) {
  RustorePurchaseState.created ||
  RustorePurchaseState.invoiceCreated ||
  RustorePurchaseState.paused => PurchaseStatus.pending,
  RustorePurchaseState.paid => PurchaseStatus.restored,
  RustorePurchaseState.cancelled ||
  RustorePurchaseState.closed ||
  RustorePurchaseState.terminated => PurchaseStatus.canceled,
  RustorePurchaseState.consumed ||
  RustorePurchaseState.confirmed => PurchaseStatus.purchased,
  null => PurchaseStatus.pending,
};
