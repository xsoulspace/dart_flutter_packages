import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

/// Purchase details builder
PurchaseDetailsModel aPurchase({
  bool active = false,
  bool pendingConfirmation = false,
  bool cancelled = false,
  PurchaseProductType type = PurchaseProductType.subscription,
}) {
  final status = pendingConfirmation
      ? PurchaseStatus.pendingVerification
      : cancelled
      ? PurchaseStatus.canceled
      : PurchaseStatus.purchased;
  return PurchaseDetailsModel(
    purchaseDate: DateTime.now(),
    status: status,
    purchaseType: type,
    duration: type == PurchaseProductType.subscription
        ? const Duration(days: 30)
        : Duration.zero,
    expiryDate: active ? DateTime.now().add(const Duration(days: 30)) : null,
  );
}

/// Product details builder
PurchaseProductDetailsModel aProduct({
  PurchaseProductId? id,
  PurchasePriceId? priceId,
  String name = 'Product',
  double price = 1,
  String currency = 'USD',
  Duration duration = const Duration(days: 30),
  PurchaseDurationModel? freeTrial,
  PurchaseProductType type = PurchaseProductType.subscription,
}) => PurchaseProductDetailsModel(
  productId: id ?? PurchaseProductId.fromJson('prod'),
  priceId: priceId ?? PurchasePriceId.fromJson('price'),
  productType: type,
  name: name,
  price: price,
  currency: currency,
  duration: duration,
  freeTrialDuration: freeTrial ?? PurchaseDurationModel.zero,
);

/// Verification dto builder
PurchaseVerificationDtoModel aVerification({
  PurchaseStatus status = PurchaseStatus.purchased,
  DateTime? date,
}) => PurchaseVerificationDtoModel(
  transactionDate: date ?? DateTime.now(),
  status: status,
);
