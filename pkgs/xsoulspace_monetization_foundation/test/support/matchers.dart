import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_monetization_foundation/xsoulspace_monetization_foundation.dart';

Matcher isSubscribed() => predicate<SubscriptionStatusResource>(
  (final s) => s.isSubscribed,
  'SubscriptionStatusResource.isSubscribed == true',
);

Matcher isPendingConfirmationStatus() => predicate<SubscriptionStatusResource>(
  (final s) => s.isPendingConfirmation,
  'SubscriptionStatusResource.isPendingConfirmation == true',
);

Matcher isPurchasingStatus() => predicate<SubscriptionStatusResource>(
  (final s) => s.isPurchasing,
  'SubscriptionStatusResource.isPurchasing == true',
);

Matcher isFreeStatus() => predicate<SubscriptionStatusResource>(
  (final s) => s.isFree,
  'SubscriptionStatusResource.isFree == true',
);

Matcher hasNoError() => predicate<PurchasePaywallErrorResource>(
  (final e) => e.hasError == false,
  'PurchasePaywallErrorResource.hasError == false',
);

Matcher hasError([
  final String? contains,
]) => predicate<PurchasePaywallErrorResource>(
  (final e) => e.hasError && (contains == null || e.error.contains(contains)),
  contains == null
      ? 'PurchasePaywallErrorResource.hasError == true'
      : 'PurchasePaywallErrorResource.hasError == true and contains "$contains"',
);
