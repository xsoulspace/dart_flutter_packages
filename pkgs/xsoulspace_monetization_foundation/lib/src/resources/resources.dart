import 'active_subscription.src.dart';
import 'available_subscriptions.src.dart';
import 'monetization_status.src.dart';
import 'monetization_type.src.dart';
import 'subscription_status.src.dart';

export 'active_subscription.src.dart';
export 'available_subscriptions.src.dart';
export 'monetization_status.src.dart';
export 'monetization_type.src.dart';
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
  MonetizationStatusResource status,
  MonetizationTypeResource type,
  ActiveSubscriptionResource activeSubscription,
  SubscriptionStatusResource subscriptionStatus,
  AvailableSubscriptionsResource availableSubscriptions,
});
