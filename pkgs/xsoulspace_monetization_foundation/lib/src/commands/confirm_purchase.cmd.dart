import 'package:flutter/widgets.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import '../resources/resources.dart';

@immutable
class ConfirmPurchaseCommand {
  const ConfirmPurchaseCommand({
    required this.purchaseProvider,
    required this.activeSubscriptionResource,
    required this.subscriptionStatusResource,
  });
  final ActiveSubscriptionResource activeSubscriptionResource;
  final SubscriptionStatusResource subscriptionStatusResource;
  final PurchaseProvider purchaseProvider;

  Future<bool> execute(final PurchaseVerificationDtoModel details) async {
    if (details.status
        case PurchaseStatus.error ||
            PurchaseStatus.purchased ||
            PurchaseStatus.restored) {
      final result = await purchaseProvider.completePurchase(details);
      switch (result.type) {
        case ResultType.success:
          if (details.status
              case (PurchaseStatus.purchased || PurchaseStatus.restored)) {
            final purchaseInfo = await purchaseProvider.getPurchaseDetails(
              details.purchaseId,
            );
            activeSubscriptionResource.set(purchaseInfo);
            subscriptionStatusResource.set(SubscriptionStatus.subscribed);

            return true;
          }
        case ResultType.failure:
          // Handle failure if needed
          return false;
      }
    }

    return false;
  }
}
