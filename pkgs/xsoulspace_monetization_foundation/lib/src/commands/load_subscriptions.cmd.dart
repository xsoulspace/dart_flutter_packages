import 'package:flutter/foundation.dart';
import 'package:xsoulspace_foundation/xsoulspace_foundation.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import '../resources/resources.dart';

/// {@template load_subscriptions_command}
/// Command to load available subscriptions from the store.
///
/// This command fetches subscription products from the purchase provider:
/// 1. Requests subscriptions for specified product IDs
/// 2. Updates the available subscriptions resource
/// 3. Handles platform-specific errors (e.g., unauthorized users)
/// 4. Updates monetization status based on availability
///
/// ## Usage
/// ```dart
/// final loadCommand = LoadSubscriptionsCommand(
///   purchaseProvider: provider,
///   monetizationStatusResource: statusResource,
///   availableSubscriptionsResource: subscriptionsResource,
///   productIds: ['premium_monthly', 'premium_yearly'],
/// );
///
/// await loadCommand.execute();
/// ```
///
/// ## Loading Flow
/// ```
/// Request Subscriptions → Provider Fetch → Update Resources
///     ↓
/// Handle Errors → Update Status → Complete
/// ```
///
/// ## Error Handling
/// - **RuStoreUserUnauthorizedException**: Sets status to store not authorized
/// - **Other Platform Exceptions**: Sets status to not available
/// - **General Errors**: Logs error and sets status to not available
/// {@endtemplate}
@immutable
class LoadSubscriptionsCommand {
  const LoadSubscriptionsCommand({
    required this.purchaseProvider,
    required this.monetizationStatusResource,
    required this.availableSubscriptionsResource,
    required this.productIds,
  });
  final List<PurchaseProductId> productIds;
  final PurchaseProvider purchaseProvider;
  final MonetizationStoreStatusResource monetizationStatusResource;
  final AvailableSubscriptionsResource availableSubscriptionsResource;

  /// {@template execute_load_subscriptions}
  /// Executes the subscription loading process.
  ///
  /// **Flow:**
  /// 1. Request subscriptions from the purchase provider
  /// 2. On success: update available subscriptions resource
  /// 3. On error: handle platform-specific exceptions
  /// 4. Update monetization status based on result
  ///
  /// **Error Handling:**
  /// - **RuStoreUserUnauthorizedException**: User needs to authorize with store
  /// - **Other PlatformExceptions**: Store is not available
  /// - **General Exceptions**: Log error and mark as not available
  ///
  /// **Resource Updates:**
  /// - `AvailableSubscriptionsResource`: Loaded with subscription products
  /// - `MonetizationStatusResource`: Updated based on availability
  /// {@endtemplate}
  Future<void> execute() async {
    try {
      final subscriptions = await purchaseProvider.getSubscriptions(productIds);
      availableSubscriptionsResource.set(
        LoadableContainer.loaded(subscriptions),
      );
    } catch (e) {
      if (!await purchaseProvider.isUserAuthorized()) {
        monetizationStatusResource.setStatus(
          MonetizationStoreStatus.userNotAuthorized,
        );
      }
      rethrow;
    }
  }
}
