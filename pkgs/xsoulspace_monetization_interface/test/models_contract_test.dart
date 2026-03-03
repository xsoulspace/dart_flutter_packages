import 'package:test/test.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

void main() {
  group('PurchaseDurationModel', () {
    test('converts years/months/days into duration', () {
      final duration = PurchaseDurationModel(years: 1, months: 2, days: 3);

      expect(duration.isZero, isFalse);
      expect(duration.duration.inDays, 365 + 60 + 3);
      expect(PurchaseDurationModel.zero.isZero, isTrue);
    });
  });

  group('PurchaseProductDetailsModel', () {
    test('supports json roundtrip and free-trial checks', () {
      final details = PurchaseProductDetailsModel(
        productId: PurchaseProductId.fromJson('premium_month'),
        priceId: PurchasePriceId.fromJson('premium_month_price'),
        productType: PurchaseProductType.subscription,
        name: 'Premium Monthly',
        formattedPrice: '49.99',
        price: 49.99,
        currency: 'USD',
        description: 'Monthly subscription',
        duration: const Duration(days: 30),
        freeTrialDuration: PurchaseDurationModel(days: 7),
      );

      final decoded = PurchaseProductDetailsModel.fromJson(details.toJson());

      expect(decoded.productId.value, 'premium_month');
      expect(decoded.productType, PurchaseProductType.subscription);
      expect(decoded.hasFreeTrial, isTrue);
      expect(decoded.isSubscription, isTrue);
    });
  });

  group('Result models', () {
    test('purchase and restore results map failure states', () {
      final purchaseFailure = PurchaseResultModel.failure('store_error');
      final restoreFailure = RestoreResultModel.failure('network_error');

      expect(purchaseFailure.isSuccess, isFalse);
      expect(purchaseFailure.error, 'store_error');
      expect(restoreFailure.isSuccess, isFalse);
      expect(restoreFailure.error, 'network_error');
    });

    test('status decode falls back to pending verification on unknown value', () {
      final details = PurchaseDetailsModel.fromJson(<String, dynamic>{
        'purchaseId': 'id',
        'productId': 'product',
        'priceId': 'price',
        'status': 'unknown_status',
        'purchaseType': 'subscription',
        'purchaseDate': DateTime.utc(2026, 1, 1).toIso8601String(),
        'duration': 0,
        'freeTrialDuration': 0,
      });

      expect(details.status, PurchaseStatus.pendingVerification);
    });
  });
}
