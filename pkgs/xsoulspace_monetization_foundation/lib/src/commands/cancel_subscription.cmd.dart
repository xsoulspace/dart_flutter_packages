import 'package:flutter/material.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import '../resources/resources.dart';

/// {@template cancel_subscription_command}
/// Command to cancel a subscription.
/// {@endtemplate}
@immutable
class CancelSubscriptionCommand {
  const CancelSubscriptionCommand({
    required this.purchaseProvider,
    required this.activeSubscriptionResource,
    required this.subscriptionStatusResource,
  });
  final PurchaseProvider purchaseProvider;
  final ActiveSubscriptionResource activeSubscriptionResource;
  final SubscriptionStatusResource subscriptionStatusResource;

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
  Future<CancelResultModel> execute({
    final PurchaseProductId productId = PurchaseProductId.empty,
  }) async {
    subscriptionStatusResource.set(SubscriptionStatus.cancelling);
    var effectiveProductId = productId;
    if (productId.isEmpty) {
      final activeSubscription = activeSubscriptionResource.subscription;
      if (activeSubscription == null) {
        return CancelResultModel.failure('No active subscription');
      }
      effectiveProductId = activeSubscription.productId;
    }
    final result = await purchaseProvider.cancel(effectiveProductId.value);
    if (result.isSuccess) {
      subscriptionStatusResource.set(SubscriptionStatus.free);
    }
    return result;
  }
}
