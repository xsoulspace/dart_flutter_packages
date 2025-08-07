import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

/// Purchase details builder
PurchaseDetailsModel aPurchase({
  final bool active = false,
  final bool pending = false,
  final bool pendingConfirmation = false,
  final bool cancelled = false,
  final PurchaseProductType type = PurchaseProductType.subscription,
}) {
  final status = pending
      ? PurchaseStatus.pending
      : pendingConfirmation
      ? PurchaseStatus.pendingConfirmation
      : cancelled
      ? PurchaseStatus.canceled
      : PurchaseStatus.purchased;
  return PurchaseDetailsModel(
    purchaseDate: DateTime.now(),
    status: status,
    purchaseType: type,
    expiryDate: active ? DateTime.now().add(const Duration(days: 30)) : null,
  );
}

/// Product details builder
PurchaseProductDetailsModel aProduct({
  final PurchaseProductId? id,
  final PurchasePriceId? priceId,
  final String name = 'Product',
  final double price = 1,
  final String currency = 'USD',
  final Duration duration = const Duration(days: 30),
  final PurchaseDurationModel? freeTrial,
  final PurchaseProductType type = PurchaseProductType.subscription,
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
  final PurchaseStatus status = PurchaseStatus.purchased,
  final DateTime? date,
}) => PurchaseVerificationDtoModel(
  transactionDate: date ?? DateTime.now(),
  status: status,
);
