import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_monetization_foundation/xsoulspace_monetization_foundation.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import 'support/fakes.dart';

void main() {
  group('LoadSubscriptionsCommand', () {
    test('loads subscriptions into resource', () async {
      final available = AvailableSubscriptionsResource();
      final provider = FakeProvider(
        subscriptions: [
          PurchaseProductDetailsModel(
            productId: PurchaseProductId.fromJson('prod'),
            priceId: PurchasePriceId.fromJson('price'),
            productType: PurchaseProductType.subscription,
            name: 'Premium',
            price: 1,
            currency: 'USD',
            duration: const Duration(days: 30),
            freeTrialDuration: PurchaseDurationModel.zero,
          ),
        ],
      );
      final cmd = LoadSubscriptionsCommand(
        purchaseProvider: provider,
        monetizationStatusResource: MonetizationStoreStatusResource(),
        availableSubscriptionsResource: available,
        productIds: [PurchaseProductId.fromJson('prod')],
      );
      await cmd.execute();
      expect(available.subscriptions.isLoaded, isTrue);
      expect(
        available.getSubscription(PurchaseProductId.fromJson('prod'))?.name,
        'Premium',
      );
    });
  });
}
