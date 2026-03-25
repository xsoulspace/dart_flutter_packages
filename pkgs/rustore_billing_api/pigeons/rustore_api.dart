import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/rustore_api.g.dart',
    kotlinOut:
        'android/src/main/kotlin/dev/xsoulspace/rustore_billing_api/RustoreApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'dev.xsoulspace.rustore_billing_api'),
  ),
)
@HostApi()
abstract class RustoreBillingApi {
  @async
  void initialize(final RustoreBillingConfig config);

  @async
  RustorePurchaseAvailabilityResult getPurchaseAvailability();

  @async
  bool getUserAuthorizationStatus();

  @async
  List<RustoreProduct> getProducts(final List<String> productIds);

  @async
  List<RustorePurchase> getPurchases(final RustorePurchaseFilter? filter);

  @async
  RustorePurchase? getPurchase(final String purchaseId);

  @async
  RustoreProductPurchaseResult purchase(
    final RustoreProductPurchaseParams params,
    final RustorePreferredPurchaseType preferredPurchaseType,
    final RustoreBillingTheme sdkTheme,
  );

  @async
  RustoreProductPurchaseResult purchaseTwoStep(
    final RustoreProductPurchaseParams params,
    final RustoreBillingTheme sdkTheme,
  );

  @async
  void confirmTwoStepPurchase(
    final String purchaseId,
    final String? developerPayload,
  );

  @async
  void cancelTwoStepPurchase(final String purchaseId);
}

@FlutterApi()
abstract class RustoreBillingCallbackApi {
  void onPurchaseResult(final RustoreProductPurchaseResult result);

  void onPurchaseError(final RustorePurchaseError error);
}

class RustoreBillingConfig {
  const RustoreBillingConfig({
    required this.consoleApplicationId,
    required this.deeplinkScheme,
    this.debugLogs = false,
    this.defaultTheme = RustoreBillingTheme.system,
    this.enableLogging = false,
  });

  final String consoleApplicationId;
  final String deeplinkScheme;
  final bool debugLogs;
  final RustoreBillingTheme defaultTheme;
  final bool enableLogging;
}

enum RustoreBillingTheme { light, dark, system, unknown }

class RustorePurchaseAvailabilityResult {
  const RustorePurchaseAvailabilityResult({
    required this.status,
    this.cause,
  });

  final RustorePurchaseAvailabilityStatus status;
  final RustoreException? cause;
}

enum RustorePurchaseAvailabilityStatus { available, unavailable, unknown }

class RustoreProduct {
  const RustoreProduct({
    required this.productId,
    required this.productType,
    required this.productStatus,
    this.title,
    this.description,
    this.price,
    this.priceLabel,
    this.currency,
    this.language,
    this.subscriptionInfo,
  });

  final String productId;
  final RustoreProductType productType;
  final RustoreProductStatus productStatus;
  final String? title;
  final String? description;
  final int? price;
  final String? priceLabel;
  final String? currency;
  final String? language;
  final RustoreProductSubscriptionInfo? subscriptionInfo;
}

enum RustoreProductStatus { active, inactive, unknown }

enum RustoreProductType { consumable, nonConsumable, subscription, unknown }

class RustoreProductSubscriptionInfo {
  const RustoreProductSubscriptionInfo({required this.periods});

  final List<RustoreProductSubscriptionPeriod> periods;
}

class RustoreProductSubscriptionPeriod {
  const RustoreProductSubscriptionPeriod({
    required this.type,
    required this.durationIso,
    this.price,
    this.priceLabel,
    this.currency,
  });

  final RustoreSubscriptionPeriodType type;
  final String durationIso;
  final int? price;
  final String? priceLabel;
  final String? currency;
}

enum RustoreSubscriptionPeriodType { trial, intro, main, grace, hold, unknown }

class RustorePurchase {
  const RustorePurchase({
    required this.purchaseId,
    required this.purchaseType,
    required this.productType,
    required this.purchaseStatus,
    this.productId,
    this.invoiceId,
    this.orderId,
    this.amountLabel,
    this.amount,
    this.currency,
    this.quantity,
    this.purchaseTime,
    this.developerPayload,
    this.subscriptionToken,
    this.sandbox,
  });

  final String purchaseId;
  final RustorePurchaseType purchaseType;
  final RustoreProductType productType;
  final RustorePurchaseStatus purchaseStatus;
  final String? productId;
  final String? invoiceId;
  final String? orderId;
  final String? amountLabel;
  final int? amount;
  final String? currency;
  final int? quantity;
  final String? purchaseTime;
  final String? developerPayload;
  final String? subscriptionToken;
  final bool? sandbox;
}

enum RustorePurchaseType { oneStep, twoStep, undefined, unknown }

enum RustorePurchaseStatus {
  created,
  invoiceCreated,
  paid,
  confirmed,
  cancelled,
  reversed,
  consumed,
  closed,
  active,
  paused,
  terminated,
  unknown,
}

class RustorePurchaseFilter {
  const RustorePurchaseFilter({
    this.productId,
    this.productType,
    this.purchaseStatus,
    this.purchaseType,
  });

  final String? productId;
  final RustoreProductType? productType;
  final RustorePurchaseStatus? purchaseStatus;
  final RustorePurchaseType? purchaseType;
}

enum RustorePreferredPurchaseType { oneStep, twoStep, unknown }

class RustoreProductPurchaseParams {
  const RustoreProductPurchaseParams({
    required this.productId,
    this.quantity,
    this.orderId,
    this.developerPayload,
    this.appUserId,
    this.appUserEmail,
  });

  final String productId;
  final int? quantity;
  final String? orderId;
  final String? developerPayload;
  final String? appUserId;
  final String? appUserEmail;
}

class RustoreProductPurchaseResult {
  const RustoreProductPurchaseResult({
    required this.resultType,
    this.purchase,
    this.error,
  });

  final RustoreProductPurchaseResultType resultType;
  final RustorePurchase? purchase;
  final RustorePurchaseError? error;
}

enum RustoreProductPurchaseResultType { success, cancelled, failure, unknown }

class RustorePurchaseError {
  const RustorePurchaseError({
    required this.code,
    required this.message,
    this.description,
    this.purchase,
  });

  final String code;
  final String message;
  final String? description;
  final RustorePurchase? purchase;
}

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
  general,
  unknown,
}
