import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_monetization_foundation/xsoulspace_monetization_foundation.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import 'support/fakes.dart';

void main() {
  group('ConfirmPurchaseCommand', () {
    test('ignores pending/canceled', () async {
      final status = SubscriptionStatusResource();
      final cmd = ConfirmPurchaseCommand(
        purchaseProvider: FakeProvider(),
        activeSubscriptionResource: ActiveSubscriptionResource(),
        subscriptionStatusResource: status,
        purchasePaywallErrorResource: PurchasePaywallErrorResource(),
      );
      final pending = PurchaseVerificationDtoModel(
        transactionDate: DateTime.now(),
      );
      final canceled = PurchaseVerificationDtoModel(
        transactionDate: DateTime.now(),
        status: PurchaseStatus.canceled,
      );
      expect(await cmd.execute(pending), isFalse);
      expect(await cmd.execute(canceled), isFalse);
    });

    test(
      'sets subscribed when provider completes success and status is purchased',
      () async {
        final status = SubscriptionStatusResource();
        final active = ActiveSubscriptionResource();
        final provider = FakeProvider(
          completeResult: CompletePurchaseResultModel.success(),
        );
        final cmd = ConfirmPurchaseCommand(
          purchaseProvider: provider,
          activeSubscriptionResource: active,
          subscriptionStatusResource: status,
          purchasePaywallErrorResource: PurchasePaywallErrorResource(),
        );
        final ok = await cmd.execute(
          PurchaseVerificationDtoModel(
            transactionDate: DateTime.now(),
            status: PurchaseStatus.purchased,
          ),
        );
        expect(ok, isTrue);
        expect(status.isSubscribed, isTrue);
        expect(
          active.isActive,
          isFalse,
          reason: 'active details set via getPurchaseDetails minimal stub',
        );
      },
    );

    test('sets error and free on failure', () async {
      final status = SubscriptionStatusResource();
      final err = PurchasePaywallErrorResource();
      final cmd = ConfirmPurchaseCommand(
        purchaseProvider: FakeProvider(
          completeResult: CompletePurchaseResultModel.failure('e'),
        ),
        activeSubscriptionResource: ActiveSubscriptionResource(),
        subscriptionStatusResource: status,
        purchasePaywallErrorResource: err,
      );
      final ok = await cmd.execute(
        PurchaseVerificationDtoModel(
          transactionDate: DateTime.now(),
          status: PurchaseStatus.pendingConfirmation,
        ),
      );
      expect(ok, isFalse);
      expect(err.hasError, isTrue);
      expect(status.isFree, isTrue);
    });
  });
}
