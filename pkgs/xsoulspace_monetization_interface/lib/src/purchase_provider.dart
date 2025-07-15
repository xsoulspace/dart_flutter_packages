import 'package:xsoulspace_monetization_interface/src/models.dart';

/// {@template purchase_provider}
/// An abstract interface for handling in-app purchases.
///
/// This class defines the contract that all purchase provider implementations
/// must adhere to, ensuring a consistent API for interacting with different
/// payment services like Google Play, Apple App Store, etc.
/// {@endtemplate}
abstract class PurchaseProvider {
  /// Initializes the purchase provider. Returns true if the provider is
  /// initialized successfully, false otherwise.
  Future<bool> init();

  /// Stream that emits purchase updates.
  ///
  /// Listen to this stream to be notified of any changes in purchase states,
  /// such as new purchases, cancellations, or restorations.
  Stream<List<PurchaseDetailsModel>> get purchaseStream;

  /// Checks if the payment provider is available on the current device.
  Future<bool> isAvailable();

  /// Retrieves the details of a list of consumables.
  Future<List<PurchaseProductDetailsModel>> getConsumables(
    List<PurchaseProductId> productIds,
  );

  /// Retrieves the details of a list of non-consumables.
  Future<List<PurchaseProductDetailsModel>> getNonConsumables(
    List<PurchaseProductId> productIds,
  );

  /// Retrieves the details of a list of products.
  ///
  /// - [productIds]: A list of [PurchaseProductId]s to fetch details for.
  Future<List<PurchaseProductDetailsModel>> getProductDetails(
    List<PurchaseProductId> productIds,
  );

  /// Retrieves the details of a list of subscriptions.
  Future<List<PurchaseProductDetailsModel>> getSubscriptions(
    List<PurchaseProductId> productIds,
  );

  /// Retrieves the details of a purchase.
  Future<PurchaseDetailsModel> getPurchaseDetails(PurchaseId productId);

  /// Initiates the purchase flow for a given product.
  ///
  /// - [productDetails]: The [PurchaseProductDetails] of the item to buy.
  Future<PurchaseResultModel> purchaseNonConsumable(
    PurchaseProductDetailsModel productDetails,
  );

  /// Restores any previously made non-consumable purchases.
  Future<RestoreResultModel> restorePurchases();

  /// Completes a purchase transaction.
  ///
  /// This is required on some platforms (like iOS and Google Play) to
  /// acknowledge that the user has received the content of the purchase.
  ///
  /// - [purchase]: The [PurchaseVerificationDto] of the purchase to complete.
  Future<CompletePurchaseResultModel> completePurchase(
    PurchaseVerificationDtoModel purchase,
  );

  /// Subscribes to a product.
  Future<PurchaseResultModel> subscribe(
    PurchaseProductDetailsModel productDetails,
  );

  /// Cancels a purchase.
  Future<CancelResultModel> cancel(PurchaseProductId productId);

  /// Opens the subscription management page.
  Future<void> openSubscriptionManagement();

  /// Disposes the purchase provider.
  Future<void> dispose();
}
