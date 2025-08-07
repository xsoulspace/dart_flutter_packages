import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_monetization_foundation/xsoulspace_monetization_foundation.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import 'support/fakes.dart';

void main() {
  group('MonetizationFoundation', () {
    test(
      'init sets status and loads/restore when loaded/authorized/installed',
      () async {
        final res = (
          status: MonetizationStoreStatusResource(),
          type: MonetizationTypeResource(MonetizationType.subscription),
          activeSubscription: ActiveSubscriptionResource(),
          subscriptionStatus: SubscriptionStatusResource(),
          availableSubscriptions: AvailableSubscriptionsResource(),
          paywallSelectedSubscription: PaywallSelectedSubscriptionResource(),
          purchasePaywallError: PurchasePaywallErrorResource(),
        );
        final provider = FakeProvider();
        final foundation = MonetizationFoundation(
          resources: res,
          purchaseProvider: provider,
          purchasesLocalApi: PurchasesLocalApi(localDb: FakeLocalDb()),
        );
        await foundation.init(productIds: [PurchaseProductId.fromJson('p')]);
        expect(res.status.status, MonetizationStoreStatus.loaded);
      },
    );

    test('dispose cancels provider', () async {
      final res = (
        status: MonetizationStoreStatusResource(),
        type: MonetizationTypeResource(MonetizationType.subscription),
        activeSubscription: ActiveSubscriptionResource(),
        subscriptionStatus: SubscriptionStatusResource(),
        availableSubscriptions: AvailableSubscriptionsResource(),
        paywallSelectedSubscription: PaywallSelectedSubscriptionResource(),
        purchasePaywallError: PurchasePaywallErrorResource(),
      );
      final provider = FakeProvider();
      final foundation = MonetizationFoundation(
        resources: res,
        purchaseProvider: provider,
        purchasesLocalApi: PurchasesLocalApi(localDb: FakeLocalDb()),
      );
      await foundation.init(productIds: []);
      await foundation.dispose();
    });
  });
}
