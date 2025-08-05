import 'package:flutter/material.dart';
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
    final bool openSubscriptionManagement = true,
  }) async {
    final oldStatus = subscriptionStatusResource.status;
    subscriptionStatusResource.set(SubscriptionStatus.cancelling);
    final activeSubscription = activeSubscriptionResource.subscription;
    if (productId.isEmpty || activeSubscription == null) {
      throw Exception('No active subscription to cancel');
    }
    final purchaseId = activeSubscription.purchaseId;
    final result = await purchaseProvider.cancel(purchaseId.value);
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
