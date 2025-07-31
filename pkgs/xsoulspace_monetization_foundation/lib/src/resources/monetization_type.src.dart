import 'package:flutter/foundation.dart';
import 'package:xsoulspace_foundation/xsoulspace_foundation.dart';

import '../models/models.dart';

/// Resource that manages the status  of the monetization system.
@stateDistributor
class MonetizationTypeResource extends ChangeNotifier {
  MonetizationTypeResource(this._type);
  MonetizationType _type;
  MonetizationType get type => _type;
  void setType(final MonetizationType value) {
    _type = value;
    notifyListeners();
  }
}
