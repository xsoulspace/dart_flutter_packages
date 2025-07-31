import 'package:from_json_to_json/from_json_to_json.dart';

import '../rustore_api.g.dart';

/// The type of the billing result
enum RustoreBillingResultType { payment, error }

/// {@template rustore_billing_result}
/// Extension type that represents the result of RuStore billing operations.
///
/// This type unifies both successful payment results and errors into a single
/// type that can be used in a unified stream for billing events.
///
/// Uses from_json_to_json for type-safe JSON handling.
///
/// Provides functionality to handle both payment results and errors
/// with pattern matching capabilities.
/// {@endtemplate}
extension type const RustoreBillingResult(Map<String, dynamic> value) {
  /// {@macro rustore_billing_result}
  factory RustoreBillingResult.fromJson(final dynamic json) {
    final map = jsonDecodeMap(json);
    return RustoreBillingResult(map);
  }

  /// Creates a [RustoreBillingResult] from a [RustorePaymentResult]
  factory RustoreBillingResult.payment(final RustorePaymentResult result) =>
      RustoreBillingResult({
        'type': RustoreBillingResultType.payment.name,
        'data': {
          'resultType': result.resultType.name,
          'productId': result.productId,
          'orderId': result.orderId,
          'subscriptionToken': result.subscriptionToken,
          'invoiceId': result.invoiceId,
          'sandbox': result.sandbox,
          'purchaseId': result.purchaseId,
          'errorCode': result.errorCode,
          'errorMessage': result.errorMessage,
        },
      });

  /// Creates a [RustoreBillingResult] from a [RustoreError]
  factory RustoreBillingResult.error(final RustoreError error) =>
      RustoreBillingResult({
        'type': RustoreBillingResultType.error.name,
        'data': {
          'code': error.code,
          'message': error.message,
          'description': error.description,
        },
      });

  /// Returns the type of this result
  RustoreBillingResultType get type =>
      RustoreBillingResultType.values.firstWhere(
        (final e) => e.name == jsonDecodeString(value['type']),
        orElse: () => RustoreBillingResultType.payment,
      );

  /// Returns true if this result represents a payment result
  bool get isPayment => type == RustoreBillingResultType.payment;

  /// Returns true if this result represents an error
  bool get isError => type == RustoreBillingResultType.error;

  /// Returns the payment result if this is a payment result, null otherwise
  RustorePaymentResult? get paymentResult {
    if (!isPayment) return null;
    final data = jsonDecodeMap(value['data']);
    return RustorePaymentResult(
      resultType: RustorePaymentResultType.values.firstWhere(
        (final e) => e.name == jsonDecodeString(data['resultType']),
        orElse: () => RustorePaymentResultType.failure,
      ),
      productId: jsonDecodeString(data['productId']),
      orderId: jsonDecodeString(data['orderId']),
      subscriptionToken: jsonDecodeString(data['subscriptionToken']),
      invoiceId: jsonDecodeString(data['invoiceId']),
      sandbox: jsonDecodeBool(data['sandbox']),
      purchaseId: jsonDecodeString(data['purchaseId']),
      errorCode: jsonDecodeString(data['errorCode']),
      errorMessage: jsonDecodeString(data['errorMessage']),
    );
  }

  /// Returns the error if this is an error result, null otherwise
  RustoreError? get error {
    if (!isError) return null;
    final data = jsonDecodeMap(value['data']);
    return RustoreError(
      code: jsonDecodeString(data['code']),
      message: jsonDecodeString(data['message']),
      description: jsonDecodeString(data['description']),
    );
  }

  /// Convert to JSON for serialization
  Map<String, dynamic> toJson() => value;

  /// Empty result for initialization
  static final empty = RustoreBillingResult({
    'type': RustoreBillingResultType.payment.name,
    'data': {
      'resultType': RustorePaymentResultType.failure.name,
      'productId': null,
      'orderId': null,
      'subscriptionToken': null,
      'invoiceId': null,
      'sandbox': null,
      'purchaseId': null,
      'errorCode': null,
      'errorMessage': null,
    },
  });
}
