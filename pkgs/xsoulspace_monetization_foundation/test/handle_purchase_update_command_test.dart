import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_monetization_foundation/xsoulspace_monetization_foundation.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import 'support/fakes.dart';

void main() {
  group('HandlePurchaseUpdateCommand', () {
    test('pending sets purchasing', () async {
      final status = SubscriptionStatusResource();
      final cmd = HandlePurchaseUpdateCommand(
        confirmPurchaseCommand: ConfirmPurchaseCommand(
          purchaseProvider: FakeProvider(),
          activeSubscriptionResource: ActiveSubscriptionResource(),
          subscriptionStatusResource: status,
          purchasePaywallErrorResource: PurchasePaywallErrorResource(),
        ),
        subscriptionStatusResource: status,
        activeSubscriptionResource: ActiveSubscriptionResource(),
        purchasesLocalApi: PurchasesLocalApi(localDb: FakeLocalDb()),
      );
      await cmd.execute(purchase(pending: true));
      expect(status.isPurchasing, isTrue);
    });

    test('purchased delegates to confirm and saves active', () async {
      final status = SubscriptionStatusResource();
      final active = ActiveSubscriptionResource();
      final local = PurchasesLocalApi(localDb: FakeLocalDb());
      final provider = FakeProvider(
        completeResult: CompletePurchaseResultModel.success(),
      );
      final cmd = HandlePurchaseUpdateCommand(
        confirmPurchaseCommand: ConfirmPurchaseCommand(
          purchaseProvider: provider,
          activeSubscriptionResource: active,
          subscriptionStatusResource: status,
          purchasePaywallErrorResource: PurchasePaywallErrorResource(),
        ),
        subscriptionStatusResource: status,
        activeSubscriptionResource: active,
        purchasesLocalApi: local,
      );
      await cmd.execute(purchase(active: true));
      expect(status.isSubscribed, isTrue);
    });

    test('canceled clears to free', () async {
      final status = SubscriptionStatusResource();
      final active = ActiveSubscriptionResource(purchase(active: true));
      final cmd = HandlePurchaseUpdateCommand(
        confirmPurchaseCommand: ConfirmPurchaseCommand(
          purchaseProvider: FakeProvider(),
          activeSubscriptionResource: active,
          subscriptionStatusResource: status,
          purchasePaywallErrorResource: PurchasePaywallErrorResource(),
        ),
        subscriptionStatusResource: status,
        activeSubscriptionResource: active,
        purchasesLocalApi: PurchasesLocalApi(localDb: FakeLocalDb()),
      );
      await cmd.execute(purchase(cancelled: true));
      expect(status.isFree, isTrue);
    });
  });
}
