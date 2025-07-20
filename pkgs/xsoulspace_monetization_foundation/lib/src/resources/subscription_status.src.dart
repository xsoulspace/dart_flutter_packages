import 'package:flutter/foundation.dart';

/// Represents the state of user access to premium features.
enum SubscriptionStatus { free, subscribed, pending }

/// Resource that manages the status of the subscription.
class SubscriptionStatusResource extends ChangeNotifier {
  SubscriptionStatusResource();

  SubscriptionStatus _value = SubscriptionStatus.free;
  SubscriptionStatus get status => _value;

  void set(final SubscriptionStatus status) {
    _value = status;
    notifyListeners();
  }

  bool get isLoading => status == SubscriptionStatus.pending;
  bool get isSubscribed => status == SubscriptionStatus.subscribed;
}
