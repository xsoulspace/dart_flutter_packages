import 'package:flutter/widgets.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

class ActiveSubscriptionResource extends ChangeNotifier {
  ActiveSubscriptionResource([this._value]);
  PurchaseDetailsModel? _value;
  PurchaseDetailsModel? get subscription => _value;

  void set(final PurchaseDetailsModel? value) {
    _value = value;
    notifyListeners();
  }
}
