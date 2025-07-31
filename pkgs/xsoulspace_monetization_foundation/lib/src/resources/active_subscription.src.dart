import 'package:flutter/widgets.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

class ActiveSubscriptionResource extends ChangeNotifier {
  ActiveSubscriptionResource([final PurchaseDetailsModel? details])
    : _value = details ?? PurchaseDetailsModel.empty;
  PurchaseDetailsModel _value;
  PurchaseDetailsModel get subscription => _value;
  bool get isActive => _value.isActive;
  bool get isNotActive => !isActive;
  bool get isPending => _value.isPending;
  bool get isCancelled => _value.isCancelled;

  void set(final PurchaseDetailsModel value) {
    _value = value;
    notifyListeners();
  }
}
