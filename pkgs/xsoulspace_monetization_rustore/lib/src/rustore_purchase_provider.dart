// ignore_for_file: avoid_catches_without_on_clauses, lines_longer_than_80_chars

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:from_json_to_json/from_json_to_json.dart';
import 'package:rustore_billing_api/rustore_billing_api.dart';
import 'package:universal_io/io.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

typedef DurationFromProductId = Duration Function(PurchaseProductId);

class RustorePurchaseProvider implements PurchaseProvider {
  RustorePurchaseProvider({
    required this.consoleApplicationId,
    required this.deeplinkScheme,
    this.enableLogging = false,
    this.productTypeChecker,
    final DurationFromProductId getDurationFromProductId =
        getDurationFromProductId,
  }) : _getDurationFromProductId = getDurationFromProductId;

  final String consoleApplicationId;
  final String deeplinkScheme;
  final DurationFromProductId _getDurationFromProductId;
  final bool enableLogging;
  final PurchaseProductType? Function(PurchaseProductId productId)?
  productTypeChecker;

  final StreamController<List<PurchaseDetailsModel>> _purchaseStreamController =
      StreamController<List<PurchaseDetailsModel>>.broadcast();
  final RustoreBillingClient _client = RustoreBillingClient.instance;

  @override
  Future<MonetizationStoreStatus> init() async {
    if (!Platform.isAndroid) {
      return MonetizationStoreStatus.notAvailable;
    }
    try {
      await _client.initialize(
        RustoreBillingConfig(
          consoleApplicationId: consoleApplicationId,
          deeplinkScheme: deeplinkScheme,
          debugLogs: enableLogging,
          enableLogging: enableLogging,
        ),
      );
      _client.updatesStream.listen((final event) async {
        final purchaseResult = event.purchaseResult;
        final error = event.error;
        if (purchaseResult != null && purchaseResult.purchase != null) {
          final purchaseDetails = await getPurchaseDetails(
            PurchaseId.fromJson(purchaseResult.purchase!.purchaseId),
          );
          _purchaseStreamController.add([purchaseDetails]);
        } else if (error != null) {
          debugPrint('RustorePurchaseProvider.init: ${error.message}');
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
      return await _client.getUserAuthorizationStatus();
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
      final rustorePurchase = await _client.getPurchase(
        purchase.purchaseId.value,
      );
      if (rustorePurchase == null) {
        return CompletePurchaseResultModel.failure(
          'Purchase ${purchase.purchaseId.value} was not found.',
        );
      }
      if (rustorePurchase.purchaseType != RustorePurchaseType.twoStep) {
        return CompletePurchaseResultModel.success();
      }
      await _client.confirmTwoStepPurchase(purchase.purchaseId.value);
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
      final preferredType =
          details.productType == PurchaseProductType.consumable
          ? RustorePreferredPurchaseType.twoStep
          : RustorePreferredPurchaseType.oneStep;
      final result = await _client.purchase(
        RustoreProductPurchaseParams(
          productId: details.productId.value,
          quantity: 1,
        ),
        preferredPurchaseType: preferredType,
      );

      if (result.purchase == null) {
        return PurchaseResultModel.failure(
          result.error?.message ?? 'Purchase failed without purchase payload.',
        );
      }

      if (result.resultType != RustoreProductPurchaseResultType.success) {
        return PurchaseResultModel.failure(
          result.error?.message ?? 'Purchase failed.',
        );
      }

      final mappedDetails = _mapRustorePurchaseToDetails(
        purchase: result.purchase!,
        fallbackProductDetails: details,
      );
      final purchaseResult = PurchaseResultModel.success(mappedDetails);
      _purchaseStreamController.add([purchaseResult.details!]);
      return purchaseResult;
    } catch (e) {
      return PurchaseResultModel.failure(e.toString());
    }
  }

  @override
  Future<RestoreResultModel> restorePurchases() async {
    try {
      final purchases = await _client.getPurchases();
      final restored = await Future.wait(
        purchases.map((final p) {
          final purchaseId = PurchaseId.fromJson(p.purchaseId);
          if (purchaseId.isEmpty) {
            return null;
          }
          return getPurchaseDetails(purchaseId);
        }).nonNulls,
      );
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
    final periods =
        product.subscriptionInfo?.periods ??
        const <RustoreProductSubscriptionPeriod>[];
    RustoreProductSubscriptionPeriod? period;
    for (final current in periods) {
      if (current.type == RustoreSubscriptionPeriodType.main) {
        period = current;
        break;
      }
    }
    period ??= periods.isNotEmpty ? periods.first : null;

    RustoreProductSubscriptionPeriod? freeTrialPeriod;
    for (final current in periods) {
      if (current.type == RustoreSubscriptionPeriodType.trial) {
        freeTrialPeriod = current;
        break;
      }
    }
    final duration = period != null
        ? _durationFromIso8601Period(period.durationIso)
        : _getDurationFromProductId(productId);

    return PurchaseProductDetailsModel(
      productId: productId,
      productType: _productTypeFromRustoreJson(product.productType),
      name: product.title ?? '',
      formattedPrice: product.priceLabel ?? '',
      price: (product.price ?? 0).toDouble(),
      currency: product.currency ?? '',
      duration: duration,
      freeTrialDuration: _durationModelFromIso8601(
        freeTrialPeriod?.durationIso ?? 'P0D',
      ),
      description: product.description ?? '',
      priceId: PurchasePriceId.fromJson(product.productId),
    );
  }

  PurchaseProductType _productTypeFromRustoreJson(
    final RustoreProductType json,
  ) => switch (json) {
    RustoreProductType.nonConsumable => PurchaseProductType.nonConsumable,
    RustoreProductType.consumable => PurchaseProductType.consumable,
    RustoreProductType.subscription => PurchaseProductType.subscription,
    RustoreProductType.unknown => PurchaseProductType.consumable,
  };

  static Duration getDurationFromProductId(final PurchaseProductId id) {
    final parts = id.value.split('_');
    final unitIndex = parts.indexWhere(
      (final part) => ['day', 'month', 'year'].contains(part),
    );
    if (unitIndex == -1 || unitIndex + 1 >= parts.length) {
      return Duration.zero;
    }
    final unit = parts[unitIndex];
    final count = jsonDecodeInt(parts[unitIndex + 1]);
    if (count == 0) {
      return Duration.zero;
    }
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
      final purchase = await _client.getPurchase(purchaseId);
      if (purchase == null) {
        return CancelResultModel.failure('Purchase $purchaseId was not found.');
      }
      if (purchase.purchaseType != RustorePurchaseType.twoStep) {
        return CancelResultModel.failure(
          'Cancel is supported only for two-step purchases.',
        );
      }
      await _client.cancelTwoStepPurchase(purchaseId);
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
    final products = await _client.getProducts(
      productIds.map((final p) => p.value).toList(),
    );
    return products
        .where((final p) => p.productType == RustoreProductType.consumable)
        .map(_mapToPurchaseProductDetails)
        .toList();
  }

  @override
  Future<List<PurchaseProductDetailsModel>> getNonConsumables(
    final List<PurchaseProductId> productIds,
  ) async {
    final products = await _client.getProducts(
      productIds.map((final p) => p.value).toList(),
    );
    return products
        .where((final p) => p.productType == RustoreProductType.nonConsumable)
        .map(_mapToPurchaseProductDetails)
        .toList();
  }

  @override
  Future<List<PurchaseProductDetailsModel>> getSubscriptions(
    final List<PurchaseProductId> productIds,
  ) async {
    try {
      final products = await _client.getProducts(
        productIds.map((final p) => p.value).toList(),
      );
      return products
          .where((final p) => p.productType == RustoreProductType.subscription)
          .map(_mapToPurchaseProductDetails)
          .toList();
    } on RustoreBillingException catch (e) {
      throw PlatformException(
        code: e.code,
        message: e.message,
        details: e.details,
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
    await launchUrlString('rustore://profile/subscriptions');
  }

  @override
  Future<PurchaseDetailsModel> getPurchaseDetails(
    final PurchaseId purchaseId,
  ) async {
    final purchase = await _client.getPurchase(purchaseId.value);
    if (purchase == null) {
      return PurchaseDetailsModel.empty;
    }
    final productId = PurchaseProductId.fromJson(purchase.productId ?? '');
    final productDetails = await getProductDetails([productId]);
    final productDetail = productDetails.firstWhere(
      (final p) => p.productId == productId,
      orElse: () => PurchaseProductDetailsModel.empty,
    );
    return _mapRustorePurchaseToDetails(
      purchase: purchase,
      fallbackProductDetails: productDetail,
    );
  }

  @override
  Future<bool> isStoreInstalled() async {
    try {
      final availability = await _client.getPurchaseAvailability();
      return availability.status ==
              RustorePurchaseAvailabilityStatus.available ||
          availability.status == RustorePurchaseAvailabilityStatus.unknown;
    } catch (e, stackTrace) {
      debugPrint('RustorePurchaseProvider.isStoreInstalled: $e');
      debugPrint('RustorePurchaseProvider.isStoreInstalled: $stackTrace');
      return false;
    }
  }

  PurchaseDetailsModel _mapRustorePurchaseToDetails({
    required final RustorePurchase purchase,
    required final PurchaseProductDetailsModel fallbackProductDetails,
  }) {
    final purchaseDate =
        dateTimeFromIso8601String(purchase.purchaseTime) ?? DateTime.now();
    final duration = fallbackProductDetails.duration;
    final expiryDate = purchaseDate.add(duration);

    return PurchaseDetailsModel(
      purchaseId: PurchaseId.fromJson(purchase.purchaseId),
      productId: PurchaseProductId.fromJson(purchase.productId ?? ''),
      priceId: PurchasePriceId.fromJson(purchase.productId ?? ''),
      status: _purchaseStatusFromRustoreState(purchase.purchaseStatus),
      purchaseDate: purchaseDate,
      name: fallbackProductDetails.name,
      formattedPrice:
          purchase.amountLabel ?? fallbackProductDetails.formattedPrice,
      price: (purchase.amount ?? 0).toDouble(),
      currency: purchase.currency ?? fallbackProductDetails.currency,
      duration: duration,
      expiryDate:
          fallbackProductDetails.productType == PurchaseProductType.subscription
          ? expiryDate
          : null,
      purchaseType: fallbackProductDetails.productType,
      freeTrialDuration: fallbackProductDetails.freeTrialDuration.toDuration(),
      purchaseToken: purchase.subscriptionToken ?? '',
    );
  }
}

PurchaseStatus _purchaseStatusFromRustoreState(
  final RustorePurchaseStatus state,
) => switch (state) {
  RustorePurchaseStatus.created ||
  RustorePurchaseStatus.invoiceCreated ||
  RustorePurchaseStatus.paid ||
  RustorePurchaseStatus.active ||
  RustorePurchaseStatus.paused => PurchaseStatus.pendingVerification,
  RustorePurchaseStatus.confirmed ||
  RustorePurchaseStatus.consumed => PurchaseStatus.purchased,
  RustorePurchaseStatus.cancelled ||
  RustorePurchaseStatus.closed ||
  RustorePurchaseStatus.terminated ||
  RustorePurchaseStatus.reversed => PurchaseStatus.canceled,
  RustorePurchaseStatus.unknown => PurchaseStatus.error,
};

Duration _durationFromIso8601Period(final String period) {
  final match = RegExp(
    r'^P(?:(\d+)Y)?(?:(\d+)M)?(?:(\d+)D)?$',
  ).firstMatch(period);
  if (match == null) {
    return Duration.zero;
  }
  final years = int.tryParse(match.group(1) ?? '0') ?? 0;
  final months = int.tryParse(match.group(2) ?? '0') ?? 0;
  final days = int.tryParse(match.group(3) ?? '0') ?? 0;
  return Duration(days: years * 365 + months * 30 + days);
}

PurchaseDurationModel _durationModelFromIso8601(final String period) {
  final match = RegExp(
    r'^P(?:(\d+)Y)?(?:(\d+)M)?(?:(\d+)D)?$',
  ).firstMatch(period);
  if (match == null) {
    return PurchaseDurationModel.zero;
  }
  return PurchaseDurationModel(
    years: int.tryParse(match.group(1) ?? '0') ?? 0,
    months: int.tryParse(match.group(2) ?? '0') ?? 0,
    days: int.tryParse(match.group(3) ?? '0') ?? 0,
  );
}

extension on PurchaseDurationModel {
  Duration toDuration() => Duration(days: years * 365 + months * 30 + days);
}
