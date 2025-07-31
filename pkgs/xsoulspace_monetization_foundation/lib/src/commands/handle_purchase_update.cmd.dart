import 'package:flutter/widgets.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import '../resources/resources.dart';
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
  });
  final ConfirmPurchaseCommand confirmPurchaseCommand;
  final SubscriptionStatusResource subscriptionStatusResource;
  final ActiveSubscriptionResource activeSubscriptionResource;

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
        subscriptionStatusResource.set(
          SubscriptionStatus.pendingPaymentConfirmation,
        );
        return;
      case PurchaseStatus.canceled:
        activeSubscriptionResource.set(PurchaseDetailsModel.empty);
        subscriptionStatusResource.set(SubscriptionStatus.free);
        return;
    }
  }
}
