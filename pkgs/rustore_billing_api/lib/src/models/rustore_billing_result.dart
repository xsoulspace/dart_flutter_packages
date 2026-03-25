import 'package:from_json_to_json/from_json_to_json.dart';

import '../rustore_api.g.dart';

enum RustoreBillingResultType { purchase, error }

extension type const RustoreBillingResult(Map<String, dynamic> value) {
  factory RustoreBillingResult.fromJson(final dynamic json) =>
      RustoreBillingResult(jsonDecodeMap(json));

  factory RustoreBillingResult.purchase(
    final RustoreProductPurchaseResult result,
  ) => RustoreBillingResult({
    'type': RustoreBillingResultType.purchase.name,
    'data': result,
  });

  factory RustoreBillingResult.error(final RustorePurchaseError error) =>
      RustoreBillingResult({
        'type': RustoreBillingResultType.error.name,
        'data': error,
      });

  RustoreBillingResultType get type {
    final rawType = jsonDecodeString(value['type']);
    return RustoreBillingResultType.values.firstWhere(
      (final e) => e.name == rawType,
      orElse: () => RustoreBillingResultType.error,
    );
  }

  bool get isPurchase => type == RustoreBillingResultType.purchase;

  bool get isError => type == RustoreBillingResultType.error;

  RustoreProductPurchaseResult? get purchaseResult {
    if (!isPurchase) {
      return null;
    }
    final data = value['data'];
    if (data is RustoreProductPurchaseResult) {
      return data;
    }
    if (data is List<Object?>) {
      return RustoreProductPurchaseResult.decode(data);
    }
    return null;
  }

  RustorePurchaseError? get error {
    if (!isError) {
      return null;
    }
    final data = value['data'];
    if (data is RustorePurchaseError) {
      return data;
    }
    if (data is List<Object?>) {
      return RustorePurchaseError.decode(data);
    }
    return null;
  }

  Map<String, dynamic> toJson() => value;

  static final RustoreBillingResult empty = RustoreBillingResult.error(
    RustorePurchaseError(code: 'EMPTY', message: 'No billing result'),
  );
}
