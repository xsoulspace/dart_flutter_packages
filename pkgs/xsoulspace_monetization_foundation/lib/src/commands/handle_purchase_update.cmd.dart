import 'package:flutter/widgets.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import '../local_api/local_api.dart';
import '../resources/resources.dart';
import 'cancel_subscription.cmd.dart';
import 'confirm_purchase.cmd.dart';

/// {@template handle_purchase_update_command}
/// Command to handle purchase status updates from the provider.
///
/// This command processes purchase updates based on their status:
/// - **Purchased/Restored**: Confirm the purchase and update subscription
/// - **Error**: Handle error state (currently delegates to confirm)
/// - **Pending**: Set subscription status to pending
/// - **Canceled**: Clear subscription and set status to free
///
/// ## Usage
/// ```dart
/// final updateCommand = HandlePurchaseUpdateCommand(
///   confirmPurchaseCommand: confirmCommand,
///   subscriptionStatusResource: statusResource,
///   activeSubscriptionResource: subscriptionResource,
/// );
///
/// await updateCommand.execute(verificationDto);
/// ```
///
/// ## Update Flow
/// ```
/// Purchase Update → Status Check → Appropriate Action
///     ↓
/// Update Resources → Complete Processing
/// ```
///
/// ## Status Handling
/// | Status | Action |
/// |--------|--------|
/// | purchased/restored | Confirm purchase |
/// | error | Handle error (TODO: add notification) |
/// | pending | Set pending status |
/// | canceled | Clear subscription |
/// {@endtemplate}
@immutable
class HandlePurchaseUpdateCommand {
  const HandlePurchaseUpdateCommand({
    required this.confirmPurchaseCommand,
    required this.subscriptionStatusResource,
    required this.activeSubscriptionResource,
    required this.purchasesLocalApi,
    required this.cancelSubscriptionCommand,
  });
  final ConfirmPurchaseCommand confirmPurchaseCommand;
  final SubscriptionStatusResource subscriptionStatusResource;
  final ActiveSubscriptionResource activeSubscriptionResource;
  final PurchasesLocalApi purchasesLocalApi;
  final CancelSubscriptionCommand cancelSubscriptionCommand;

  /// {@template execute_purchase_update}
  /// Executes the purchase update handling process.
  ///
  /// **Parameters:**
  /// - `dto`: Purchase verification data with status information
  ///
  /// **Status-Specific Actions:**
  /// - **purchased/restored**: Confirm purchase through `ConfirmPurchaseCommand`
  /// - **error**: Currently delegates to confirm (TODO: add error notification)
  /// - **pending**: Sets subscription status to pending
  /// - **canceled**: Clears active subscription and sets status to free
  ///
  /// **Resource Updates:**
  /// - `SubscriptionStatusResource`: Updated based on purchase status
  /// - `ActiveSubscriptionResource`: Cleared on cancellation
  /// {@endtemplate}
  Future<void> execute(final PurchaseDetailsModel details) async {
    final dto = details.toVerificationDto();
    switch (dto.status) {
      case PurchaseStatus.error:
        // TODO(arenukvern): add error notification
        await cancelSubscriptionCommand.execute(
          productId: dto.productId,
          purchaseId: dto.purchaseId,
          openSubscriptionManagement: false,
        );
      case PurchaseStatus.canceled:
        // noop
        break;
      case PurchaseStatus.pendingVerification || PurchaseStatus.purchased:
        await confirmPurchaseCommand.execute(dto);
    }
  }
}
