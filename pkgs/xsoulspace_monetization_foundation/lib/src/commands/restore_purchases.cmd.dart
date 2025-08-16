import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import '../local_api/local_api.dart';
import '../resources/resources.dart';
import 'handle_purchase_update.cmd.dart';

/// {@template restore_purchases_command}
/// Command to restore previous purchases from the store.
///
/// This command handles the restoration of previously purchased items:
/// 1. Requests restoration from the purchase provider
/// 2. Filters for active purchases only
/// 3. Processes each restored purchase through the update handler
/// 4. Maintains purchase state consistency
///
/// ## Usage
/// ```dart
/// final restoreCommand = RestorePurchasesCommand(
///   purchaseProvider: provider,
///   handlePurchaseUpdateCommand: updateCommand,
/// );
///
/// await restoreCommand.execute();
/// ```
///
/// ## Restoration Flow
/// ```
/// Restore Request → Provider Restore → Filter Active Purchases
///     ↓
/// Process Each Purchase → Update Resources → Complete
/// ```
///
/// ## When to Use
/// - App startup to restore previous purchases
/// - User manually requests purchase restoration
/// - After app reinstall or device change
/// {@endtemplate}
@immutable
class RestorePurchasesCommand {
  /// {@macro restore_purchases_command}
  const RestorePurchasesCommand({
    required this.purchaseProvider,
    required this.purchasesLocalApi,
    required this.handlePurchaseUpdateCommand,
    required this.subscriptionStatusResource,
  });
  final PurchaseProvider purchaseProvider;
  final PurchasesLocalApi purchasesLocalApi;
  final HandlePurchaseUpdateCommand handlePurchaseUpdateCommand;
  final SubscriptionStatusResource subscriptionStatusResource;

  /// {@template execute_restore_purchases}
  /// Executes the purchase restoration process.
  ///
  /// **Flow:**
  /// 1. Request restoration from the purchase provider
  /// 2. On success: process each restored purchase
  /// 3. Filter for active purchases only (skip expired/canceled)
  /// 4. Handle each purchase through the update command
  /// 5. On failure: silently handle (no state changes)
  ///
  /// Will await restore even if `shouldAwaitRestore` is `false` if there is no
  /// active subscription.
  ///
  /// **Note:** This command delegates the actual purchase processing
  /// to `HandlePurchaseUpdateCommand` to maintain consistency with
  /// the purchase update flow.
  /// {@endtemplate}
  Future<void> execute({final bool shouldAwaitRestore = true}) async {
    // Do not downgrade status when already subscribed locally; just run restore.
    if (!subscriptionStatusResource.isSubscribed) {
      subscriptionStatusResource.set(SubscriptionStatus.restoring);
    }

    if (shouldAwaitRestore) {
      await _runStoreRestore();
    } else {
      unawaited(_runStoreRestore());
    }
  }

  Future<void> _runStoreRestore() async {
    final result = await purchaseProvider.restorePurchases();
    switch (result.type) {
      case ResultType.success:
        for (final purchase in result.restoredPurchases) {
          if (purchase.isActive) {
            await handlePurchaseUpdateCommand.execute(purchase);
            continue;
          } else if (purchase.isPending) {
            try {
              await purchaseProvider.cancel(purchase.productId.value);
              // ignore: avoid_catches_without_on_clauses
            } catch (e) {
              debugPrint('RestorePurchasesCommand.execute: $e');
            }
            try {
              await purchaseProvider.cancel(purchase.purchaseId.value);
              // ignore: avoid_catches_without_on_clauses
            } catch (e) {
              debugPrint('RestorePurchasesCommand.execute: $e');
            }
          } else if (purchase.isPendingConfirmation) {
            await handlePurchaseUpdateCommand.execute(purchase);
          }
        }
      case ResultType.failure:
      // Handle failure if needed
    }
    // Finalize state based on actual active subscription presence
    final locallyActive = await purchasesLocalApi.getActiveSubscription();
    if (subscriptionStatusResource.isSubscribed || locallyActive.isActive) {
      subscriptionStatusResource.set(SubscriptionStatus.subscribed);
    } else {
      subscriptionStatusResource.set(SubscriptionStatus.free);
      await purchasesLocalApi.clearActiveSubscription();
    }
  }
}
