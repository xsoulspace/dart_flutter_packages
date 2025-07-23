import 'package:xsoulspace_monetization_interface/src/models.dart';

import 'monetization_status.dart';

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
  Future<MonetizationStatus> init();

  /// Stream that emits purchase updates.
  ///
  /// Listen to this stream to be notified of any changes in purchase states,
  /// such as new purchases, cancellations, or restorations.

  // TODO(arenukvern): adjust this to all implementations
  /// Currently copied from in_app_purchase_manager.dart:
  ///
  /// Listen to this broadcast stream to get real time update for purchases.
  /// This stream will never close as long as the app is active.
  ///
  /// Purchase updates can happen in several situations:
  ///
  /// When a purchase is triggered by user in the app.
  /// When a purchase is triggered by user from the platform-specific
  /// store front.
  /// When a purchase is restored on the device by the user in the app.
  /// If a purchase is not completed ([completePurchase] is not called
  /// on the purchase object) from the last app session. Purchase updates
  /// will happen when a new app session starts instead.
  ///
  /// IMPORTANT! You must subscribe to this stream as soon as your app
  /// launches, preferably before returning your main App Widget in main().
  /// Otherwise you will miss purchase updated made before this
  /// stream is subscribed to.
  ///
  /// We also recommend listening to the stream with one subscription
  /// at a given time. If you choose to have multiple subscription at the
  /// same time, you should be careful at the fact that each subscription
  /// will receive all the events after they start to listen.
  Stream<List<PurchaseDetailsModel>> get purchaseStream;

  /// Checks if the store has authorized user.
  ///
  /// This is important if store (for example) Google Play has not authorized
  /// user yet - then the purchase flow will not work.
  Future<bool> isUserAuthorized();

  /// Checks if the store is installed on the device.
  Future<bool> isStoreInstalled();

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
