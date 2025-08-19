import 'package:flutter/widgets.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import '../resources/resources.dart';
import 'cancel_subscription.cmd.dart';

/// {@template subscribe_command}
/// Command to handle subscription purchases.
///
/// This command implements the Command pattern for subscription operations:
/// 1. Checks if user is already subscribed
/// 2. Sets pending status
/// 3. Attempts subscription through provider
/// 4. Confirms purchase on success
/// 5. Resets status on failure
///
/// ## Usage
/// ```dart
/// final subscribeCommand = SubscribeCommand(
///   purchaseProvider: provider,
///   subscriptionStatusResource: statusResource,
///   confirmPurchaseCommand: confirmCommand,
/// );
///
/// final success = await subscribeCommand.execute(productDetails);
/// ```
/// {@endtemplate}
@immutable
class SubscribeCommand {
  const SubscribeCommand({
    required this.purchaseProvider,
    required this.subscriptionStatusResource,
    required this.cancelSubscriptionCommand,
    required this.purchasePaywallErrorResource,
  });
  final SubscriptionStatusResource subscriptionStatusResource;
  final PurchaseProvider purchaseProvider;
  final CancelSubscriptionCommand cancelSubscriptionCommand;
  final PurchasePaywallErrorResource purchasePaywallErrorResource;

  /// {@template execute}
  /// Executes the subscription purchase flow.
  ///
  /// **Returns:** `true` if subscription was successful, `false` otherwise.
  ///
  /// **Flow:**
  /// 1. Check if already subscribed → return false
  /// 2. Set status to pending
  /// 3. Attempt subscription via provider
  /// 4. On success: since the transaction will be sent to the stream,
  /// the stream handler will handle the purchase confirmation.
  /// 5. On failure: reset to free status
  ///
  /// The result will be sent to the stream.
  /// {@endtemplate}
  Future<void> execute(final PurchaseProductDetailsModel details) async {
    if (subscriptionStatusResource.isSubscribed) return;
    final previousStatus = subscriptionStatusResource.status;
    subscriptionStatusResource.set(SubscriptionStatus.purchasing);
    purchasePaywallErrorResource.clear();

    final result = await purchaseProvider.subscribe(details);
    final resultDetails = result.details;
    switch (result.type) {
      case ResultType.success:
        subscriptionStatusResource.set(
          SubscriptionStatus.pendingPaymentConfirmation,
        );

      case ResultType.failure:
        subscriptionStatusResource.set(previousStatus);
        if (resultDetails == null || resultDetails.isCancelled) return;

        purchasePaywallErrorResource.error = result.error;

        /// handle case when upgrading / downgrading subscription
        await cancelSubscriptionCommand.execute(
          productId: details.productId,
          openSubscriptionManagement: false,
        );
    }
  }
}
