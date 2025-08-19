import 'package:flutter_test/flutter_test.dart';
// ignore_for_file: unused_import
import 'package:xsoulspace_monetization_foundation/xsoulspace_monetization_foundation.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import '../support/builders.dart';
import '../support/harness.dart';
import '../support/matchers.dart';

void main() {
  late MonetizationTestEnv env;

  setUp(() => env = MonetizationTestEnv()..setUp());
  tearDown(() => env.tearDown());

  group('ConfirmPurchaseCommand', () {
    test('ignores pending/canceled', () async {
      final cmd = env.makeConfirmPurchaseCommand();
      expect(await cmd.execute(aVerification()), isTrue);
      // cancel and pure pending should return false
      expect(
        await cmd.execute(aVerification(status: PurchaseStatus.canceled)),
        isFalse,
      );
      expect(
        await cmd.execute(aVerification(status: PurchaseStatus.pending)),
        isFalse,
      );
    });

    test(
      'sets subscribed when provider completes success and status is purchased',
      () async {
        env.givenCompleteSuccess();
        final cmd = env.makeConfirmPurchaseCommand();

        final ok = await cmd.execute(aVerification());

        expect(ok, isTrue);
        expect(env.subscriptionStatus, isSubscribed());
        expect(
          env.activeSubscription.isActive,
          isFalse,
          reason: 'active details set via getPurchaseDetails minimal stub',
        );
      },
    );

    test('sets error and free on failure', () async {
      env.givenCompleteFailure('e');
      final cmd = env.makeConfirmPurchaseCommand();
      final ok = await cmd.execute(
        aVerification(status: PurchaseStatus.pendingConfirmation),
      );
      expect(ok, isFalse);
      expect(env.purchasePaywallError, hasError());
      expect(env.subscriptionStatus, isFreeStatus());
    });
  });
}
