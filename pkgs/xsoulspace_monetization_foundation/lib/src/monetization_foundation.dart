import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import 'commands/commands.dart';
import 'models/models.dart';
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
  }) : srcs = resources;

  /// {@macro purchase_provider}
  final PurchaseProvider purchaseProvider;

  /// {@macro monetization_resources}
  @protected
  @visibleForTesting
  final MonetizationResources srcs;

  StreamSubscription<List<PurchaseDetailsModel>>? _purchaseUpdateSubscription;

  /// Restores previous purchases without full initialization.
  Future<bool> restore() => _restorePurchasesCommand.execute();

  final _initCompleter = Completer<bool>();

  /// Future that completes when the initialization is complete.
  Future<bool> get initFuture => _initCompleter.future;

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
  }) async {
    if (_initCompleter.isCompleted) return;
    srcs.status.setStatus(MonetizationStatus.loading);
    final isAvailable = await purchaseProvider.isUserAuthorized();
    if (!isAvailable) {
      srcs.status.setStatus(MonetizationStatus.notAvailable);
      return;
    }

    final isInitialized = await purchaseProvider.init();

    srcs.status.setStatus(
      isInitialized
          ? MonetizationStatus.loaded
          : MonetizationStatus.notAvailable,
    );
    if (!isInitialized) {
      _initCompleter.complete(false);
      return;
    }

    await LoadSubscriptionsCommand(
      purchaseProvider: purchaseProvider,
      monetizationStatusResource: srcs.status,
      availableSubscriptionsResource: srcs.availableSubscriptions,
      productIds: productIds,
    ).execute();

    if (restorePurchases) await _restorePurchasesCommand.execute();

    await _listenUpdates();
    _initCompleter.complete(true);
  }

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
      await _handlePurchaseUpdateCommand.execute(purchase.toVerificationDto());
    }
  }

  /// Cleans up resources and cancels subscriptions.
  Future<void> dispose() async {
    await _purchaseUpdateSubscription?.cancel();
  }

  /// {@template subscribe}
  /// Subscribes to a product.
  /// {@endtemplate}
  Future<bool> subscribe(final PurchaseProductDetailsModel details) async =>
      SubscribeCommand(
        purchaseProvider: purchaseProvider,
        subscriptionStatusResource: srcs.subscriptionStatus,
        confirmPurchaseCommand: _confirmPurchaseCommand,
      ).execute(details);
}

extension on MonetizationFoundation {
  ConfirmPurchaseCommand get _confirmPurchaseCommand => ConfirmPurchaseCommand(
    purchaseProvider: purchaseProvider,
    activeSubscriptionResource: srcs.activeSubscription,
    subscriptionStatusResource: srcs.subscriptionStatus,
  );

  RestorePurchasesCommand get _restorePurchasesCommand =>
      RestorePurchasesCommand(
        purchaseProvider: purchaseProvider,
        handlePurchaseUpdateCommand: _handlePurchaseUpdateCommand,
      );

  HandlePurchaseUpdateCommand get _handlePurchaseUpdateCommand =>
      HandlePurchaseUpdateCommand(
        activeSubscriptionResource: srcs.activeSubscription,
        subscriptionStatusResource: srcs.subscriptionStatus,
        confirmPurchaseCommand: ConfirmPurchaseCommand(
          purchaseProvider: purchaseProvider,
          activeSubscriptionResource: srcs.activeSubscription,
          subscriptionStatusResource: srcs.subscriptionStatus,
        ),
      );
}
