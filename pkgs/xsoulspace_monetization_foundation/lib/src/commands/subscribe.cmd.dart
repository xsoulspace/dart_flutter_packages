import 'package:flutter/widgets.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import '../resources/resources.dart';
import 'confirm_purchase.cmd.dart';

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
