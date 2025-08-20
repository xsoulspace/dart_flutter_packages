import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import '../resources/resources.dart';

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
    required this.subscriptionStatusResource,
  });
  final PurchaseProvider purchaseProvider;
  final SubscriptionStatusResource subscriptionStatusResource;

  /// {@template execute_restore_purchases}
  /// Executes the purchase restoration process.
  ///
  /// This simple function just sets the status to restoring and runs the
  /// restore.
  /// From native side, it loops through the transactions and sends it to
  /// the stream, so every result would be handled there.
  /// {@endtemplate}
  Future<void> execute() async {
    if (subscriptionStatusResource.isRestoring) return;
    final oldStatus = subscriptionStatusResource.status;
    final shouldSetStatus = !subscriptionStatusResource.isSubscribed;
    if (shouldSetStatus) {
      // Make not downgrade status when already subscribed locally; just
      // run restore.
      subscriptionStatusResource.set(SubscriptionStatus.restoring);
    }

    await purchaseProvider.restorePurchases();

    if (shouldSetStatus) {
      subscriptionStatusResource.set(oldStatus);
    }
  }
}
