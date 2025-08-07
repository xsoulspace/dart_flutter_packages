import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_monetization_foundation/xsoulspace_monetization_foundation.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import 'support/fakes.dart';

void main() {
  group('SubscribeCommand', () {
    test('does nothing if already subscribed', () async {
      final status = SubscriptionStatusResource()
        ..set(SubscriptionStatus.subscribed);
      final provider = FakeProvider();
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

      await cmd.execute(
        PurchaseProductDetailsModel(
          freeTrialDuration: PurchaseDurationModel.zero,
        ),
      );
      expect(status.isSubscribed, isTrue);
      expect(provider.subscribeCalls, 0);
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

      await cmd.execute(
        PurchaseProductDetailsModel(
          freeTrialDuration: PurchaseDurationModel.zero,
        ),
      );
      expect(
        status.isPendingConfirmation,
        isFalse,
        reason: 'should confirm and set subscribed',
      );
      expect(status.isSubscribed, isTrue);
      expect(provider.completeCalls, 1);
      expect(provider.subscribeCalls, 1);
    });

    test('success without confirmation leaves status pending', () async {
      final status = SubscriptionStatusResource();
      final provider = FakeProvider(
        subscribeResult: PurchaseResultModel.success(
          purchase(pendingConfirmation: true),
          shouldConfirmPurchase: false,
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
      await cmd.execute(
        PurchaseProductDetailsModel(
          freeTrialDuration: PurchaseDurationModel.zero,
        ),
      );
      expect(status.isPendingConfirmation, isTrue);
      expect(provider.completeCalls, 0);
      expect(provider.subscribeCalls, 1);
    });

    test(
      'failure without details leaves purchasing; resolved asynchronously',
      () async {
        final status = SubscriptionStatusResource();
        final provider = FakeProvider(
          subscribeResult: PurchaseResultModel(
            details: purchase(),
            type: ResultType.failure,
            error: 'err',
          ),
        );
        final errRes = PurchasePaywallErrorResource();
        final cmd = SubscribeCommand(
          purchaseProvider: provider,
          subscriptionStatusResource: status,
          confirmPurchaseCommand: ConfirmPurchaseCommand(
            purchaseProvider: provider,
            activeSubscriptionResource: ActiveSubscriptionResource(),
            subscriptionStatusResource: status,
            purchasePaywallErrorResource: errRes,
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
                  purchasePaywallErrorResource: errRes,
                ),
                subscriptionStatusResource: status,
                activeSubscriptionResource: ActiveSubscriptionResource(),
                purchasesLocalApi: PurchasesLocalApi(localDb: FakeLocalDb()),
              ),
              subscriptionStatusResource: status,
            ),
          ),
          purchasePaywallErrorResource: errRes,
        );

        await cmd.execute(
          PurchaseProductDetailsModel(
            freeTrialDuration: PurchaseDurationModel.zero,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(status.isPurchasing, isTrue);
        expect(errRes.hasError, isFalse);
        expect(provider.cancelCalls, 0);
      },
    );
  });
}
