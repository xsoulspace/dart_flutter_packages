import 'package:flutter/material.dart';
import 'package:is_dart_empty_or_not/is_dart_empty_or_not.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import '../resources/resources.dart';
import '../utils/chain.dart';
import 'restore_purchases.cmd.dart';

/// {@template cancel_subscription_command}
/// Command to cancel a subscription.
/// {@endtemplate}
@immutable
class CancelSubscriptionCommand implements ChainCommand {
  const CancelSubscriptionCommand({
    required this.purchaseProvider,
    required this.activeSubscriptionResource,
    required this.subscriptionStatusResource,
    required this.restorePurchasesCommand,
  });
  final PurchaseProvider purchaseProvider;
  final ActiveSubscriptionResource activeSubscriptionResource;
  final SubscriptionStatusResource subscriptionStatusResource;
  final RestorePurchasesCommand restorePurchasesCommand;

  /// {@template execute}
  /// Executes the cancel subscription flow.
  ///
  /// **Returns:** `true` if subscription was cancelled, `false` otherwise.
  ///
  /// **Flow:**
  /// 1. Check if already subscribed → return false
  /// 2. Set status to pending
  /// 3. Attempt subscription via provider
  /// 4. On success: confirm purchase and return true
  /// {@endtemplate}
  Future<void> execute({
    final PurchaseProductId productId = PurchaseProductId.empty,
    final PurchaseId purchaseId = PurchaseId.empty,
    final bool openSubscriptionManagement = true,
  }) async {
    final oldStatus = subscriptionStatusResource.status;
    subscriptionStatusResource.set(SubscriptionStatus.cancelling);
    final activeSubscription = activeSubscriptionResource.subscription;
    if (!activeSubscription.isActive &&
        purchaseId.isEmpty &&
        productId.isEmpty) {
      // Nothing to cancel
      subscriptionStatusResource.set(oldStatus);
      return;
    }

    final idToCancel = purchaseId.value
        .whenEmptyUse(productId.value)
        .whenEmptyUse(activeSubscription.purchaseId.value);

    final result = await purchaseProvider.cancel(idToCancel);
    if (result.isSuccess) {
      subscriptionStatusResource.set(oldStatus);
      return;
    }

    if (result.isFailure && openSubscriptionManagement) {
      await purchaseProvider.openSubscriptionManagement();
      await Future.delayed(const Duration(seconds: 1));
      // check if subscription is cancelled
      await restorePurchasesCommand.execute();
    }
    subscriptionStatusResource.set(oldStatus);
  }
}
