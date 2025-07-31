import 'active_subscription.src.dart';
import 'available_subscriptions.src.dart';
import 'monetization_store_status.src.dart';
import 'monetization_type.src.dart';
import 'paywall/paywall_selected_subscription.src.dart';
import 'paywall/purchase_paywall_error.src.dart';
import 'subscription_status.src.dart';

export 'active_subscription.src.dart';
export 'available_subscriptions.src.dart';
export 'monetization_store_status.src.dart';
export 'monetization_type.src.dart';
export 'paywall/paywall_selected_subscription.src.dart';
export 'paywall/purchase_paywall_error.src.dart';
export 'subscription_status.src.dart';

/// {@template monetization_resources}
/// A tuple of resources that manage the state of the monetization system.
///
/// This tuple contains:
/// - [status]: The overall status of the monetization system.
/// - [type]: The type of monetization system.
/// - [activeSubscription]: The active subscription details.
/// - [subscriptionStatus]: The status of the subscription.
/// - [availableSubscriptions]: The available subscriptions.
/// {@endtemplate}
typedef MonetizationResources = ({
  MonetizationStoreStatusResource status,
  MonetizationTypeResource type,
  ActiveSubscriptionResource activeSubscription,
  SubscriptionStatusResource subscriptionStatus,
  AvailableSubscriptionsResource availableSubscriptions,
  PaywallSelectedSubscriptionResource paywallSelectedSubscription,
  PurchasePaywallErrorResource purchasePaywallError,
});
