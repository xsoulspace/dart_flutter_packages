import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

/// {@template purchase_manager}
/// Manages in-app purchases by delegating to a specific [PurchaseProvider].
/// {@endtemplate}
class PurchaseManager {
  PurchaseManager(this.provider);
  final PurchaseProvider provider;

  Stream<List<PurchaseDetails>> get purchaseStream => provider.purchaseStream;

  Future<bool> isAvailable() => provider.isAvailable();

  Future<List<PurchaseProductDetails>> getProductDetails(
    final List<PurchaseProductId> productIds,
  ) => provider.getProductDetails(productIds);

  Future<PurchaseResult> purchase(
    final PurchaseProductDetails productDetails,
  ) => provider.purchase(productDetails);

  Future<RestoreResult> restorePurchases() => provider.restorePurchases();

  Future<CompletePurchaseResult> completePurchase(
    final PurchaseVerificationDto purchase,
  ) => provider.completePurchase(purchase);
}
