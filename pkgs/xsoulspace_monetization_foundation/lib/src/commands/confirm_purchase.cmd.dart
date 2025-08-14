import 'package:flutter/widgets.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import '../../xsoulspace_monetization_foundation.dart';

/// {@template confirm_purchase_command}
/// Command to confirm and complete purchase transactions.
///
/// This command handles the final step of the purchase process:
/// 1. Validates purchase status (purchased, restored, or error)
/// 2. Completes the purchase through the provider
/// 3. Updates subscription state on success
/// 4. Retrieves and stores purchase details
///
/// ## Usage
/// ```dart
/// final confirmCommand = ConfirmPurchaseCommand(
///   purchaseProvider: provider,
///   activeSubscriptionResource: subscriptionResource,
///   subscriptionStatusResource: statusResource,
/// );
///
/// final success = await confirmCommand.execute(verificationDto);
/// ```
///
/// ## Purchase Flow
/// ```
/// Purchase Attempt → Provider Verification → ConfirmPurchaseCommand
///     ↓
/// Complete Purchase → Update Resources → Return Success/Failure
/// ```
/// {@endtemplate}
@immutable
class ConfirmPurchaseCommand {
  const ConfirmPurchaseCommand({
    required this.purchaseProvider,
    required this.activeSubscriptionResource,
    required this.subscriptionStatusResource,
    required this.purchasePaywallErrorResource,
    required this.purchasesLocalApi,
  });
  final ActiveSubscriptionResource activeSubscriptionResource;
  final SubscriptionStatusResource subscriptionStatusResource;
  final PurchaseProvider purchaseProvider;
  final PurchasePaywallErrorResource purchasePaywallErrorResource;
  final PurchasesLocalApi purchasesLocalApi;

  /// {@template execute_confirm_purchase}
  /// Executes the purchase confirmation process.
  ///
  /// **Parameters:**
  /// - `details`: Purchase verification data from the provider
  ///
  /// **Returns:** `true` if purchase was successfully confirmed, `false` otherwise.
  ///
  /// **Flow:**
  /// 1. Check if status is valid (purchased, restored, or error)
  /// 2. Complete purchase through provider
  /// 3. On success: retrieve purchase details and update resources
  /// 4. On failure: return false without updating state
  ///
  /// **Resource Updates:**
  /// - `ActiveSubscriptionResource`: Set to current purchase details
  /// - `SubscriptionStatusResource`: Set to subscribed status
  /// {@endtemplate}
  Future<bool> execute(final PurchaseVerificationDtoModel details) async {
    if (details.status case PurchaseStatus.pending || PurchaseStatus.canceled) {
      return false;
    }
    final result = await purchaseProvider.completePurchase(details);
    switch (result.type) {
      case ResultType.success:
        if (details.status
            case (PurchaseStatus.purchased ||
                PurchaseStatus.pendingConfirmation)) {
          final purchaseInfo = await purchaseProvider.getPurchaseDetails(
            details.purchaseId,
          );
          activeSubscriptionResource.set(purchaseInfo);
          subscriptionStatusResource.set(SubscriptionStatus.subscribed);
          await purchasesLocalApi.saveActiveSubscription(purchaseInfo);
          return true;
        }
      case ResultType.failure:
        purchasePaywallErrorResource.error = result.error;
        subscriptionStatusResource.set(SubscriptionStatus.free);
        // Handle failure if needed
        return false;
    }
    return false;
  }
}
