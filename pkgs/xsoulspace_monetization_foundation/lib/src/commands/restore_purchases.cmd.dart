import 'package:flutter/widgets.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

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
  const RestorePurchasesCommand({
    required this.purchaseProvider,
    required this.handlePurchaseUpdateCommand,
  });
  final PurchaseProvider purchaseProvider;
  final HandlePurchaseUpdateCommand handlePurchaseUpdateCommand;

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
  /// **Note:** This command delegates the actual purchase processing
  /// to `HandlePurchaseUpdateCommand` to maintain consistency with
  /// the purchase update flow.
  /// {@endtemplate}
  Future<bool> execute() async {
    final result = await purchaseProvider.restorePurchases();
    switch (result.type) {
      case ResultType.success:
        for (final purchase in result.restoredPurchases) {
          if (!purchase.isActive) continue;
          await handlePurchaseUpdateCommand.execute(
            purchase.toVerificationDto(),
          );
          if (purchase.isActive) return true;
        }
        return false;
      case ResultType.failure:
        // Handle failure if needed
        return false;
    }
  }
}
