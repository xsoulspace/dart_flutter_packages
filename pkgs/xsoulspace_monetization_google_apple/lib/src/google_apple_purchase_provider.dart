// ignore_for_file: avoid_catches_without_on_clauses, lines_longer_than_80_chars

import 'dart:async';
import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/services.dart';
import 'package:from_json_to_json/from_json_to_json.dart';
import 'package:in_app_purchase/in_app_purchase.dart' as iap;
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import 'apple_native_purchase_provider.dart';

/// {@template google_apple_purchase_provider}
/// Implementation of [PurchaseProvider] using the `in_app_purchase` package.
/// {@endtemplate}
class GoogleApplePurchaseProvider implements PurchaseProvider {
  final _appleNativeProvider = AppleNativePurchaseProvider();

  /// assume by default that the user is signed in
  static var _isUserSignedInToStore = true;

  final iap.InAppPurchase _inAppPurchase = iap.InAppPurchase.instance;
  late StreamSubscription<List<iap.PurchaseDetails>> _purchaseSubscription;

  final _purchaseStreamController =
      StreamController<List<PurchaseDetailsModel>>.broadcast();

  /// Initializes the purchase provider.
  @override
  Future<MonetizationStoreStatus> init() async {
    _purchaseSubscription = _inAppPurchase.purchaseStream.listen(
      (final purchaseDetailsList) {
        final purchases = purchaseDetailsList
            .map(_mapToPurchaseDetails)
            .toList();
        _purchaseStreamController.add(purchases);
      },
      onDone: _purchaseStreamController.close,
      onError: (final error) => _purchaseStreamController.addError(error),
    );

    return MonetizationStoreStatus.loaded;
  }

  @override
  Future<void> dispose() async {
    await _purchaseSubscription.cancel();
    await _purchaseStreamController.close();
  }

  @override
  Stream<List<PurchaseDetailsModel>> get purchaseStream =>
      _purchaseStreamController.stream;

  @override
  Future<bool> isUserAuthorized() async => _isUserSignedInToStore;

  @override
  Future<CompletePurchaseResultModel> completePurchase(
    final PurchaseVerificationDtoModel purchase,
  ) async {
    // This is a simplified mapping. You might need a more robust way
    // to find the original iap.PurchaseDetails object.
    final iapPurchase = iap.PurchaseDetails(
      purchaseID: purchase.purchaseId.value,
      productID: purchase.productId.value,
      transactionDate: purchase.transactionDate?.toIso8601String(),
      status: purchase.status._toFlutterIAPStatus(),
      verificationData: iap.PurchaseVerificationData(
        localVerificationData: purchase.localVerificationData ?? '',
        serverVerificationData: purchase.serverVerificationData ?? '',
        source: purchase.source ?? '',
      ),
    );

    try {
      await _inAppPurchase.completePurchase(iapPurchase);
      return CompletePurchaseResultModel.success();
    } catch (e) {
      return CompletePurchaseResultModel.failure(e.toString());
    }
  }

  @override
  Future<List<PurchaseProductDetailsModel>> getProductDetails(
    final List<PurchaseProductId> productIds,
  ) async {
    if (Platform.isIOS) {
      return _appleNativeProvider.fetchProducts(productIds);
    }
    final response = await _inAppPurchase.queryProductDetails(
      productIds.map((final id) => id.value).toSet(),
    );
    if (response.error != null) {
      throw Exception(response.error!.message);
    }
    return response.productDetails.map(_mapToProductDetails).toList();
  }

  @override
  Future<PurchaseResultModel> purchaseNonConsumable(
    final PurchaseProductDetailsModel productDetails,
  ) async {
    if (Platform.isIOS) {
      return _appleNativeProvider.purchaseProduct(productDetails);
    }
    final response = await _inAppPurchase.queryProductDetails({
      productDetails.productId.value,
    });
    if (response.error != null) {
      return PurchaseResultModel.failure(response.error!.message);
    }
    if (response.productDetails.isEmpty) {
      return PurchaseResultModel.failure(
        'Product not found: ${productDetails.productId.value}',
      );
    }

    final purchaseParam = iap.PurchaseParam(
      productDetails: response.productDetails.first,
    );

    try {
      final success = await _inAppPurchase.buyNonConsumable(
        purchaseParam: purchaseParam,
      );
      // The result of the purchase will be delivered via the purchaseStream.
      // Here we are just initiating it. Returning a pending-like status
      // might be an option, but for now we rely on the stream.
      // This part of the flow may need refinement based on UX.
      if (success) {
        // A proper success would be to return the PurchaseDetails from the stream,
        // but this method must return. We assume 'pending' and let the stream update.
        return PurchaseResultModel.success(
          _mapToPurchaseDetails(
            iap.PurchaseDetails(
              productID: productDetails.productId.value,
              purchaseID: '', // Not available immediately
              transactionDate: DateTime.now().millisecondsSinceEpoch.toString(),
              status: iap.PurchaseStatus.pending,
              verificationData: iap.PurchaseVerificationData(
                localVerificationData: '',
                serverVerificationData: '',
                source: 'in_app_purchase',
              ),
            ),
          ),
          shouldConfirmPurchase: false,
        );
      } else {
        return PurchaseResultModel.failure('Purchase initiation failed.');
      }
    } catch (e) {
      return PurchaseResultModel.failure(e.toString());
    }
  }

  @override
  Future<RestoreResultModel> restorePurchases() async {
    try {
      await _inAppPurchase.restorePurchases();
      // Restore results are also delivered via the purchaseStream.
      // This method simply triggers the process.
      return RestoreResultModel.success([]);
    } catch (e) {
      return RestoreResultModel.failure(e.toString());
    }
  }

  PurchaseProductDetailsModel _mapToProductDetails(
    final iap.ProductDetails product,
  ) => PurchaseProductDetailsModel(
    productId: PurchaseProductId.fromJson(product.id),
    priceId: PurchasePriceId.fromJson(product.id),
    // This logic needs to be robust. Assuming type from ID is brittle.
    productType: product.id.contains('subscription')
        ? PurchaseProductType.subscription
        : PurchaseProductType.nonConsumable,
    name: product.title,
    formattedPrice: product.price,
    price: product.rawPrice,
    currency: product.currencyCode,
    description: product.description,
    // This duration logic is also an assumption and needs to be solid.
    duration: _extractDurationFromProductId(product.id).duration,
    // TODO: Implement free trial duration
    freeTrialDuration: PurchaseDurationModel.zero,
  );

  PurchaseDetailsModel _mapToPurchaseDetails(
    final iap.PurchaseDetails purchase,
  ) {
    final transactionDate = purchase.transactionDate;
    // "2025-08-17 7:44:54 AM"
    final purchaseDate = dateTimeFromIso8601String(transactionDate);

    return PurchaseDetailsModel(
      purchaseId: PurchaseId.fromJson(purchase.purchaseID ?? ''),
      productId: PurchaseProductId.fromJson(purchase.productID),
      priceId: PurchasePriceId.fromJson(purchase.productID),
      status: _mapPurchaseStatus(purchase.status),
      purchaseDate: purchaseDate ?? DateTime.now(),
      // This needs to be determined properly
      purchaseType: PurchaseProductType.nonConsumable,
      localVerificationData: purchase.verificationData.localVerificationData,
      serverVerificationData: purchase.verificationData.serverVerificationData,
      source: purchase.verificationData.source,
      name: purchase.productID,
      duration: _extractDurationFromProductId(purchase.productID).duration,
      freeTrialDuration: _extractDurationFromProductId(
        purchase.productID,
      ).duration,
    );
  }

  PurchaseStatus _mapPurchaseStatus(final iap.PurchaseStatus status) =>
      switch (status) {
        iap.PurchaseStatus.pending => PurchaseStatus.pending,
        iap.PurchaseStatus.purchased => PurchaseStatus.purchased,
        iap.PurchaseStatus.error => PurchaseStatus.error,
        iap.PurchaseStatus.restored => PurchaseStatus.pendingConfirmation,
        iap.PurchaseStatus.canceled => PurchaseStatus.canceled,
      };

  void _catchNoResponse(final iap.IAPError error) {
    // iOS has no user signed
    if (error.code == 'storekit_no_response') {
      _isUserSignedInToStore = false;
    }
  }

  @override
  Future<List<PurchaseProductDetailsModel>> getConsumables(
    final List<PurchaseProductId> productIds,
  ) async {
    // TODO(arenukvern): implement identification of consumables
    final response = await _inAppPurchase.queryProductDetails(
      productIds.map((final id) => id.value).toSet(),
    );
    if (response.error != null) {
      _catchNoResponse(response.error!);
      throw Exception(response.error!.message);
    }
    return response.productDetails.map(_mapToProductDetails).toList();
  }

  @override
  Future<List<PurchaseProductDetailsModel>> getNonConsumables(
    final List<PurchaseProductId> productIds,
  ) async {
    // TODO(arenukvern): implement identification of non-consumables
    final response = await _inAppPurchase.queryProductDetails(
      productIds.map((final id) => id.value).toSet(),
    );
    if (response.error != null) {
      _catchNoResponse(response.error!);
      throw Exception(response.error!.message);
    }
    return response.productDetails.map(_mapToProductDetails).toList();
  }

  @override
  Future<List<PurchaseProductDetailsModel>> getSubscriptions(
    final List<PurchaseProductId> productIds,
  ) async {
    if (Platform.isIOS) {
      final products = await _appleNativeProvider.fetchProducts(productIds);
      return products
          .where(
            (final product) =>
                product.productType == PurchaseProductType.subscription,
          )
          .toList();
    }
    // TODO(arenukvern): implement identification of subscriptions
    final response = await _inAppPurchase.queryProductDetails(
      productIds.map((final id) => id.value).toSet(),
    );
    if (response.error != null) {
      _catchNoResponse(response.error!);
      throw Exception(response.error!.message);
    }
    return response.productDetails.map(_mapToProductDetails).toList();
  }

  @override
  Future<PurchaseResultModel> subscribe(
    final PurchaseProductDetailsModel productDetails,
  ) => purchaseNonConsumable(productDetails);

  @override
  Future<void> openSubscriptionManagement() async {
    await AppSettings.openAppSettings(type: AppSettingsType.subscriptions);
  }

  @override
  Future<PurchaseDetailsModel> getPurchaseDetails(
    final PurchaseId purchaseId,
  ) async {
    try {
      final purchases = await purchaseStream.firstWhere(
        (final list) =>
            list.any((final p) => p.purchaseId.value == purchaseId.value),
        orElse: () => throw Exception('Purchase not found'),
      );
      if (purchases.isEmpty) {
        throw Exception('Purchase not found');
      }
      return purchases.firstWhere(
        (final p) => p.purchaseId.value == purchaseId.value,
      );
    } catch (e) {
      throw Exception('Failed to get purchase details: $e');
    }
  }

  @override
  Future<CancelResultModel> cancel(final String purchaseOrProductId) async {
    try {
      if (Platform.isIOS) {
        return _appleNativeProvider.cancelSubscription();
      } else {
        await openSubscriptionManagement();
        return CancelResultModel.success();
      }
    } on PlatformException catch (e) {
      return CancelResultModel.failure(e.message ?? 'Unknown error');
    }
  }

  // There is no direct API in in_app_purchase to check if the store app is installed.
  // We'll use isAvailable() as a proxy, which checks if the underlying store is available.
  // This is not 100% accurate for "installed", but is the best available check.
  @override
  Future<bool> isStoreInstalled() => _inAppPurchase.isAvailable();
}

PurchaseDurationModel _extractDurationFromProductId(final String productId) {
  if (productId.contains('year')) {
    return PurchaseDurationModel(years: 1);
  } else if (productId.contains('month')) {
    return PurchaseDurationModel(months: 1);
  } else {
    return PurchaseDurationModel.zero;
  }
}

extension on PurchaseStatus {
  iap.PurchaseStatus _toFlutterIAPStatus() => switch (this) {
    PurchaseStatus.pending => iap.PurchaseStatus.pending,
    PurchaseStatus.purchased => iap.PurchaseStatus.purchased,
    PurchaseStatus.error => iap.PurchaseStatus.error,
    PurchaseStatus.pendingConfirmation => iap.PurchaseStatus.restored,
    PurchaseStatus.canceled => iap.PurchaseStatus.canceled,
  };
}

// extension on PurchaseProductId {
//   // the product should have clear structure in its id
//   Duration toDuration() {
//     if (value.contains('year')) {
//       return const Duration(days: 365);
//     } else if (value.contains('month')) {
//       return const Duration(days: 30);
//     } else {
//       return Duration.zero;
//     }
//   }
// }
