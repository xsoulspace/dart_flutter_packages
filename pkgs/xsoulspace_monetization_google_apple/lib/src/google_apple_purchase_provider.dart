// ignore_for_file: avoid_catches_without_on_clauses

import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart' as iap;
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

/// {@template google_apple_purchase_provider}
/// Implementation of [PurchaseProvider] using the `in_app_purchase` package.
/// {@endtemplate}
class GoogleApplePurchaseProvider implements PurchaseProvider {
  final iap.InAppPurchase _inAppPurchase = iap.InAppPurchase.instance;
  late StreamSubscription<List<iap.PurchaseDetails>> _purchaseSubscription;

  final _purchaseStreamController =
      StreamController<List<PurchaseDetails>>.broadcast();

  /// Initializes the purchase provider.
  Future<void> init() async {
    _purchaseSubscription = _inAppPurchase.purchaseStream.listen(
      (purchaseDetailsList) {
        final purchases = purchaseDetailsList
            .map(_mapToPurchaseDetails)
            .toList();
        _purchaseStreamController.add(purchases);
      },
      onDone: () => _purchaseStreamController.close(),
      onError: (error) => _purchaseStreamController.addError(error),
    );
  }

  void dispose() {
    _purchaseSubscription.cancel();
    _purchaseStreamController.close();
  }

  @override
  Stream<List<PurchaseDetails>> get purchaseStream =>
      _purchaseStreamController.stream;

  @override
  Future<bool> isAvailable() => _inAppPurchase.isAvailable();

  @override
  Future<CompletePurchaseResult> completePurchase(
    PurchaseVerificationDto purchase,
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
      return const CompletePurchaseResult.success();
    } catch (e) {
      return CompletePurchaseResult.failure(e.toString());
    }
  }

  @override
  Future<List<PurchaseProductDetails>> getProductDetails(
    List<PurchaseProductId> productIds,
  ) async {
    final response = await _inAppPurchase.queryProductDetails(
      productIds.map((id) => id.value).toSet(),
    );
    if (response.error != null) {
      throw Exception(response.error!.message);
    }
    return response.productDetails.map(_mapToProductDetails).toList();
  }

  @override
  Future<PurchaseResult> purchase(PurchaseProductDetails productDetails) async {
    final response = await _inAppPurchase.queryProductDetails({
      productDetails.productId.value,
    });
    if (response.error != null) {
      return PurchaseResult.failure(response.error!.message);
    }
    if (response.productDetails.isEmpty) {
      return PurchaseResult.failure(
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
        return PurchaseResult.success(
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
        );
      } else {
        return const PurchaseResult.failure('Purchase initiation failed.');
      }
    } catch (e) {
      return PurchaseResult.failure(e.toString());
    }
  }

  @override
  Future<RestoreResult> restorePurchases() async {
    try {
      await _inAppPurchase.restorePurchases();
      // Restore results are also delivered via the purchaseStream.
      // This method simply triggers the process.
      return const RestoreResult.success([]);
    } catch (e) {
      return RestoreResult.failure(e.toString());
    }
  }

  PurchaseProductDetails _mapToProductDetails(iap.ProductDetails product) {
    return PurchaseProductDetails(
      productId: PurchaseProductId(product.id),
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
      duration: product.id.contains('year')
          ? const Duration(days: 365)
          : (product.id.contains('month')
                ? const Duration(days: 30)
                : Duration.zero),
    );
  }

  PurchaseDetails _mapToPurchaseDetails(iap.PurchaseDetails purchase) {
    return PurchaseDetails(
      purchaseId: PurchaseId(purchase.purchaseID ?? ''),
      productId: PurchaseProductId(purchase.productID),
      name: '', // Not available in iap.PurchaseDetails
      formattedPrice: '', // Not available in iap.PurchaseDetails
      status: _mapPurchaseStatus(purchase.status),
      price: 0.0, // Not available in iap.PurchaseDetails
      currency: '', // Not available in iap.PurchaseDetails
      purchaseDate: purchase.transactionDate != null
          ? DateTime.fromMillisecondsSinceEpoch(
              int.parse(purchase.transactionDate!),
            )
          : DateTime.now(),
      purchaseType: PurchaseProductType
          .nonConsumable, // This needs to be determined properly
      localVerificationData: purchase.verificationData.localVerificationData,
      serverVerificationData: purchase.verificationData.serverVerificationData,
      source: purchase.verificationData.source,
    );
  }

  PurchaseStatus _mapPurchaseStatus(iap.PurchaseStatus status) =>
      switch (status) {
        iap.PurchaseStatus.pending => PurchaseStatus.pending,
        iap.PurchaseStatus.purchased => PurchaseStatus.purchased,
        iap.PurchaseStatus.error => PurchaseStatus.error,
        iap.PurchaseStatus.restored => PurchaseStatus.restored,
        iap.PurchaseStatus.canceled => PurchaseStatus.canceled,
        // iap.PurchaseStatus.deferred is not in all versions
        _ => PurchaseStatus.pending,
      };
}

extension on PurchaseStatus {
  iap.PurchaseStatus _toFlutterIAPStatus() => switch (this) {
    PurchaseStatus.pending => iap.PurchaseStatus.pending,
    PurchaseStatus.purchased => iap.PurchaseStatus.purchased,
    PurchaseStatus.error => iap.PurchaseStatus.error,
    PurchaseStatus.restored => iap.PurchaseStatus.restored,
    PurchaseStatus.canceled => iap.PurchaseStatus.canceled,
  };
}
