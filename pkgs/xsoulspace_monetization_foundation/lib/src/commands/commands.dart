/// {@template monetization_commands}
/// Business logic commands for the monetization system.
///
/// This module implements the Command pattern to encapsulate all business logic
/// related to purchases, subscriptions, and monetization state management.
///
/// ## Command Pattern Benefits
/// - **Immutability**: All commands are immutable and stateless
/// - **Testability**: Business logic is isolated and easily testable
/// - **Composability**: Commands can be combined and reused
/// - **Separation of Concerns**: UI logic separated from business logic
///
/// ## Available Commands
///
/// ### Purchase Flow Commands
/// - `SubscribeCommand`: Handle new subscription purchases
/// - `ConfirmPurchaseCommand`: Complete and verify purchases
/// - `RestorePurchasesCommand`: Restore previous purchases
///
/// ### State Management Commands
/// - `HandlePurchaseUpdateCommand`: Process purchase status updates
/// - `LoadSubscriptionsCommand`: Load available subscription products
///
/// ## Usage Pattern
/// ```dart
/// // Create commands with dependencies
/// final subscribeCommand = SubscribeCommand(
///   purchaseProvider: provider,
///   subscriptionStatusResource: statusResource,
///   confirmPurchaseCommand: confirmCommand,
/// );
///
/// // Execute commands
/// final success = await subscribeCommand.execute(productDetails);
///
/// // Commands update resources, UI reacts to changes
/// ```
///
/// ## Command Dependencies
/// Commands typically depend on:
/// - `PurchaseProvider`: Platform-specific purchase operations
/// - `Resource` classes: State management and persistence
/// - Other commands: For complex workflows
///
/// ## Testing Commands
/// ```dart
/// test('SubscribeCommand should update status on success', () async {
///   final command = SubscribeCommand(...);
///   await command.execute(productDetails);
///   expect(statusResource.status, SubscriptionStatus.subscribed);
/// });
/// ```
/// {@endtemplate}
library;

export 'cancel_subscription.cmd.dart';
export 'clear_local_subscription.cmd.dart';
export 'confirm_purchase.cmd.dart';
export 'handle_purchase_update.cmd.dart';
export 'load_subscriptions.cmd.dart';
export 'restore_local_purchases.cmd.dart';
export 'restore_purchases.cmd.dart';
export 'subscribe.cmd.dart';
