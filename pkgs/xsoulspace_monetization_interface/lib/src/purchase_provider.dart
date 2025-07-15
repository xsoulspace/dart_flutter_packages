import 'package:xsoulspace_monetization_interface/src/models.dart';

/// {@template purchase_provider}
/// An abstract interface for handling in-app purchases.
///
/// This class defines the contract that all purchase provider implementations
/// must adhere to, ensuring a consistent API for interacting with different
/// payment services like Google Play, Apple App Store, etc.
/// {@endtemplate}
abstract class PurchaseProvider {
  /// Stream that emits purchase updates.
  ///
  /// Listen to this stream to be notified of any changes in purchase states,
  /// such as new purchases, cancellations, or restorations.
  Stream<List<PurchaseDetails>> get purchaseStream;

  /// Checks if the payment provider is available on the current device.
  Future<bool> isAvailable();

  /// Retrieves the details of a list of products.
  ///
  /// - [productIds]: A list of [PurchaseProductId]s to fetch details for.
  Future<List<PurchaseProductDetails>> getProductDetails(
    List<PurchaseProductId> productIds,
  );

  /// Initiates the purchase flow for a given product.
  ///
  /// - [productDetails]: The [PurchaseProductDetails] of the item to buy.
  Future<PurchaseResult> purchase(PurchaseProductDetails productDetails);

  /// Restores any previously made non-consumable purchases.
  Future<RestoreResult> restorePurchases();

  /// Completes a purchase transaction.
  ///
  /// This is required on some platforms (like iOS and Google Play) to
  /// acknowledge that the user has received the content of the purchase.
  ///
  /// - [purchase]: The [PurchaseVerificationDto] of the purchase to complete.
  Future<CompletePurchaseResult> completePurchase(
    PurchaseVerificationDto purchase,
  );
}
