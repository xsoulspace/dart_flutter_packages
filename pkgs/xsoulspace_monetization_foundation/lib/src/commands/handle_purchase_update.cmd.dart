import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import '../resources/resources.dart';
import 'confirm_purchase.cmd.dart';

class HandlePurchaseUpdateCommand {
  HandlePurchaseUpdateCommand({
    required this.confirmPurchaseCommand,
    required this.subscriptionStatusResource,
    required this.activeSubscriptionResource,
  });
  final ConfirmPurchaseCommand confirmPurchaseCommand;
  final SubscriptionStatusResource subscriptionStatusResource;
  final ActiveSubscriptionResource activeSubscriptionResource;

  Future<void> execute(final PurchaseVerificationDtoModel dto) async {
    switch (dto.status) {
      case PurchaseStatus.restored:
      case PurchaseStatus.purchased:
        await confirmPurchaseCommand.execute(dto);
        return;
      case PurchaseStatus.error:
        // TODO(arenukvern): add error notification
        await confirmPurchaseCommand.execute(dto);
      case PurchaseStatus.pending:
        subscriptionStatusResource.set(SubscriptionStatus.pending);
        return;
      case PurchaseStatus.canceled:
        activeSubscriptionResource.set(null);
        subscriptionStatusResource.set(SubscriptionStatus.free);
        return;
    }
  }
}
