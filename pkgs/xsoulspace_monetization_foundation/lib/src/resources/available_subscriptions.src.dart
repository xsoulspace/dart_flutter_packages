import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:xsoulspace_foundation/xsoulspace_foundation.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

class AvailableSubscriptionsResource extends ChangeNotifier {
  LoadableContainer<List<PurchaseProductDetailsModel>> _value =
      const LoadableContainer(value: []);
  LoadableContainer<List<PurchaseProductDetailsModel>> get subscriptions =>
      _value;
  void set(final LoadableContainer<List<PurchaseProductDetailsModel>> value) {
    _value = value;
    notifyListeners();
  }

  PurchaseProductDetailsModel? getSubscription(final PurchaseProductId id) =>
      _value.value.firstWhereOrNull((final e) => e.productId == id);
}
