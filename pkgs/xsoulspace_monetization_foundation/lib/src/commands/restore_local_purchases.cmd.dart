import 'package:flutter/widgets.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import '../local_api/local_api.dart';
import '../resources/resources.dart';

/// {@template restore_local_purchases_command}
/// Command that restores subscription state from local storage only.
///
/// It is designed for fast startup flows where we want to reflect the
/// locally-known active subscription immediately, without waiting for the
/// store/provider initialization or network calls.
///
/// Returns `true` when the locally stored subscription is active.
/// {@endtemplate}
@immutable
class RestoreLocalPurchasesCommand {
  /// {@macro restore_local_purchases_command}
  const RestoreLocalPurchasesCommand({
    required this.purchasesLocalApi,
    required this.subscriptionStatusResource,
  });

  final PurchasesLocalApi purchasesLocalApi;
  final SubscriptionStatusResource subscriptionStatusResource;

  /// {@template restore_local_execute}
  /// Checks local storage for an active subscription and updates the
  /// `SubscriptionStatusResource` to `subscribed` when found.
  ///
  /// Does not set the status to `free` if not found, to avoid overriding any
  /// concurrent flows. Returns whether an active subscription was detected.
  /// {@endtemplate}
  Future<void> execute() async {
    final activeSubscription = await purchasesLocalApi.getActiveSubscription();
    final status = activeSubscription?.status;
    if (activeSubscription == null || status == null) {
      subscriptionStatusResource.set(SubscriptionStatus.free);
    } else {
      subscriptionStatusResource.set(switch (status) {
        PurchaseStatus.purchased when activeSubscription.isPurchased =>
          SubscriptionStatus.subscribed,
        PurchaseStatus.purchased => SubscriptionStatus.free,
        PurchaseStatus.pendingVerification =>
          SubscriptionStatus.pendingPaymentConfirmation,
        PurchaseStatus.canceled => SubscriptionStatus.free,
        PurchaseStatus.error => SubscriptionStatus.free,
      });
    }

    if (subscriptionStatusResource.status != SubscriptionStatus.subscribed) {
      await purchasesLocalApi.clearActiveSubscription();
    }
  }
}
