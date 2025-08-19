import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_monetization_foundation/xsoulspace_monetization_foundation.dart';
// ignore_for_file: unused_import
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import '../support/builders.dart';
import '../support/harness.dart';
import '../support/matchers.dart';

void main() {
  late MonetizationTestEnv env;

  setUp(() => env = MonetizationTestEnv()..setUp());
  tearDown(() => env.tearDown());

  group('HandlePurchaseUpdateCommand', () {
    test('pending sets purchasing', () async {
      final cmd = env.makeHandlePurchaseUpdateCommand();
      await cmd.execute(aPurchase(pending: true));
      expect(env.subscriptionStatus, isPurchasingStatus());
    });

    test('purchased delegates to confirm and saves active', () async {
      env.givenCompleteSuccess();
      // Need to rewire confirm command with the new provider in env
      final cmd = env.makeHandlePurchaseUpdateCommand();
      await cmd.execute(aPurchase(active: true));
      expect(env.subscriptionStatus, isSubscribed());
      expect(env.provider.completeCalls, 1);
    });

    test('canceled clears to free', () async {
      // Seed active subscription in env
      env.activeSubscription = ActiveSubscriptionResource(
        aPurchase(active: true),
      );
      final cmd = env.makeHandlePurchaseUpdateCommand();
      await cmd.execute(aPurchase(cancelled: true));
      expect(env.subscriptionStatus, isFreeStatus());
    });
  });
}
