/// {@template noop_providers}
/// No-operation provider implementations for testing and development.
///
/// These providers implement the same interfaces as real providers but
/// perform no actual operations. They're useful for:
///
/// - **Testing**: Unit tests without real transactions
/// - **Development**: Development builds without store integration
/// - **Demo**: Demonstrations without requiring real accounts
/// - **CI/CD**: Automated testing without store credentials
///
/// ## Usage
/// ```dart
/// // For testing
/// final testProvider = NoopPurchaseProvider();
/// final testAdProvider = NoopAdProvider();
///
/// // Use in your app for development
/// final purchaseProvider = kDebugMode
///   ? NoopPurchaseProvider()
///   : RealPurchaseProvider();
/// ```
/// {@endtemplate}
library;

export 'noop_ad_provider.dart';
export 'noop_purchase_provider.dart';
