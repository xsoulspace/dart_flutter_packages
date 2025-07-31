import 'package:flutter/foundation.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

/// {@template subscription_plans_resource}
/// Resource for managing subscription plans state including loading,
/// error handling,
/// and product selection
/// {@endtemplate}
class PaywallSelectedSubscriptionResource extends ChangeNotifier {
  /// {@macro subscription_plans_resource}
  PaywallSelectedSubscriptionResource({
    final PurchaseProductId selectedProductId = PurchaseProductId.empty,
    final PurchaseProductDetailsModel? selectedProductDetails,
  }) : _selectedProductId = selectedProductId,
       _selectedProductDetails = selectedProductDetails;

  PurchaseProductId _selectedProductId;
  PurchaseProductDetailsModel? _selectedProductDetails;

  PurchaseProductId get selectedProductId => _selectedProductId;
  PurchaseProductDetailsModel? get selectedProductDetails =>
      _selectedProductDetails;
  bool get isLoading => !isLoaded;
  bool get isLoaded =>
      selectedProductId.isNotEmpty && selectedProductDetails != null;

  void setSelectedProductId({
    required final PurchaseProductId selectedProductId,
    required final PurchaseProductDetailsModel selectedProductDetails,
  }) {
    _selectedProductId = selectedProductId;
    _selectedProductDetails = selectedProductDetails;
    notifyListeners();
  }

  void clear() {
    _selectedProductId = PurchaseProductId.empty;
    _selectedProductDetails = null;
    notifyListeners();
  }
}
