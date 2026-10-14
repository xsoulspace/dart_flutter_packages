import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_monetization_foundation/xsoulspace_monetization_foundation.dart';

Matcher isSubscribed() => predicate<SubscriptionStatusResource>(
  (s) => s.isSubscribed,
  'SubscriptionStatusResource.isSubscribed == true',
);

Matcher isPendingConfirmationStatus() => predicate<SubscriptionStatusResource>(
  (s) => s.isPendingConfirmation,
  'SubscriptionStatusResource.isPendingConfirmation == true',
);

Matcher isPurchasingStatus() => predicate<SubscriptionStatusResource>(
  (s) => s.isPurchasing,
  'SubscriptionStatusResource.isPurchasing == true',
);

Matcher isFreeStatus() => predicate<SubscriptionStatusResource>(
  (s) => s.isFree,
  'SubscriptionStatusResource.isFree == true',
);

Matcher hasNoError() => predicate<PurchasePaywallErrorResource>(
  (e) => e.hasError == false,
  'PurchasePaywallErrorResource.hasError == false',
);

Matcher hasError([
  String? contains,
]) => predicate<PurchasePaywallErrorResource>(
  (e) => e.hasError && (contains == null || e.error.contains(contains)),
  contains == null
      ? 'PurchasePaywallErrorResource.hasError == true'
      : 'PurchasePaywallErrorResource.hasError == true and contains "$contains"',
);
