import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/rustore_api.g.dart',
    kotlinOut:
        'android/src/main/kotlin/com/xsoulspace/rustore_billing_api/RustoreApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.xsoulspace.rustore_billing_api'),
  ),
)
// Data Models
@HostApi()
abstract class RustoreBillingApi {
  /// Initialize the RuStore billing client
  @async
  void initialize(final RustoreBillingConfig config);

  /// Handle deep link intent (for payment flows)
  void onNewIntent(final String? intentData);

  /// Check if purchases are available on this device
  @async
  RustorePurchaseAvailabilityResult checkPurchasesAvailability();

  /// Check if RuStore is installed on the device
  @async
  bool isRuStoreInstalled();

  /// Get available products by IDs
  @async
  List<RustoreProduct> getProducts(final List<String> productIds);

  /// Get existing purchases
  @async
  List<RustorePurchase> getPurchases();

  /// Start purchase flow for a product
  @async
  RustorePaymentResult purchaseProduct(
    final String productId,
    final String? developerPayload,
  );

  /// Confirm a successful purchase
  @async
  void confirmPurchase(final String purchaseId, final String? developerPayload);

  /// Delete a purchase
  @async
  void deletePurchase(final String purchaseId);

  /// Set the billing client theme
  @async
  void setTheme(final RustoreBillingTheme theme);
}

@FlutterApi()
abstract class RustoreBillingCallbackApi {
  /// Called when purchase state changes
  void onPurchaseResult(final RustorePaymentResult result);

  /// Called when an error occurs
  void onError(final RustoreError error);
}

// Configuration
class RustoreBillingConfig {
  const RustoreBillingConfig({
    required this.consoleApplicationId,
    required this.deeplinkScheme,
    this.debugLogs = false,
    this.theme = RustoreBillingTheme.light,
    this.enableLogging = false,
  });

  final String consoleApplicationId;
  final String deeplinkScheme;
  final bool debugLogs;
  final RustoreBillingTheme theme;
  final bool enableLogging;
}

// Billing theme enum
enum RustoreBillingTheme { light, dark }

// Purchase availability result
class RustorePurchaseAvailabilityResult {
  const RustorePurchaseAvailabilityResult({
    required this.resultType,
    this.cause,
  });

  final RustorePurchaseAvailabilityType resultType;
  final RustoreException? cause;
}

enum RustorePurchaseAvailabilityType { available, unavailable, unknown }

// Product model
class RustoreProduct {
  const RustoreProduct({
    required this.productId,
    required this.productType,
    this.title,
    this.description,
    this.price,
    this.priceLabel,
    this.currency,
    this.language,
    this.subscription,
  });

  final String productId;
  final RustoreProductType productType;
  final String? title;
  final String? description;
  final int? price;
  final String? priceLabel;
  final String? currency;
  final String? language;
  final RustoreProductSubscription? subscription;
}

enum RustoreProductType { nonConsumable, consumable, subscription }

// Subscription period model
class RustoreSubscriptionPeriod {
  const RustoreSubscriptionPeriod({
    required this.years,
    required this.months,
    required this.days,
  });

  final int years;
  final int months;
  final int days;
}

// Product subscription model
class RustoreProductSubscription {
  const RustoreProductSubscription({
    this.subscriptionPeriod,
    this.freeTrialPeriod,
    this.gracePeriod,
    this.introductoryPrice,
    this.introductoryPriceAmount,
    this.introductoryPricePeriod,
  });

  final RustoreSubscriptionPeriod? subscriptionPeriod;
  final RustoreSubscriptionPeriod? freeTrialPeriod;
  final RustoreSubscriptionPeriod? gracePeriod;
  final String? introductoryPrice;
  final String? introductoryPriceAmount;
  final RustoreSubscriptionPeriod? introductoryPricePeriod;
}

// Purchase model
class RustorePurchase {
  const RustorePurchase({
    this.purchaseId,
    this.productId,
    this.productType,
    this.invoiceId,
    this.description,
    this.language,
    this.purchaseTime,
    this.orderId,
    this.amountLabel,
    this.amount,
    this.currency,
    this.quantity,
    this.purchaseState,
    this.developerPayload,
  });

  final String? purchaseId;
  final String? productId;
  final RustoreProductType? productType;
  final String? invoiceId;
  final String? description;
  final String? language;
  final String? purchaseTime;
  final String? orderId;
  final String? amountLabel;
  final int? amount;
  final String? currency;
  final int? quantity;
  final RustorePurchaseState? purchaseState;
  final String? developerPayload;
}

// Purchase state enum
enum RustorePurchaseState {
  created,
  invoice_created,
  confirmed,
  paid,
  cancelled,
  consumed,
  closed,
  paused,
  terminated,
}

// Payment result
class RustorePaymentResult {
  const RustorePaymentResult({
    required this.resultType,
    this.purchaseId,
    this.errorCode,
    this.errorMessage,
  });

  final RustorePaymentResultType resultType;
  final String? purchaseId;
  final String? errorCode;
  final String? errorMessage;
}

enum RustorePaymentResultType {
  success,
  cancelled,
  failure,
  invalid_payment_state,
}

// Error model
class RustoreError {
  const RustoreError({
    required this.code,
    required this.message,
    this.description,
  });

  final String code;
  final String message;
  final String? description;
}

// RuStore exception types
class RustoreException {
  const RustoreException({
    required this.type,
    required this.message,
    this.errorCode,
  });

  final RustoreExceptionType type;
  final String message;
  final String? errorCode;
}

enum RustoreExceptionType {
  notInstalled,
  outdated,
  userUnauthorized,
  requestLimitReached,
  reviewExists,
  invalidReviewInfo,
  general,
}
