import 'package:flutter_test/flutter_test.dart';
// ignore_for_file: unused_import
import 'package:xsoulspace_monetization_foundation/xsoulspace_monetization_foundation.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import 'support/harness.dart';

void main() {
  late MonetizationTestEnv env;

  setUp(() => env = MonetizationTestEnv()..setUp());
  tearDown(() => env.tearDown());

  group('CancelSubscriptionCommand', () {
    test('no active and no ids -> no-op', () async {
      final cmd = env.makeCancelSubscriptionCommand();
      await cmd.execute();
      expect(env.subscriptionStatus.isCancelling, isFalse);
    });

    test('uses explicit purchaseId when provided', () async {
      final cmd = env.makeCancelSubscriptionCommand();
      await cmd.execute(purchaseId: PurchaseId.fromJson('abc'));
      expect(env.provider.cancelCalls, 1);
    });
  });
}
