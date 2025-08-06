import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import 'commands/commands.dart';
import 'local_api/local_api.dart';
import 'resources/resources.dart';

/// {@template monetization_foundation}
/// Main orchestrator for the monetization system.
///
/// This class coordinates the initialization sequence:
/// 1. Sets initial loading state
/// 2. Initializes the purchase provider
/// 3. Loads available subscriptions
/// 4. Restores previous purchases
/// 5. Sets up purchase update listeners
///
/// ## Usage
/// ```dart
/// final foundation = MonetizationFoundation(
///   resources: (
///     activeSubscription: ActiveSubscriptionResource(),
///     availableSubscriptions: AvailableSubscriptionsResource(),
///     subscriptionStatus: SubscriptionStatusResource(),
///     status: MonetizationStatusResource(),
///   ),
///   purchaseProvider: yourProvider,
/// );
///
/// await foundation.init();
/// ```
/// {@endtemplate}
class MonetizationFoundation {
  /// {@macro monetization_foundation}
  MonetizationFoundation({
    required final MonetizationResources resources,
    required this.purchaseProvider,
    required this.purchasesLocalApi,
  }) : srcs = resources;

  /// {@macro purchase_provider}
  final PurchaseProvider purchaseProvider;

  /// {@macro purchases_local_api}
  final PurchasesLocalApi purchasesLocalApi;

  /// {@macro monetization_resources}
  @protected
  @visibleForTesting
  final MonetizationResources srcs;

  StreamSubscription<List<PurchaseDetailsModel>>? _purchaseUpdateSubscription;

  /// Restores previous purchases without full initialization.
  Future<void> restore() => _restorePurchasesCommand.execute();

  var _initCompleter = Completer<bool>();

  /// Future that completes when the initialization is complete.
  Future<bool> get initFuture => _initCompleter.future;

  final _productIds = <PurchaseProductId>[];
  void _assignProductIds(final Iterable<PurchaseProductId> productIds) {
    if (productIds.isEmpty) return;
    _productIds
      ..clear()
      ..addAll([...productIds]);
  }

  /// {@template init}
  /// Initializes the complete monetization system.
  ///
  /// **Sequence:**
  /// 1. Set loading state
  /// 2. Check if purchase provider is available
  /// 3. Initialize purchase provider
  /// 4. Update status based on initialization result
  /// 5. Load subscriptions if initialized
  /// 6. Restore purchases and set up listeners
  /// {@endtemplate}
  Future<void> init({
    required final List<PurchaseProductId> productIds,
    final bool restorePurchases = true,
    final bool force = false,
  }) async {
    if (force) {
      _initCompleter.complete(false);
      _initCompleter = Completer<bool>();
    } else if (_initCompleter.isCompleted) {
      return;
    }
    _assignProductIds(productIds);
    srcs.status.setStatus(MonetizationStoreStatus.loading);

    var status = await purchaseProvider.init();

    final isAvailable = await purchaseProvider.isStoreInstalled();
    final isAuthorized = await purchaseProvider.isUserAuthorized();
    if (!isAvailable) {
      status = MonetizationStoreStatus.notAvailable;
    } else if (!isAuthorized) {
      status = MonetizationStoreStatus.userNotAuthorized;
    }

    srcs.status.setStatus(status);

    if (status case MonetizationStoreStatus.loaded) {
      await _loadSubscriptionsCommand.execute();
      if (restorePurchases) await _restorePurchasesCommand.execute();
    }

    await _listenUpdates();
    _initCompleter.complete(true);
  }

  /// Loads products from the purchase provider.
  Future<void> loadSubscriptions({
    final List<PurchaseProductId> productIds = const [],
  }) async {
    _assignProductIds(productIds);
    await _loadSubscriptionsCommand.execute();
  }

  /// Checks if the user is authorized to use the purchase provider.
  Future<bool> isUserAuthorized() => purchaseProvider.isUserAuthorized();

  /// Checks if the store is installed on the device.
  Future<bool> isStoreInstalled() => purchaseProvider.isStoreInstalled();

  /// Restores purchases and sets up purchase update listeners.
  Future<void> _listenUpdates() async {
    await _purchaseUpdateSubscription?.cancel();
    _purchaseUpdateSubscription = purchaseProvider.purchaseStream.listen(
      _handlePurchaseUpdate,
    );
  }

  /// Handles incoming purchase updates from the provider.
  Future<void> _handlePurchaseUpdate(
    final List<PurchaseDetailsModel> purchases,
  ) async {
    for (final purchase in purchases) {
      await _handlePurchaseUpdateCommand.execute(purchase);
    }
  }

  /// Cleans up resources and cancels subscriptions.
  Future<void> dispose() async {
    await _purchaseUpdateSubscription?.cancel();
  }

  /// {@template cancel_subscription}
  /// Cancels a subscription.
  ///
  /// Returns isCancelled if subscription was cancelled.
  ///
  /// Redirects to store if subscription was not cancelled using API.
  /// {@endtemplate}
  Future<void> cancelSubscription({
    final PurchaseProductId productId = PurchaseProductId.empty,
    final PurchaseId purchaseId = PurchaseId.empty,
  }) => _cancelSubscriptionCommand.execute(
    productId: productId,
    purchaseId: purchaseId,
  );

  /// {@template subscribe}
  /// Subscribes to a product.
  /// {@endtemplate}
  Future<bool> subscribe(final PurchaseProductDetailsModel details) =>
      _subscribeCommand.execute(details);

  /// Opens the subscription management page.
  Future<void> openSubscriptionManagement() =>
      purchaseProvider.openSubscriptionManagement();

  /// Check if user has an active subscription
  Future<void> checkActiveSubscription({
    final bool shouldRestore = true,
  }) async {
    try {
      final isInitialized = await initFuture;
      if (!isInitialized) return;

      final isAuthorized = await isUserAuthorized();
      if (!isAuthorized) return;
      if (!shouldRestore) return;
      await restore();
      // TODO: check if subscription is active
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      // If we can't check subscription status, assume no active subscription
      return;
    }
  }
}

extension on MonetizationFoundation {
  SubscribeCommand get _subscribeCommand => SubscribeCommand(
    purchaseProvider: purchaseProvider,
    subscriptionStatusResource: srcs.subscriptionStatus,
    confirmPurchaseCommand: _confirmPurchaseCommand,
    cancelSubscriptionCommand: _cancelSubscriptionCommand,
    purchasePaywallErrorResource: srcs.purchasePaywallError,
  );

  ConfirmPurchaseCommand get _confirmPurchaseCommand => ConfirmPurchaseCommand(
    purchaseProvider: purchaseProvider,
    activeSubscriptionResource: srcs.activeSubscription,
    subscriptionStatusResource: srcs.subscriptionStatus,
    purchasePaywallErrorResource: srcs.purchasePaywallError,
  );

  CancelSubscriptionCommand get _cancelSubscriptionCommand =>
      CancelSubscriptionCommand(
        purchaseProvider: purchaseProvider,
        activeSubscriptionResource: srcs.activeSubscription,
        subscriptionStatusResource: srcs.subscriptionStatus,
        restorePurchasesCommand: _restorePurchasesCommand,
      );

  RestorePurchasesCommand get _restorePurchasesCommand =>
      RestorePurchasesCommand(
        purchaseProvider: purchaseProvider,
        purchasesLocalApi: purchasesLocalApi,
        handlePurchaseUpdateCommand: _handlePurchaseUpdateCommand,
        subscriptionStatusResource: srcs.subscriptionStatus,
      );

  HandlePurchaseUpdateCommand get _handlePurchaseUpdateCommand =>
      HandlePurchaseUpdateCommand(
        activeSubscriptionResource: srcs.activeSubscription,
        subscriptionStatusResource: srcs.subscriptionStatus,
        confirmPurchaseCommand: _confirmPurchaseCommand,
        purchasesLocalApi: purchasesLocalApi,
      );

  LoadSubscriptionsCommand get _loadSubscriptionsCommand =>
      LoadSubscriptionsCommand(
        purchaseProvider: purchaseProvider,
        monetizationStatusResource: srcs.status,
        availableSubscriptionsResource: srcs.availableSubscriptions,
        productIds: _productIds,
      );
}
