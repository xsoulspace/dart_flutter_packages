import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_monetization_foundation/xsoulspace_monetization_foundation.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import 'support/fakes.dart';

void main() {
  group('SubscribeCommand', () {
    test('returns false if already subscribed', () async {
      final status = SubscriptionStatusResource()
        ..set(SubscriptionStatus.subscribed);
      final cmd = SubscribeCommand(
        purchaseProvider: FakeProvider(),
        subscriptionStatusResource: status,
        confirmPurchaseCommand: ConfirmPurchaseCommand(
          purchaseProvider: FakeProvider(),
          activeSubscriptionResource: ActiveSubscriptionResource(),
          subscriptionStatusResource: status,
          purchasePaywallErrorResource: PurchasePaywallErrorResource(),
        ),
        cancelSubscriptionCommand: CancelSubscriptionCommand(
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
        ),
        purchasePaywallErrorResource: PurchasePaywallErrorResource(),
      );

      final res = await cmd.execute(
        PurchaseProductDetailsModel(
          freeTrialDuration: PurchaseDurationModel.zero,
        ),
      );
      expect(res, isFalse);
    });

    test('sets pending then confirms on provider success', () async {
      final status = SubscriptionStatusResource();
      final provider = FakeProvider(
        subscribeResult: PurchaseResultModel.success(
          purchase(pendingConfirmation: true),
          shouldConfirmPurchase: true,
        ),
      );
      final cmd = SubscribeCommand(
        purchaseProvider: provider,
        subscriptionStatusResource: status,
        confirmPurchaseCommand: ConfirmPurchaseCommand(
          purchaseProvider: provider,
          activeSubscriptionResource: ActiveSubscriptionResource(),
          subscriptionStatusResource: status,
          purchasePaywallErrorResource: PurchasePaywallErrorResource(),
        ),
        cancelSubscriptionCommand: CancelSubscriptionCommand(
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
        ),
        purchasePaywallErrorResource: PurchasePaywallErrorResource(),
      );

      final ok = await cmd.execute(
        PurchaseProductDetailsModel(
          freeTrialDuration: PurchaseDurationModel.zero,
        ),
      );

      expect(ok, isTrue);
      expect(
        status.isPendingConfirmation,
        isFalse,
        reason: 'should confirm and set subscribed',
      );
      expect(status.isSubscribed, isTrue);
      expect(provider.completeCalls, 1);
    });

    test('on failure sets free and triggers cancel flow for upgrades', () async {
      final status = SubscriptionStatusResource();
      final provider = FakeProvider(
        subscribeResult: PurchaseResultModel.failure('err'),
      );
      final cmd = SubscribeCommand(
        purchaseProvider: provider,
        subscriptionStatusResource: status,
        confirmPurchaseCommand: ConfirmPurchaseCommand(
          purchaseProvider: provider,
          activeSubscriptionResource: ActiveSubscriptionResource(),
          subscriptionStatusResource: status,
          purchasePaywallErrorResource: PurchasePaywallErrorResource(),
        ),
        cancelSubscriptionCommand: CancelSubscriptionCommand(
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
        ),
        purchasePaywallErrorResource: PurchasePaywallErrorResource(),
      );

      final ok = await cmd.execute(
        PurchaseProductDetailsModel(
          freeTrialDuration: PurchaseDurationModel.zero,
        ),
      );
      expect(ok, isFalse);
      expect(status.isFree, isTrue);
      expect(
        provider.cancelCalls,
        0,
        reason:
            'cancel is called inside cancelSubscriptionCommand only when needed',
      );
    });
  });
}
