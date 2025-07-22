import 'package:flutter/widgets.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import '../resources/resources.dart';
import 'confirm_purchase.cmd.dart';

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
    required this.confirmPurchaseCommand,
  });
  final SubscriptionStatusResource subscriptionStatusResource;
  final PurchaseProvider purchaseProvider;
  final ConfirmPurchaseCommand confirmPurchaseCommand;

  /// {@template execute}
  /// Executes the subscription purchase flow.
  ///
  /// **Returns:** `true` if subscription was successful, `false` otherwise.
  ///
  /// **Flow:**
  /// 1. Check if already subscribed → return false
  /// 2. Set status to pending
  /// 3. Attempt subscription via provider
  /// 4. On success: confirm purchase and return true
  /// 5. On failure: reset to free status and return false
  /// {@endtemplate}
  Future<bool> execute(final PurchaseProductDetailsModel details) async {
    if (subscriptionStatusResource.isSubscribed) return false;
    subscriptionStatusResource.set(SubscriptionStatus.pending);
    final result = await purchaseProvider.subscribe(details);
    switch (result.type) {
      case ResultType.success:
        return confirmPurchaseCommand.execute(
          result.details!.toVerificationDto(),
        );
      case ResultType.failure:
        subscriptionStatusResource.set(SubscriptionStatus.free);
    }
    return false;
  }
}
