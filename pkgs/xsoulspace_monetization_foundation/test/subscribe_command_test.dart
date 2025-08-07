import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_monetization_foundation/xsoulspace_monetization_foundation.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import 'support/builders.dart';
import 'support/harness.dart';
import 'support/matchers.dart';

void main() {
  late MonetizationTestEnv env;

  setUp(() => env = MonetizationTestEnv()..setUp());
  tearDown(() => env.tearDown());

  group('SubscribeCommand', () {
    test('does nothing if already subscribed', () async {
      env.subscriptionStatus.set(SubscriptionStatus.subscribed);
      final cmd = env.makeSubscribeCommand();

      await cmd.execute(aProduct(freeTrial: PurchaseDurationModel.zero));

      expect(env.subscriptionStatus, isSubscribed());
      expect(env.provider.subscribeCalls, 0);
    });

    test('sets pending then confirms on provider success', () async {
      env.givenSubscribeSuccess();
      final cmd = env.makeSubscribeCommand();

      await cmd.execute(aProduct(freeTrial: PurchaseDurationModel.zero));

      expect(
        env.subscriptionStatus.isPendingConfirmation,
        isFalse,
        reason: 'should confirm and set subscribed',
      );
      expect(env.subscriptionStatus, isSubscribed());
      expect(env.provider.completeCalls, 1);
      expect(env.provider.subscribeCalls, 1);
    });

    test('success without confirmation leaves status pending', () async {
      env.givenSubscribeSuccess(shouldConfirm: false);
      final cmd = env.makeSubscribeCommand();

      await cmd.execute(aProduct(freeTrial: PurchaseDurationModel.zero));

      expect(env.subscriptionStatus, isPendingConfirmationStatus());
      expect(env.provider.completeCalls, 0);
      expect(env.provider.subscribeCalls, 1);
    });

    test(
      'failure without details leaves purchasing; resolved asynchronously',
      () async {
        env.givenSubscribeFailure();
        final cmd = env.makeSubscribeCommand();

        await cmd.execute(aProduct(freeTrial: PurchaseDurationModel.zero));
        await Future<void>.delayed(Duration.zero);
        expect(env.subscriptionStatus, isPurchasingStatus());
        expect(env.purchasePaywallError, hasNoError());
        expect(env.provider.cancelCalls, 0);
      },
    );
  });
}
