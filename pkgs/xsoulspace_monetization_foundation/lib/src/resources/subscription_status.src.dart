import 'package:flutter/foundation.dart';

/// Represents the state of user access to premium features.
enum SubscriptionStatus {
  free,

  /// if user restoring subscription, then
  /// user should not be allowed to purchase new subscription
  restoring,

  /// if user purchasing subscription, then
  /// user should not be allowed to purchase new subscription
  purchasing,
  pendingPaymentConfirmation,
  subscribed,
  cancelling,
}

/// Resource that manages the status of the subscription.
class SubscriptionStatusResource extends ChangeNotifier {
  SubscriptionStatusResource();

  SubscriptionStatus _value = SubscriptionStatus.free;
  SubscriptionStatus get status => _value;

  void set(final SubscriptionStatus status) {
    _value = status;
    notifyListeners();
  }

  bool get isFree => status == SubscriptionStatus.free;
  bool get isRestoring => status == SubscriptionStatus.restoring;
  bool get isPurchasing => status == SubscriptionStatus.purchasing;
  bool get isPendingConfirmation =>
      status == SubscriptionStatus.pendingPaymentConfirmation;
  bool get isSubscribed => status == SubscriptionStatus.subscribed;
  bool get isCancelling => status == SubscriptionStatus.cancelling;
}
