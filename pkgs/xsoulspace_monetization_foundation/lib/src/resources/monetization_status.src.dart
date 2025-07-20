import 'package:flutter/foundation.dart';
import 'package:xsoulspace_foundation/xsoulspace_foundation.dart';

import '../models/models.dart';

/// Resource that manages the status  of the monetization system.
@stateDistributor
class MonetizationStatusResource extends ChangeNotifier {
  MonetizationStatusResource();

  MonetizationStatus _status = MonetizationStatus.loading;
  bool get isInitialized => _status == MonetizationStatus.loaded;
  MonetizationStatus get status => _status;
  void setStatus(final MonetizationStatus value) {
    _status = value;
    notifyListeners();
  }
}
