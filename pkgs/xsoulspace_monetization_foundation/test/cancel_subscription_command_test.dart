import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_monetization_foundation/xsoulspace_monetization_foundation.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import 'support/fakes.dart';

void main() {
  group('CancelSubscriptionCommand', () {
    test('no active and no ids -> no-op', () async {
      final status = SubscriptionStatusResource();
      final cmd = CancelSubscriptionCommand(
        purchaseProvider: FakeProvider(),
        activeSubscriptionResource: ActiveSubscriptionResource(),
        subscriptionStatusResource: status,
        restorePurchasesCommand: RestorePurchasesCommand(
          purchaseProvider: FakeProvider(),
          purchasesLocalApi: PurchasesLocalApi(localDb: FakeLocalDb()),
          handlePurchaseUpdateCommand: HandlePurchaseUpdateCommand(
            confirmPurchaseCommand: ConfirmPurchaseCommand(
              purchaseProvider: FakeProvider(),
              activeSubscriptionResource: ActiveSubscriptionResource(),
              subscriptionStatusResource: status,
              purchasePaywallErrorResource: PurchasePaywallErrorResource(),
            ),
            subscriptionStatusResource: status,
            activeSubscriptionResource: ActiveSubscriptionResource(),
            purchasesLocalApi: PurchasesLocalApi(localDb: FakeLocalDb()),
          ),
          subscriptionStatusResource: status,
        ),
      );
      await cmd.execute();
      expect(status.isCancelling, isFalse);
    });

    test('uses explicit purchaseId when provided', () async {
      final status = SubscriptionStatusResource();
      final provider = FakeProvider();
      final cmd = CancelSubscriptionCommand(
        purchaseProvider: provider,
        activeSubscriptionResource: ActiveSubscriptionResource(),
        subscriptionStatusResource: status,
        restorePurchasesCommand: RestorePurchasesCommand(
          purchaseProvider: provider,
          purchasesLocalApi: PurchasesLocalApi(localDb: FakeLocalDb()),
          handlePurchaseUpdateCommand: HandlePurchaseUpdateCommand(
            confirmPurchaseCommand: ConfirmPurchaseCommand(
              purchaseProvider: provider,
              activeSubscriptionResource: ActiveSubscriptionResource(),
              subscriptionStatusResource: status,
              purchasePaywallErrorResource: PurchasePaywallErrorResource(),
            ),
            subscriptionStatusResource: status,
            activeSubscriptionResource: ActiveSubscriptionResource(),
            purchasesLocalApi: PurchasesLocalApi(localDb: FakeLocalDb()),
          ),
          subscriptionStatusResource: status,
        ),
      );
      await cmd.execute(purchaseId: PurchaseId.fromJson('abc'));
      expect(provider.cancelCalls, 1);
    });
  });
}
