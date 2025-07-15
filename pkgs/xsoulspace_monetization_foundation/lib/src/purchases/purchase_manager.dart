import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

/// {@template purchase_manager}
/// Manages in-app purchases by delegating to a specific [PurchaseProvider].
/// {@endtemplate}
class PurchaseManager {
  PurchaseManager(this.provider);
  final PurchaseProvider provider;

  /// Retrieves available consumable items.
  Future<List<PurchaseProductDetailsModel>> getConsumables(
    final List<PurchaseProductId> productIds,
  ) => provider.getConsumables(productIds);

  /// Retrieves available non-consumable items.
  Future<List<PurchaseProductDetailsModel>> getNonConsumables(
    final List<PurchaseProductId> productIds,
  ) => provider.getNonConsumables(productIds);

  /// Opens the subscription management page.
  Future<void> openSubscriptionManagement() =>
      provider.openSubscriptionManagement();

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
  Stream<List<PurchaseDetailsModel>> get purchaseStream =>
      provider.purchaseStream;

  /// Restores previously made purchases.
  Future<RestoreResultModel> restorePurchases() => provider.restorePurchases();

  /// Initializes the purchase provider. Returns true if the provider is
  /// initialized successfully, false otherwise.
  Future<bool> init() => provider.init();

  /// Checks if the payment provider is available on the current device.
  Future<bool> isAvailable() => provider.isAvailable();

  /// Retrieves the details of a list of products.
  Future<List<PurchaseProductDetailsModel>> getProductDetails(
    final List<PurchaseProductId> productIds,
  ) => provider.getProductDetails(productIds);

  /// Retrieves the details of a purchase.
  Future<PurchaseDetailsModel> getPurchaseDetails(final PurchaseId productId) =>
      provider.getPurchaseDetails(productId);

  /// Retrieves the details of a list of subscriptions.
  Future<List<PurchaseProductDetailsModel>> getSubscriptions(
    final List<PurchaseProductId> productIds,
  ) => provider.getSubscriptions(productIds);

  /// You should call this after receiving [PurchaseStatus.error] or
  /// [PurchaseStatus.restored] or [PurchaseStatus.purchased]
  /// to complete the purchase.
  Future<CompletePurchaseResultModel> completePurchase(
    final PurchaseVerificationDtoModel purchase,
  ) => provider.completePurchase(purchase);

  /// Purchases a product.
  Future<PurchaseResultModel> purchaseNonConsumable(
    final PurchaseProductDetailsModel productDetails,
  ) => provider.purchaseNonConsumable(productDetails);

  /// Subscribes to a product.
  Future<PurchaseResultModel> subscribe(
    final PurchaseProductDetailsModel details,
  ) => provider.subscribe(details);

  /// Cancels a purchase.
  Future<CancelResultModel> cancel(final PurchaseProductId productId) =>
      provider.cancel(productId);
}
