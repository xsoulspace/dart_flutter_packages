import 'package:flutter/widgets.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import 'handle_purchase_update.cmd.dart';

@immutable
class RestorePurchasesCommand {
  const RestorePurchasesCommand({
    required this.purchaseProvider,
    required this.handlePurchaseUpdateCommand,
  });
  final PurchaseProvider purchaseProvider;
  final HandlePurchaseUpdateCommand handlePurchaseUpdateCommand;

  Future<void> execute() async {
    final result = await purchaseProvider.restorePurchases();
    switch (result.type) {
      case ResultType.success:
        for (final purchase in result.restoredPurchases) {
          if (!purchase.isActive) continue;
          await handlePurchaseUpdateCommand.execute(
            purchase.toVerificationDto(),
          );
        }
      case ResultType.failure:
        // Handle failure if needed
        break;
    }
  }
}
