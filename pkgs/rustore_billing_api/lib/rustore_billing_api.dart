/// {@template rustore_billing_api}
/// Flutter plugin for RuStore billing integration.
///
/// Provides a comprehensive API for integrating RuStore billing functionality
/// into Flutter applications, including product management, purchase flows,
/// and payment confirmation.
///
/// ## Usage
///
/// ```dart
/// import 'package:rustore_billing_api/rustore_billing_api.dart';
///
/// // Initialize the billing client
/// final client = RustoreBillingClient.instance;
/// await client.initialize(RustoreBillingConfig(
///   consoleApplicationId: 'your_app_id',
///   deeplinkScheme: 'your_scheme',
///   debugLogs: true,
/// ));
///
/// // Get available products
/// final products = await client.getProducts(['product1', 'product2']);
///
/// // Purchase a product
/// final result = await client.purchaseProduct('product1');
/// if (result.resultType == RustorePaymentResultType.success) {
///   await client.confirmPurchase(result.purchaseId!);
/// }
///
/// // Listen to unified billing results
/// client.billingResults.listen((result) {
///   result.when(
///     payment: (paymentResult) => print('Payment: ${paymentResult.resultType}'),
///     error: (error) => print('Error: ${error.message}'),
///   );
/// });
/// ```
/// {@endtemplate}
library;

export 'src/android/rustore_billing_android.dart';
// Export the unified billing result model
export 'src/models/rustore_billing_result.dart';
// Export the generated pigeon models and APIs
export 'src/rustore_api.g.dart'
    show
        RustoreBillingConfig,
        RustoreBillingTheme,
        RustoreError,
        RustoreException,
        RustoreExceptionType,
        RustorePaymentResult,
        RustorePaymentResultType,
        RustoreProduct,
        RustoreProductSubscription,
        RustoreProductType,
        RustorePurchase,
        RustorePurchaseAvailabilityResult,
        RustorePurchaseAvailabilityType,
        RustorePurchaseState,
        RustoreSubscriptionPeriod;
// Export the main client
export 'src/rustore_billing_client.dart';
// Export the platform interface
export 'src/rustore_billing_platform.dart';
