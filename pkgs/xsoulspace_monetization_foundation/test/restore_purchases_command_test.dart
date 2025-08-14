import 'package:flutter_test/flutter_test.dart';

import 'support/builders.dart';
import 'support/harness.dart';
import 'support/matchers.dart';

void main() {
  group('RestorePurchasesCommand', () {
    late MonetizationTestEnv env;

    setUp(() => env = MonetizationTestEnv()..setUp());
    tearDown(() => env.tearDown());

    test('does not downgrade when already subscribed locally', () async {
      final active = aPurchase(active: true);
      await env.purchasesLocalApi.saveActiveSubscription(active);

      env.givenRestoreFailure('net');
      final cmd = env.makeRestorePurchasesCommand();

      await cmd.execute();

      expect(env.subscriptionStatus, isSubscribed());
    });

    test('sets free when no local active and no restored purchases', () async {
      env.givenRestoreSuccess();
      final cmd = env.makeRestorePurchasesCommand();

      await cmd.execute();

      expect(env.subscriptionStatus, isFreeStatus());
    });
  });
}
