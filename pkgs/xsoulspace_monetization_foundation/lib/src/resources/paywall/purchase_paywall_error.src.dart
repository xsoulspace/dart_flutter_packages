import 'package:flutter/widgets.dart';

/// {@template purchase_paywall_error_resource}
/// Resource for managing purchase paywall error state during
/// purchase process.
///
/// This resource purpose to show error to user,
/// therefore there should be only one, readable, latest error at a time.
/// {@endtemplate}
class PurchasePaywallErrorResource extends ChangeNotifier {
  /// {@macro purchase_paywall_error_resource}
  PurchasePaywallErrorResource();

  var _error = '';

  String get error => _error;

  bool get hasError => _error.isNotEmpty;

  set error(final String value) {
    _error = value;
    notifyListeners();
  }

  void clear() {
    _error = '';
    notifyListeners();
  }
}
